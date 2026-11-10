import AVFoundation
import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var camera = CameraEngine()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLenses = false
    @State private var showShare = false
    @State private var showHelp = false
    @State private var showControls = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FreePhoto").font(.headline).tracking(3)
                        Text("O original, nas suas mãos.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showControls = true } label: { Image(systemName: "slider.horizontal.3").font(.title2) }
                        .accessibilityLabel("Controles manuais da câmera")
                        .disabled(camera.selectedID.isEmpty || camera.busy || camera.controlsBusy)
                    Button { showHelp = true } label: { Image(systemName: "info.circle").font(.title2) }
                        .accessibilityLabel("Sobre os formatos de captura")
                }
                .padding()

                ZStack {
                    CameraPreview(session: camera.session)
                    GridOverlay().allowsHitTesting(false)
                    if camera.permissionDenied {
                        VStack(spacing: 16) {
                            Image(systemName: "camera.fill").font(.largeTitle)
                            Text("Permita o acesso à câmera nos Ajustes.").multilineTextAlignment(.center)
                            Button("Abrir Ajustes") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }.buttonStyle(.borderedProminent)
                        }.padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                    VStack {
                        HStack {
                            Text(camera.mode.isRAW ? "\(camera.mode.rawValue.uppercased()) · DNG" : "\(camera.mode.rawValue) · PROCESSADO")
                                .font(.caption.bold()).tracking(1)
                                .padding(8).background(.black.opacity(0.65), in: Capsule())
                            Spacer()
                        }
                        Spacer()
                        HStack {
                            Image(systemName: "camera.aperture")
                            Text(camera.lenses.first(where: { $0.id == camera.selectedID })?.name ?? "Câmera")
                            Spacer()
                            Text("SEM ZOOM DIGITAL").font(.system(size: 9, weight: .semibold)).tracking(1)
                        }.font(.caption).padding(10).background(.black.opacity(0.65), in: Capsule())
                    }.padding(12)
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 12)

                VStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(camera.lenses) { lens in
                                Button { camera.select(lens) } label: {
                                    Text(lens.name).font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(camera.selectedID == lens.id ? Color.yellow : Color.white.opacity(0.12), in: Capsule())
                                        .foregroundStyle(camera.selectedID == lens.id ? .black : .white)
                                }.disabled(camera.busy || camera.controlsBusy)
                            }
                        }
                    }
                    Picker("Formato", selection: Binding(get: { camera.mode }, set: { camera.selectMode($0) })) {
                        ForEach(CaptureMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }.pickerStyle(.segmented).disabled(camera.busy || camera.controlsBusy || camera.selectedID.isEmpty)
                    Text("\(camera.mode.isRAW ? "DNG original" : camera.mode.rawValue) → Fotos automaticamente")
                        .font(.caption2).foregroundStyle(.secondary)

                    VStack(spacing: 4) {
                        Text(camera.capability).font(.caption.monospacedDigit())
                        Text(camera.status).font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(3)
                    }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)

                    HStack {
                        Button { showLenses = true } label: {
                            VStack(spacing: 5) {
                                Image(systemName: "camera.filters").font(.title2)
                                Text("Lentes").font(.caption2)
                            }.frame(width: 64)
                        }.accessibilityLabel("Ver câmeras e especificações")
                        Spacer()
                        Button { camera.capture() } label: {
                            ZStack {
                                Circle().stroke(.white, lineWidth: 3).frame(width: 74, height: 74)
                                Circle().fill(camera.ready ? .white : .gray).frame(width: 62, height: 62)
                                if camera.busy { ProgressView().tint(.black) }
                            }
                        }.disabled(!camera.ready || camera.busy || camera.controlsBusy).accessibilityLabel("Capturar foto em \(camera.mode.rawValue)")
                        Spacer()
                        Menu {
                            Button("Compartilhar arquivo original", systemImage: "square.and.arrow.up") { showShare = true }
                            Button(camera.lastShotInPhotos ? "Já salvo no Fotos" : "Tentar salvar no Fotos", systemImage: "photo.badge.plus") { camera.saveLastToPhotos() }
                                .disabled(camera.lastShotInPhotos || camera.busy)
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.up").font(.title2)
                                Text("Original").font(.caption2)
                            }.frame(width: 64)
                        }.disabled(camera.lastShot == nil)
                    }
                }.padding(16)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task { camera.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() } else { camera.stop() }
        }
        .sheet(isPresented: $showLenses) { lensSheet }
        .sheet(isPresented: $showHelp) { helpSheet }
        .sheet(isPresented: $showControls) { ManualControlsView(camera: camera) }
        .sheet(isPresented: $showShare) {
            if let shot = camera.lastShot { ShareSheet(url: shot.url) }
        }
        .alert("FreePhoto", isPresented: Binding(
            get: { camera.errorMessage != nil },
            set: { if !$0 { camera.errorMessage = nil } })) {
                Button("OK") { camera.errorMessage = nil }
            } message: { Text(camera.errorMessage ?? "") }
    }

    private var lensSheet: some View {
        NavigationStack {
            List {
                Section("Câmeras de fotografia detectadas") {
                    ForEach(camera.lenses) { lens in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lens.name).font(.headline)
                            Text(lens.details).font(.caption).foregroundStyle(.secondary)
                            Text("ID: \(lens.id)").font(.caption2).textSelection(.enabled)
                            Text("Máximo anunciado: \(lens.maximum.width) × \(lens.maximum.height)")
                                .font(.caption.monospacedDigit())
                        }.padding(.vertical, 5)
                    }
                }
                Section {
                    Text("A lista vem do iOS. As capacidades RAW são verificadas ao selecionar cada câmera. O máximo anunciado não garante essa resolução em todos os formatos.")
                    Text("No iPhone 16 Pro Max, 2× é um recorte da principal; macro usa a ultra-angular. São modos de uso, não lentes extras. O LiDAR mede profundidade e não é uma câmera de fotografia colorida.")
                }.font(.footnote)
            }
            .navigationTitle("Suas lentes")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { showLenses = false } } }
        }
    }

    private var helpSheet: some View {
        NavigationStack {
            List {
                Section("RAW Bayer · menos processamento") {
                    Text(CaptureMode.bayer.explanation)
                    Text("O app não aplica nitidez, redução de ruído, filtros ou conversão. O iOS e o sensor ainda podem realizar operações que o app não controla. Não significa acesso elétrico direto ao sensor nem garantia de processamento zero.")
                }
                Section("ProRAW Max · prioridade à resolução") {
                    Text(CaptureMode.proRAW.explanation)
                    Text("ProRAW não é um formato sem processamento. Pode chegar a 48 MP nas lentes e condições compatíveis. A resolução entregue aparece após cada captura.")
                }
                Section("JPEG e PNG") {
                    Text(CaptureMode.jpeg.explanation)
                    Text(CaptureMode.png.explanation)
                    Text("O PNG usa pixels processados sem um JPEG intermediário e é salvo em sRGB de 8 bits. JPEG e PNG não substituem o DNG para preservar dados RAW.")
                }
                Section("Originais e privacidade") {
                    Text("Cada captura é adicionada automaticamente ao app Fotos, após sua permissão. Uma cópia local e o relatório JSON ficam em Arquivos → No Meu iPhone → FreePhoto → Capturas. Se a importação falhar, use o menu Original para tentar novamente. O app não solicita localização nem envia dados a um servidor próprio. Se o Fotos do iCloud estiver ativo, a biblioteca pode sincronizar normalmente pelo iOS.")
                    Text("A prévia da câmera e as miniaturas de outros apps são renderizadas pelo sistema e podem parecer diferentes do DNG revelado. Esta versão opera em retrato. Use o botão de controles para ajustar ISO, tempo, foco, balanço de branco e resolução. Ao trocar lente ou formato, os ajustes voltam ao automático.")
                }
            }
            .navigationTitle("Fotografia RAW")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { showHelp = false } } }
        }
    }
}

