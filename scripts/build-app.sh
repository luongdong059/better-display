#!/bin/bash
# Đóng gói Better Display.app (universal: arm64 + x86_64) + Sparkle.framework
# + ad-hoc codesign. Kết quả: dist/Better Display.app
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build -c release (universal arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product BetterDisplay

BIN=".build/apple/Products/Release/BetterDisplay"
[ -f "$BIN" ] || BIN=".build/release/BetterDisplay"

SPARKLE_FW=$(find .build/artifacts -type d -name "Sparkle.framework" -path "*macos*" | head -1)
[ -n "$SPARKLE_FW" ] || { echo "Không tìm thấy Sparkle.framework trong .build/artifacts"; exit 1; }

APP="dist/Better Display.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN" "$APP/Contents/MacOS/BetterDisplay"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundle resource của SPM (icon menu bar) — Bundle.module tìm nó trong Contents/Resources.
RES_BUNDLE="$(dirname "$BIN")/better-display_BetterDisplay.bundle"
[ -d "$RES_BUNDLE" ] || { echo "Không tìm thấy $RES_BUNDLE"; exit 1; }
cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

# Binary tìm Sparkle qua @rpath — trỏ vào Contents/Frameworks của bundle.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/BetterDisplay" 2>/dev/null || true

echo "==> codesign (ad-hoc, gồm cả Sparkle XPC services)"
codesign --force --deep -s - "$APP"

echo "==> kiến trúc: $(lipo -archs "$APP/Contents/MacOS/BetterDisplay")"
echo "==> OK: $APP"
echo "Cài đặt:  cp -R \"$APP\" /Applications/"
