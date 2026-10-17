#!/bin/zsh
# Builds HamsterPal.app next to this script. Usage: ./build.sh [--run]
set -e
cd "$(dirname "$0")"
APP=HamsterPal.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Assets/ham.png "$APP/Contents/Resources/ham.png"
swiftc -O -suppress-warnings -swift-version 5 -parse-as-library \
  -framework AppKit -framework SwiftUI \
  Sources/*.swift -o "$APP/Contents/MacOS/HamsterPal"
# app icon + preview sheet, drawn by the app itself
HAM_RENDER="$PWD/build" "$APP/Contents/MacOS/HamsterPal"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $PWD/$APP"
# install the copy the Dock points at
INSTALLED="$HOME/Applications/HamsterPal.app"
if [[ "$1" == "--run" ]]; then pkill -x HamsterPal 2>/dev/null || true; sleep 1; fi
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
echo "installed $INSTALLED"
if [[ "$1" == "--run" ]]; then open "$INSTALLED"; fi
