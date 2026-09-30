#!/usr/bin/env bash
# Build an unsigned Metrogas .ipa for CI artifact download.
# Not installable on devices until resigned with a valid Apple cert/profile.
set -euo pipefail

PROJECT="Metrogas.xcodeproj"
SCHEME="Metrogas"
CONFIGURATION="Release"
OUT="build/Metrogas.ipa"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="${ROOT}/build"
APP_DIR="${BUILD_DIR}/Release-iphoneos"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
mkdir -p "$BUILD_DIR"

echo "==> Building ${SCHEME} (${CONFIGURATION}) without code signing"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=NO \
  clean build

APP_PATH="$(find "$BUILD_DIR/DerivedData/Build/Products" -name "${SCHEME}.app" -print | head -n 1)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "ERROR: ${SCHEME}.app not found under DerivedData products" >&2
  find "$BUILD_DIR/DerivedData/Build/Products" -maxdepth 3 -type d -print || true
  exit 1
fi

echo "==> Packaging IPA from: $APP_PATH"
rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

rm -f "$OUT"
(
  cd "$BUILD_DIR"
  zip -qry "$(basename "$OUT")" Payload
)
# zip wrote into BUILD_DIR; move if OUT path differs
if [[ "$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")" != "$(cd "$BUILD_DIR" && pwd)/$(basename "$OUT")" ]]; then
  mv "$BUILD_DIR/$(basename "$OUT")" "$OUT"
fi

echo "==> IPA ready: $OUT ($(du -h "$OUT" | awk '{print $1}'))"
unzip -l "$OUT" | head -40
if ! unzip -l "$OUT" | grep -q 'PlugIns/MetrogasWidgets.appex/MetrogasWidgets'; then
  echo "ERROR: MetrogasWidgets.appex missing from IPA" >&2
  exit 1
fi
echo "==> Widget extension embedded OK"
