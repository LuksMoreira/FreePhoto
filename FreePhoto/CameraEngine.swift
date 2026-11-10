import AVFoundation
import Combine
import CoreImage
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

enum CaptureMode: String, CaseIterable, Identifiable {
    case bayer = "RAW Bayer"
    case proRAW = "ProRAW Max"
    case jpeg = "JPEG"
    case png = "PNG"
    var isRAW: Bool { self == .bayer || self == .proRAW }
    var fileExtension: String { isRAW ? "dng" : (self == .jpeg ? "jpg" : "png") }
    var id: String { rawValue }
    var explanation: String {
        switch self {
        case .bayer: return "DNG Bayer, sem filtros do app. A resolução RAW pode ser inferior ao máximo do sensor."
        case .proRAW: return "DNG com processamento computacional da Apple. Solicita a maior resolução anunciada pela lente."
        case .jpeg: return "JPEG processado pelo iOS. Arquivo compacto, com compressão com perdas."
        case .png: return "PNG sem perdas na codificação, gerado da imagem processada pelo iOS. Não é RAW nem significa ausência de processamento."
        }
    }
}

struct Lens: Identifiable {
    let device: AVCaptureDevice
    var id: String { device.uniqueID }
    var name: String {
        if device.position == .front { return "Frontal" }
        switch device.deviceType {
        case .builtInUltraWideCamera: return "Ultra-angular"
        case .builtInTelephotoCamera: return "Teleobjetiva"
        default: return "Principal"
        }
    }
    var maximum: CMVideoDimensions {
        device.formats.flatMap(\.supportedMaxPhotoDimensions).max { area($0) < area($1) }
            ?? CMVideoDimensions(width: 0, height: 0)
    }
    var details: String {
        "\(device.localizedName) · ƒ/\(String(format: "%.1f", device.lensAperture)) · até \(megapixels(maximum))"
    }
}

func area(_ d: CMVideoDimensions) -> Int64 { Int64(d.width) * Int64(d.height) }
func megapixels(_ d: CMVideoDimensions) -> String {
    String(format: "%.1f MP", Double(area(d)) / 1_000_000)
}

struct SavedShot: Identifiable {
    let id = UUID()
    let url: URL
    let reportURL: URL
    let summary: String
}

struct ManualSettings: Codable {
    var automaticExposure = true
    var iso: Double = 100
    var exposureSeconds: Double = 1 / 125
    var automaticFocus = true
    var focus: Double = 0.5
    var automaticWhiteBalance = true
    var temperature: Double = 5500
    var tint: Double = 0
}

struct PhotoResolution: Identifiable {
    let dimensions: CMVideoDimensions
    var id: String { "\(dimensions.width)x\(dimensions.height)" }
    var label: String { "\(megapixels(dimensions)) · \(dimensions.width) × \(dimensions.height)" }
}

struct ManualControlState {
    var settings = ManualSettings()
    var supportsExposure = false
    var supportsFocus = false
    var supportsWhiteBalance = false
    var minISO: Double = 100
    var maxISO: Double = 101
    var minExposure: Double = 1 / 8000
    var maxExposure: Double = 1
    var aperture: Double = 0
    var resolutions: [PhotoResolution] = []
    var resolutionID = ""
}

private struct RawCapture {
    let data: Data
    let dimensions: CMVideoDimensions
    let exifISO: Double?
    let exifExposureSeconds: Double?
    let exifAperture: Double?
}

private struct CaptureReport: Codable {
    let capturedAt: Date
    let mode: String
    let deviceID: String
    let deviceName: String
    let requestedWidth: Int32
    let requestedHeight: Int32
    let deliveredWidth: Int32
    let deliveredHeight: Int32
    let rawPixelFormat: UInt32?
    let originalBytes: Int
    let controls: ManualSettings
    let exifISO: Double?
    let exifExposureSeconds: Double?
    let exifAperture: Double?
    let note: String
}

