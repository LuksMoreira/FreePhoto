#!/bin/bash
set -euo pipefail

FREEPHOTO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FREEPHOTO_ROOT"
FREEPHOTO_TARGET="${1:-device}"
FREEPHOTO_ARTIFACTS="$FREEPHOTO_ROOT/build/artifacts"
mkdir -p "$FREEPHOTO_ARTIFACTS"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este script precisa de macOS com Xcode. Windows pode editar o projeto, mas nao compilar o SDK iOS."
  exit 2
fi
case "$FREEPHOTO_TARGET" in
  device) FREEPHOTO_DESTINATION='generic/platform=iOS'; FREEPHOTO_PRODUCT=Debug-iphoneos ;;
  simulator) FREEPHOTO_DESTINATION='generic/platform=iOS Simulator'; FREEPHOTO_PRODUCT=Debug-iphonesimulator ;;
  *) echo 'Uso: bash scripts/build-unsigned.sh [device|simulator]'; exit 2 ;;
esac

{
  xcodebuild -version
  sw_vers
  echo "Target: $FREEPHOTO_TARGET; no signing, no App Store/TestFlight upload."
} | tee "$FREEPHOTO_ARTIFACTS/environment-$FREEPHOTO_TARGET.txt"

plutil -lint FreePhoto/Info.plist FreePhoto.xcodeproj/project.pbxproj
xcodebuild -project FreePhoto.xcodeproj -list \
  > "$FREEPHOTO_ARTIFACTS/project-list-$FREEPHOTO_TARGET.txt"
xcodebuild -project FreePhoto.xcodeproj -scheme FreePhoto \
  -configuration Debug -destination "$FREEPHOTO_DESTINATION" \
  -derivedDataPath "build/derived-$FREEPHOTO_TARGET" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  2>&1 | tee "$FREEPHOTO_ARTIFACTS/build-$FREEPHOTO_TARGET.log"

FREEPHOTO_APP="$FREEPHOTO_ROOT/build/derived-$FREEPHOTO_TARGET/Build/Products/$FREEPHOTO_PRODUCT/FreePhoto.app"
test -d "$FREEPHOTO_APP"
ditto -c -k --sequesterRsrc --keepParent "$FREEPHOTO_APP" \
  "$FREEPHOTO_ARTIFACTS/FreePhoto-$FREEPHOTO_TARGET-unsigned.app.zip"

if [[ "$FREEPHOTO_TARGET" == "simulator" ]]; then
  bash scripts/smoke-simulator.sh "$FREEPHOTO_APP" "$FREEPHOTO_ARTIFACTS"
fi
echo 'Compilacao concluida. App de dispositivo SEM assinatura nao pode ser instalado no iPhone.'
