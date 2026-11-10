#!/bin/bash
set -euo pipefail
FREEPHOTO_APP="${1:?Informe o caminho absoluto do app de simulador}"
FREEPHOTO_ARTIFACTS="${2:?Informe o diretorio de artefatos}"

FREEPHOTO_RUNTIME="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; assert r,"Nenhum runtime iOS instalado"; print(sorted(r,key=lambda x:tuple(map(int,x["version"].split("."))))[-1]["identifier"])')"
FREEPHOTO_DEVICE_TYPE="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin)["devicetypes"] if "iPhone" in x["name"]]; assert d,"Nenhum tipo iPhone instalado"; print(d[-1]["identifier"])')"
FREEPHOTO_SIMULATOR="$(xcrun simctl create "FreePhoto-CI-$$" "$FREEPHOTO_DEVICE_TYPE" "$FREEPHOTO_RUNTIME")"
trap 'xcrun simctl shutdown "$FREEPHOTO_SIMULATOR" >/dev/null 2>&1 || true; xcrun simctl delete "$FREEPHOTO_SIMULATOR" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$FREEPHOTO_SIMULATOR"
xcrun simctl bootstatus "$FREEPHOTO_SIMULATOR" -b
xcrun simctl install "$FREEPHOTO_SIMULATOR" "$FREEPHOTO_APP"
xcrun simctl privacy "$FREEPHOTO_SIMULATOR" grant camera com.example.FreePhoto \
  > "$FREEPHOTO_ARTIFACTS/simulator-camera-permission.txt" 2>&1 || true
xcrun simctl launch "$FREEPHOTO_SIMULATOR" com.example.FreePhoto \
  | tee "$FREEPHOTO_ARTIFACTS/simulator-launch.txt"
sleep 3
# Verify the app process still exists after launch, rather than only trusting launch success.
xcrun simctl spawn "$FREEPHOTO_SIMULATOR" launchctl list \
  | awk '$1 ~ /^[0-9]+$/ && /com[.]example[.]FreePhoto/ {found=1; print} END {exit !found}' \
  | tee "$FREEPHOTO_ARTIFACTS/simulator-process.txt"
xcrun simctl io "$FREEPHOTO_SIMULATOR" screenshot "$FREEPHOTO_ARTIFACTS/FreePhoto-simulator.png"
echo 'Smoke test: instalacao e abertura no simulador. Nao testa lentes, RAW ou camera fisica.' \
  | tee "$FREEPHOTO_ARTIFACTS/simulator-scope.txt"
