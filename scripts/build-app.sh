#!/usr/bin/env bash
# Builds OnAir with SwiftPM and wraps it in a signed macOS .app bundle.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
# Signing: uses $ONAIR_SIGN_IDENTITY if set, otherwise ad-hoc ("-").
# With ad-hoc signing macOS may ask for camera/mic/screen permissions again after each rebuild.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/OnAir.app"
IDENTITY="${ONAIR_SIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG" --product OnAir
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/OnAir" "$APP/Contents/MacOS/OnAir"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles of dependencies, if any.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

codesign --force --options runtime --timestamp=none \
  --entitlements "$ROOT/Resources/OnAir.entitlements" \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