private struct CameraFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Capture-session state is confined to sessionQueue. Published values are written on main.
final class CameraEngine: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var lenses: [Lens] = []
    @Published private(set) var selectedID = ""
    @Published private(set) var mode: CaptureMode = .bayer
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var status = "Preparando câmera…"
    @Published private(set) var capability = ""
    @Published private(set) var lastShot: SavedShot?
    @Published private(set) var controlState = ManualControlState()
    @Published private(set) var controlsBusy = false
    @Published private(set) var lastShotInPhotos = false
    @Published var errorMessage: String?

    private let sessionQueue = DispatchQueue(label: "FreePhoto.session", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var currentMode: CaptureMode = .bayer
    private var manual = ManualSettings()
    private var adjustingControls = false
    private var requestedDimensions = CMVideoDimensions(width: 0, height: 0)
    private var pending: PhotoReceiver?
    private var wantsRunning = false
    private var interrupted = false
    private var notificationTokens: [NSObjectProtocol] = []
    private var importedPhotos = Set<URL>()
    private var importingPhotos = Set<URL>()

    override init() {
        super.init()
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: .AVCaptureSessionWasInterrupted,
            object: session, queue: nil) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in
                    guard let self else { return }
                    self.interrupted = true
                    self.publish(ready: false, status: "Câmera interrompida. Aguarde ou reabra o app.")
                }
            })
        notificationTokens.append(center.addObserver(forName: .AVCaptureSessionInterruptionEnded,
            object: session, queue: nil) { [weak self] _ in self?.start() })
        notificationTokens.append(center.addObserver(forName: .AVCaptureSessionRuntimeError,
            object: session, queue: nil) { [weak self] note in
                let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                    ?? "Erro na sessão. Volte ao app para tentar novamente."
                self?.sessionQueue.async { [weak self] in self?.publish(ready: false, status: message) }
            })
    }

    deinit {
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
    }

    func start() {
        sessionQueue.async {
            self.wantsRunning = true
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.startAuthorized()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    self.sessionQueue.async {
                        if granted { self.startAuthorized() } else { self.denyCamera() }
                    }
                }
            default: self.denyCamera()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.wantsRunning = false
            if self.session.isRunning { self.session.stopRunning() }
            self.publish(ready: false, status: "Câmera pausada")
        }
    }

    private func denyCamera() {
        DispatchQueue.main.async {
            self.permissionDenied = true
            self.ready = false
            self.status = "Permita o acesso à câmera nos Ajustes."
        }
    }

    private func startAuthorized() {
        guard wantsRunning else { return }
        interrupted = false
        do {
            if input == nil {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera,
                                  .builtInTelephotoCamera, .builtInTrueDepthCamera],
                    mediaType: .video, position: .unspecified)
                // TrueDepth and wide-angle can represent the same front color camera.
                // Keep one front color camera, but every distinct rear physical camera.
                var devices = discovery.devices.filter { !$0.isVirtualDevice }
                let front = devices.first { $0.position == .front && $0.deviceType == .builtInTrueDepthCamera }
                    ?? devices.first { $0.position == .front }
                devices = devices.filter { $0.position != .front }
                if let front { devices.append(front) }
                let found = devices.map { Lens(device: $0) }.sorted {
                    if $0.device.position != $1.device.position { return $0.device.position == .back }
                    return $0.device.activeFormat.videoFieldOfView > $1.device.activeFormat.videoFieldOfView
                }
                guard let initial = found.first(where: { $0.device.position == .back &&
                    $0.device.deviceType == .builtInWideAngleCamera }) ?? found.first else {
                    throw CameraFailure(message: "Nenhuma câmera disponível. Use um iPhone físico.")
                }
                DispatchQueue.main.async { self.lenses = found; self.permissionDenied = false }
                try configure(device: initial.device, mode: currentMode)
            }
            if !session.isRunning { session.startRunning() }
            refreshAvailability()
        } catch { fail(error) }
    }

    func select(_ lens: Lens) {
        sessionQueue.async {
            guard self.pending == nil, !self.adjustingControls, self.wantsRunning else { return }
            self.publish(ready: false, status: "Trocando lente…")
            do {
                try self.configure(device: lens.device, mode: self.currentMode)
                self.refreshAvailability()
            } catch { self.fail(error) }
        }
    }

    func selectMode(_ mode: CaptureMode) {
        sessionQueue.async {
            guard self.pending == nil, !self.adjustingControls,
                  let device = self.input?.device, self.wantsRunning else { return }
            self.publish(ready: false, status: "Configurando formato…")
            do {
                try self.configure(device: device, mode: mode)
                self.refreshAvailability()
            } catch { self.fail(error) }
        }
    }

    private func configure(device: AVCaptureDevice, mode: CaptureMode) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        let newInput = try AVCaptureDeviceInput(device: device)
        let oldInput = input
        if let oldInput { session.removeInput(oldInput) }
        guard session.canAddInput(newInput) else {
            if let oldInput, session.canAddInput(oldInput) { session.addInput(oldInput) }
            throw CameraFailure(message: "Não foi possível conectar essa câmera.")
        }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else {
                session.removeInput(newInput)
                input = nil
                throw CameraFailure(message: "Saída de fotografia indisponível.")
            }
            session.addOutput(output)
        }

        // ProRAW seeks the largest advertised still format. Bayer uses a regular
        // <=12.6 MP still size when available, rather than assuming 48 MP Bayer.
        let candidates = device.formats.flatMap { format in
            format.supportedMaxPhotoDimensions.map { (format, $0) }
        }
        let bayerCandidates = candidates.filter { area($0.1) <= 12_600_000 }
        let pool = mode == .bayer && !bayerCandidates.isEmpty ? bayerCandidates : candidates
        guard let chosen = pool.max(by: { area($0.1) < area($1.1) }) else {
            throw CameraFailure(message: "Essa lente não anuncia dimensões de fotografia.")
        }
        try device.lockForConfiguration()
        device.activeFormat = chosen.0
        device.videoZoomFactor = 1 // physical lens, no crop/digital zoom
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.unlockForConfiguration()

        if output.isAppleProRAWSupported { output.isAppleProRAWEnabled = mode == .proRAW }
        output.maxPhotoDimensions = chosen.1
        requestedDimensions = chosen.1
        output.maxPhotoQualityPrioritization = .quality
        if output.isLivePhotoCaptureSupported { output.isLivePhotoCaptureEnabled = false }
        currentMode = mode
        // A different physical lens/format has different limits. Start safely in Auto.
        manual = ManualSettings()
        publishControls(device: device)
        DispatchQueue.main.async { self.mode = mode; self.selectedID = device.uniqueID }
    }

    private func bounded(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        value.isFinite ? min(max(value, lower), upper) : lower
    }

    private func publishControls(device: AVCaptureDevice) {
        let format = device.activeFormat
        var snapshot = ManualControlState()
        snapshot.supportsExposure = device.isExposureModeSupported(.custom)
        snapshot.supportsFocus = device.isFocusModeSupported(.locked)
            && device.isLockingFocusWithCustomLensPositionSupported
        snapshot.supportsWhiteBalance = device.isWhiteBalanceModeSupported(.locked)
            && device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        snapshot.minISO = Double(format.minISO)
        snapshot.maxISO = Double(format.maxISO)
        snapshot.minExposure = CMTimeGetSeconds(format.minExposureDuration)
        snapshot.maxExposure = CMTimeGetSeconds(format.maxExposureDuration)
        snapshot.aperture = Double(device.lensAperture)
        let wb = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
        var values = manual
        values.iso = bounded(Double(device.iso), snapshot.minISO, snapshot.maxISO)
        values.exposureSeconds = bounded(CMTimeGetSeconds(device.exposureDuration),
            snapshot.minExposure, snapshot.maxExposure)
        values.focus = bounded(Double(device.lensPosition), 0, 1)
        values.temperature = bounded(Double(wb.temperature), 2000, 15000)
        values.tint = bounded(Double(wb.tint), -150, 150)
        snapshot.settings = values
        manual = values
        let ceiling = area(output.maxPhotoDimensions)
        var seen = Set<String>()
        snapshot.resolutions = format.supportedMaxPhotoDimensions
            .filter { area($0) <= ceiling }
            .map { PhotoResolution(dimensions: $0) }
            .filter { seen.insert($0.id).inserted }
            .sorted { area($0.dimensions) < area($1.dimensions) }
        snapshot.resolutionID = PhotoResolution(dimensions: requestedDimensions).id
        DispatchQueue.main.async { self.controlState = snapshot }
    }

    func refreshControls() {
        sessionQueue.async {
            guard self.pending == nil, !self.adjustingControls, let device = self.input?.device else { return }
            self.publishControls(device: device)
        }
    }

    func applyControls(_ requested: ManualSettings, resolutionID: String) {
        sessionQueue.async {
            guard self.pending == nil, !self.adjustingControls, self.wantsRunning,
                  let device = self.input?.device else { return }
            do {
                guard requested.automaticExposure || device.isExposureModeSupported(.custom) else {
                    throw CameraFailure(message: "Exposição manual indisponível nesta lente/formato.")
                }
                guard requested.automaticFocus || (device.isFocusModeSupported(.locked)
                    && device.isLockingFocusWithCustomLensPositionSupported) else {
                    throw CameraFailure(message: "Foco manual indisponível nesta lente.")
                }
                guard requested.automaticWhiteBalance || (device.isWhiteBalanceModeSupported(.locked)
                    && device.isLockingWhiteBalanceWithCustomDeviceGainsSupported) else {
                    throw CameraFailure(message: "Balanço de branco manual indisponível nesta lente.")
                }
                guard let resolution = device.activeFormat.supportedMaxPhotoDimensions.first(where: {
                    PhotoResolution(dimensions: $0).id == resolutionID && area($0) <= area(self.output.maxPhotoDimensions)
                }) else { throw CameraFailure(message: "Selecione uma resolução disponível para o formato atual.") }

                var accepted = requested
                let format = device.activeFormat
                accepted.iso = self.bounded(requested.iso, Double(format.minISO), Double(format.maxISO))
                accepted.exposureSeconds = self.bounded(requested.exposureSeconds,
                    CMTimeGetSeconds(format.minExposureDuration), CMTimeGetSeconds(format.maxExposureDuration))
                accepted.focus = self.bounded(requested.focus, 0, 1)
                accepted.temperature = self.bounded(requested.temperature, 2000, 15000)
                accepted.tint = self.bounded(requested.tint, -150, 150)

                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                self.adjustingControls = true
                DispatchQueue.main.async { self.controlsBusy = true }
                self.publish(ready: false, status: "Aplicando controles…")
                let settled = DispatchGroup()
                if accepted.automaticExposure {
                    if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                } else {
                    settled.enter()
                    let rounded = CMTime(seconds: accepted.exposureSeconds, preferredTimescale: 1_000_000_000)
                    let duration = CMTimeMaximum(format.minExposureDuration,
                        CMTimeMinimum(format.maxExposureDuration, rounded))
                    device.setExposureModeCustom(duration: duration, iso: Float(accepted.iso)) { _ in settled.leave() }
                }
                if accepted.automaticFocus {
                    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                } else {
                    settled.enter()
                    device.setFocusModeLocked(lensPosition: Float(accepted.focus)) { _ in settled.leave() }
                }
                if accepted.automaticWhiteBalance {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                } else {
                    let temperature = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                        temperature: Float(accepted.temperature), tint: Float(accepted.tint))
                    var gains = device.deviceWhiteBalanceGains(for: temperature)
                    let maxGain = Double(device.maxWhiteBalanceGain)
                    gains.redGain = Float(self.bounded(Double(gains.redGain), 1, maxGain))
                    gains.greenGain = Float(self.bounded(Double(gains.greenGain), 1, maxGain))
                    gains.blueGain = Float(self.bounded(Double(gains.blueGain), 1, maxGain))
                    settled.enter()
                    device.setWhiteBalanceModeLocked(with: gains) { _ in settled.leave() }
                }
                self.manual = accepted
                self.requestedDimensions = resolution
                // Do not allow capture until all asynchronous manual adjustments settle.
                settled.notify(queue: self.sessionQueue) {
                    self.adjustingControls = false
                    self.publishControls(device: device)
                    self.refreshAvailability()
                    DispatchQueue.main.async { self.controlsBusy = false }
                }
            } catch { self.fail(error) }
        }
    }

    private func rawFormat() -> OSType? {
        guard currentMode.isRAW else { return nil }
        return output.availableRawPhotoPixelFormatTypes.first {
            currentMode == .bayer ? AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
                : AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
        }
    }

    private func supportsCapture() -> Bool {
        switch currentMode {
        case .bayer, .proRAW: return rawFormat() != nil
        case .jpeg: return output.availablePhotoCodecTypes.contains(.jpeg)
        case .png: return output.availablePhotoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA)
        }
    }

    private func refreshAvailability() {
        let supported = supportsCapture()
        let d = requestedDimensions
        DispatchQueue.main.async {
            self.capability = "Solicitado: até \(megapixels(d)) · \(d.width) × \(d.height)"
        }
        publish(ready: supported && session.isRunning && wantsRunning && !interrupted && !adjustingControls && pending == nil,
            status: supported ? "Pronto · \(currentMode.rawValue) → Fotos" : "\(currentMode.rawValue) indisponível nesta lente. Escolha outra lente ou modo.")
    }

    func capture() {
        sessionQueue.async {
            guard self.pending == nil, !self.adjustingControls, self.wantsRunning, self.session.isRunning,
                  !self.interrupted, let device = self.input?.device, self.supportsCapture() else { return }
            self.publish(ready: false, status: "Capturando…")
            DispatchQueue.main.async { self.busy = true }
            let raw = self.rawFormat()
            let settings: AVCapturePhotoSettings
            if let raw { settings = AVCapturePhotoSettings(rawPixelFormatType: raw) }
            else if self.currentMode == .jpeg {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                // PNG uses uncompressed processed pixels, avoiding a lossy JPEG intermediate.
                settings = AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            }
            settings.maxPhotoDimensions = self.requestedDimensions
            settings.flashMode = .off
            // Apple requires .speed to honor custom ISO/duration during still capture.
            settings.photoQualityPrioritization = self.currentMode == .bayer || !self.manual.automaticExposure
                ? .speed : .quality
            let requested = self.requestedDimensions
            let selectedMode = self.currentMode
            let selectedControls = self.manual
            let receiver = PhotoReceiver(mode: selectedMode) { result in
                self.sessionQueue.async {
                    do {
                        let captured = try result.get()
                        let shot = try self.store(captured: captured, requested: requested,
                            device: device, mode: selectedMode, raw: raw, controls: selectedControls)
                        DispatchQueue.main.async { self.lastShot = shot; self.lastShotInPhotos = false }
                        self.publish(ready: false, status: "Salvando no Fotos…")
                        self.importToPhotos(shot) { error in
                            self.pending = nil
                            DispatchQueue.main.async { self.busy = false }
                            self.refreshAvailability()
                            DispatchQueue.main.async {
                                self.status = error == nil ? "Salvo no Fotos · \(shot.summary)" : "Salvo em Arquivos · falha ao adicionar ao Fotos"
                                if let error { self.errorMessage = error.localizedDescription }
                            }
                        }
                    } catch {
                        self.pending = nil
                        DispatchQueue.main.async { self.busy = false }
                        self.fail(error)
                    }
                }
            }
            self.pending = receiver
            // Capture only the selected format; never silently replace it with another.
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90 // portrait-only first version
            }
            self.output.capturePhoto(with: settings, delegate: receiver)
        }
    }

    private func store(captured: RawCapture, requested: CMVideoDimensions,
                       device: AVCaptureDevice, mode: CaptureMode, raw: OSType?,
                       controls: ManualSettings) throws -> SavedShot {
        let data = captured.data
        let actual = captured.dimensions
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Capturas", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = "FreePhoto-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        let url = folder.appendingPathComponent(stem + "." + mode.fileExtension)
        let reportURL = folder.appendingPathComponent(stem + ".json")
        try data.write(to: url, options: .atomic)
        let report = CaptureReport(capturedAt: Date(), mode: mode.rawValue,
            deviceID: device.uniqueID, deviceName: device.localizedName,
            requestedWidth: requested.width, requestedHeight: requested.height,
            deliveredWidth: actual.width, deliveredHeight: actual.height,
            rawPixelFormat: raw, originalBytes: data.count,
            controls: controls, exifISO: captured.exifISO,
            exifExposureSeconds: captured.exifExposureSeconds, exifAperture: captured.exifAperture,
            note: mode.explanation + " O teto solicitado não garante a resolução entregue. A prévia é processada pelo sistema.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // Keep the local image even if its optional report or Photos import fails.
        do { try encoder.encode(report).write(to: reportURL, options: .atomic) }
        catch { DispatchQueue.main.async { self.errorMessage = "Foto salva, mas o relatório falhou: \(error.localizedDescription)" } }
        return SavedShot(url: url, reportURL: reportURL,
            summary: "\(megapixels(actual)) · \(actual.width) × \(actual.height) · \(mode.rawValue)")
    }

    func saveLastToPhotos() {
        guard let shot = lastShot else { return }
        sessionQueue.async {
            self.importToPhotos(shot) { error in
                DispatchQueue.main.async {
                    if let error { self.errorMessage = error.localizedDescription }
                    else { self.status = "Foto adicionada ao Fotos" }
                }
            }
        }
    }

    // Called on sessionQueue; completion also runs there. Retain local backups on failure.
    private func importToPhotos(_ shot: SavedShot, completion: @escaping (Error?) -> Void) {
        if importedPhotos.contains(shot.url) { completion(nil); return }
        guard importingPhotos.insert(shot.url).inserted else {
            completion(CameraFailure(message: "Esta foto já está sendo adicionada ao Fotos.")); return
        }
        let finish: (Error?) -> Void = { error in
            self.sessionQueue.async {
                self.importingPhotos.remove(shot.url)
                if error == nil {
                    self.importedPhotos.insert(shot.url)
                    DispatchQueue.main.async {
                        if self.lastShot?.id == shot.id { self.lastShotInPhotos = true }
                    }
                }
                completion(error)
            }
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { authorization in
            guard authorization == .authorized || authorization == .limited else {
                finish(CameraFailure(message: "Permita adicionar fotos nos Ajustes. Sua imagem está preservada em Arquivos → No Meu iPhone → FreePhoto → Capturas. Use o menu Original para tentar novamente."))
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: shot.url, options: nil)
            } completionHandler: { saved, error in
                finish(saved ? nil : (error ?? CameraFailure(message: "Não foi possível salvar no Fotos. A imagem está preservada em Arquivos; tente novamente pelo menu Original.")))
            }
        }
    }

    private func publish(ready: Bool, status: String) {
        DispatchQueue.main.async { self.ready = ready; self.status = status }
    }

    private func fail(_ error: Error) {
        refreshAvailability()
        DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
    }
}