private struct ManualControlsView: View {
    @ObservedObject var camera: CameraEngine
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ManualSettings()
    @State private var resolutionID = ""

    private var state: ManualControlState { camera.controlState }
    private var exposureRange: ClosedRange<Double> {
        let lower = log2(max(state.minExposure, 0.000000001))
        return lower...max(lower + 0.0001, log2(max(state.maxExposure, state.minExposure)))
    }

    private func shutter(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.2f s", seconds) }
        return String(format: "1/%.0f s", 1 / max(seconds, 0.000000001))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(camera.lenses.first(where: { $0.id == camera.selectedID })?.name ?? "Câmera") · \(camera.mode.rawValue)")
                        .font(.headline)
                    Text("Edite e toque em Aplicar. Ao trocar lente ou formato, os controles voltam ao automático e os limites são recalculados.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Exposição") {
                    Toggle("Exposição automática", isOn: $draft.automaticExposure)
                        .disabled(!state.supportsExposure)
                    if state.supportsExposure {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("ISO", value: String(format: "%.0f", draft.iso))
                            Slider(value: $draft.iso,
                                in: state.minISO...max(state.minISO + 0.001, state.maxISO))
                                .accessibilityLabel("ISO")
                            Text("Limites da lente: \(Int(state.minISO))–\(Int(state.maxISO))")
                                .font(.caption).foregroundStyle(.secondary)
                            LabeledContent("Obturador", value: shutter(draft.exposureSeconds))
                            Slider(value: Binding(
                                get: { min(max(log2(max(draft.exposureSeconds, 0.000000001)), exposureRange.lowerBound), exposureRange.upperBound) },
                                set: { draft.exposureSeconds = pow(2, $0) }), in: exposureRange)
                                .accessibilityLabel("Tempo de exposição")
                            Text("Limites: \(shutter(state.minExposure))–\(shutter(state.maxExposure))")
                                .font(.caption).foregroundStyle(.secondary)
                        }.disabled(draft.automaticExposure)
                    } else {
                        Text("A lente/formato atual não disponibiliza exposição manual.").font(.footnote)
                    }
                    Text("ISO e tempo são fixados juntos no modo manual. Com exposição automática, os números são uma leitura pontual; podem mudar após a leitura.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("A exposição manual prioriza o respeito aos valores escolhidos. Isso pode reduzir a resolução entregue em ProRAW.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Foco") {
                    Toggle("Foco automático", isOn: $draft.automaticFocus)
                        .disabled(!state.supportsFocus)
                    if state.supportsFocus {
                        LabeledContent("Posição da lente", value: String(format: "%.2f", draft.focus))
                        Slider(value: $draft.focus, in: 0...1)
                            .disabled(draft.automaticFocus).accessibilityLabel("Foco manual")
                        Text("Posição normalizada de 0 a 1; não é distância em metros.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else { Text("Foco manual indisponível nesta câmera.").font(.footnote) }
                }
                Section("Balanço de branco") {
                    Toggle("Balanço de branco automático", isOn: $draft.automaticWhiteBalance)
                        .disabled(!state.supportsWhiteBalance)
                    if state.supportsWhiteBalance {
                        VStack(spacing: 8) {
                            LabeledContent("Temperatura", value: String(format: "%.0f K", draft.temperature))
                            Slider(value: $draft.temperature, in: 2000...15000, step: 50)
                                .accessibilityLabel("Temperatura de cor")
                            LabeledContent("Matiz", value: String(format: "%+.0f", draft.tint))
                            Slider(value: $draft.tint, in: -150...150, step: 1)
                                .accessibilityLabel("Matiz do balanço de branco")
                        }.disabled(draft.automaticWhiteBalance)
                        Text("A faixa em Kelvin é uma faixa de ajuste do app. Os ganhos RGB são limitados ao que a câmera aceita; a leitura após Aplicar pode diferir do valor solicitado. Reveladores RAW podem interpretar o balanço de branco de outra forma.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else { Text("Balanço de branco manual indisponível nesta câmera.").font(.footnote) }
                }
                Section("Resolução") {
                    Picker("Teto de captura", selection: $resolutionID) {
                        ForEach(state.resolutions) { resolution in
                            Text(resolution.label).tag(resolution.id)
                        }
                    }
                    Text("Opções anunciadas pelo formato ativo. O iOS pode entregar uma imagem menor; o resultado real aparece após o disparo e no relatório JSON.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Abertura fixa", value: String(format: "ƒ/%.1f", state.aperture))
                }
                Section {
                    Button("Restaurar exposição, foco e balanço automáticos") {
                        draft.automaticExposure = true
                        draft.automaticFocus = true
                        draft.automaticWhiteBalance = true
                    }
                    Button("Atualizar leituras da câmera") { camera.refreshControls() }
                    if camera.controlsBusy { ProgressView("Aguardando os ajustes da câmera…") }
                }
            }
            .disabled(camera.controlsBusy || camera.busy)
            .navigationTitle("Controles manuais")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }.disabled(camera.controlsBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") { camera.applyControls(draft, resolutionID: resolutionID) }
                        .disabled(camera.controlsBusy || camera.busy || resolutionID.isEmpty)
                }
            }
            .onAppear { camera.refreshControls() }
            .onReceive(camera.$controlState) { state in
                draft = state.settings
                resolutionID = state.resolutionID
            }
            .alert("Controles da câmera", isPresented: Binding(
                get: { camera.errorMessage != nil },
                set: { if !$0 { camera.errorMessage = nil } })) {
                    Button("OK") { camera.errorMessage = nil }
                } message: { Text(camera.errorMessage ?? "") }
            .interactiveDismissDisabled(camera.controlsBusy)
        }
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.setNeedsLayout() }
}

private struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for index in 1...2 {
                    let x = geometry.size.width * CGFloat(index) / 3
                    let y = geometry.size.height * CGFloat(index) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }.stroke(.white.opacity(0.2), lineWidth: 0.5)
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
