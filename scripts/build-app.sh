#!/bin/bash
# Đóng gói Better Display.app từ SwiftPM build (release) + ad-hoc codesign.
# Kết quả: dist/Better Display.app — kéo vào /Applications để cài.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release --product BetterDisplay

APP="dist/Better Display.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/BetterDisplay "$APP/Contents/MacOS/BetterDisplay"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> codesign (ad-hoc)"
codesign --force --deep -s - "$APP"

echo "==> OK: $APP"
echo "Cài đặt:  cp -R \"$APP\" /Applications/"
