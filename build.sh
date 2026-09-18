#!/bin/zsh
# Builds FancyScroll with SwiftPM and assembles a signed .app bundle in ./build
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="FancyScroll"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG" 2>&1 | grep -v "^\[" || true
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
[[ -x "$BIN" ]] || { echo "build failed: $BIN not found"; exit 1; }

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc sign so macOS gives the app a stable identity for the Accessibility permission.
echo "▸ codesign (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature" || true

echo "✓ built $APP"
echo "  run:      open $APP"
echo "  install:  cp -R $APP /Applications/"