private final class PhotoReceiver: NSObject, AVCapturePhotoCaptureDelegate {
    private let mode: CaptureMode
    private var payload: RawCapture?
    private var processingError: Error?
    private let completion: (Result<RawCapture, Error>) -> Void

    init(mode: CaptureMode, completion: @escaping (Result<RawCapture, Error>) -> Void) {
        self.mode = mode
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error { processingError = error; return }
        guard photo.isRawPhoto == mode.isRAW else {
            processingError = CameraFailure(message: "A câmera não entregou o formato solicitado.")
            return
        }
        let data: Data
        let dimensions: CMVideoDimensions
        if mode == .png {
            guard let buffer = photo.pixelBuffer else {
                processingError = CameraFailure(message: "A câmera não entregou pixels para gerar PNG."); return
            }
            let image = CIImage(cvPixelBuffer: buffer)
            let context = CIContext(options: [.cacheIntermediates: false])
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
                processingError = CameraFailure(message: "Falha ao renderizar a imagem PNG."); return
            }
            let encoded = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else {
                processingError = CameraFailure(message: "Falha ao iniciar a codificação PNG."); return
            }
            // Preserve EXIF/orientation without a UIImage round-trip or resizing.
            CGImageDestinationAddImage(destination, cgImage, photo.metadata as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                processingError = CameraFailure(message: "Falha ao finalizar o PNG."); return
            }
            data = encoded as Data
            dimensions = CMVideoDimensions(width: Int32(cgImage.width), height: Int32(cgImage.height))
        } else {
            guard let encoded = photo.fileDataRepresentation() else {
                processingError = CameraFailure(message: "A câmera não entregou dados da foto."); return
            }
            data = encoded
            dimensions = mode.isRAW ? photo.resolvedSettings.rawPhotoDimensions : photo.resolvedSettings.photoDimensions
        }
        let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
        let seconds = (exif?[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
        let aperture = (exif?[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
        payload = RawCapture(data: data, dimensions: dimensions,
            exifISO: iso, exifExposureSeconds: seconds, exifAperture: aperture)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let failure = error ?? processingError { completion(.failure(failure)) }
        else if let payload { completion(.success(payload)) }
        else { completion(.failure(CameraFailure(message: "Captura encerrada sem arquivo de imagem."))) }
    }
}
