#!/bin/bash
# Phát hành phiên bản mới lên GitHub Releases + cập nhật appcast.xml (Sparkle).
#
# Cách dùng:  ./scripts/release.sh 0.5.0 "Mô tả ngắn của bản này"
#
# Yêu cầu:
#   - gh CLI đã đăng nhập (gh auth login)
#   - Private key Sparkle tại ~/.config/better-display/sparkle_private_key
#   - sign_update trong PATH hoặc đặt SPARKLE_BIN trỏ tới thư mục bin của Sparkle
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Thiếu version, ví dụ: ./scripts/release.sh 0.5.0 \"ghi chú\"}"
NOTES="${2:-Bản cập nhật $VERSION}"
REPO="luongdong059/better-display"
KEY_FILE="$HOME/.config/better-display/sparkle_private_key"
SIGN_UPDATE="${SPARKLE_BIN:-}/sign_update"
command -v "$SIGN_UPDATE" >/dev/null 2>&1 || SIGN_UPDATE="sign_update"
command -v "$SIGN_UPDATE" >/dev/null 2>&1 || { echo "Không tìm thấy sign_update — đặt SPARKLE_BIN=<thư mục bin Sparkle>"; exit 1; }
[ -f "$KEY_FILE" ] || { echo "Không thấy private key: $KEY_FILE"; exit 1; }

# 1. Cập nhật version trong Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Packaging/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Packaging/Info.plist

# 2. Build + đóng gói + nén
./scripts/build-app.sh
ZIP="Better-Display-$VERSION.zip"
(cd dist && ditto -c -k --keepParent "Better Display.app" "$ZIP")

# 3. Ký EdDSA cho Sparkle
SIGNATURE_LINE=$("$SIGN_UPDATE" -f "$KEY_FILE" "dist/$ZIP")
echo "Chữ ký: $SIGNATURE_LINE"

# 4. Chèn item mới vào appcast.xml (mục mới nhất đứng đầu)
DOWNLOAD_URL="https://github.com/$REPO/releases/download/v$VERSION/$ZIP"
PUB_DATE=$(LC_ALL=en_US.UTF-8 date "+%a, %d %b %Y %H:%M:%S %z")
ITEM=$(cat <<EOF
        <item>
            <title>Phiên bản $VERSION</title>
            <description><![CDATA[${NOTES}]]></description>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure url="$DOWNLOAD_URL" $SIGNATURE_LINE type="application/octet-stream"/>
        </item>
EOF
)
python3 - "$ITEM" << 'PYEOF'
import sys
item = sys.argv[1]
with open("appcast.xml") as f:
    content = f.read()
marker = "<!-- ITEMS -->"
if marker not in content:
    sys.exit("appcast.xml thiếu marker <!-- ITEMS -->")
content = content.replace(marker, marker + "\n" + item, 1)
with open("appcast.xml", "w") as f:
    f.write(content)
PYEOF

# 5. Commit + tag + push + GitHub Release
git add Packaging/Info.plist appcast.xml
git commit -m "Release v$VERSION"
git tag "v$VERSION"
git push && git push origin "v$VERSION"
gh release create "v$VERSION" "dist/$ZIP" --repo "$REPO" --title "v$VERSION" --notes "$NOTES"

echo ""
echo "==> Đã phát hành v$VERSION. App đã cài sẽ thấy update trong vòng 1 ngày (hoặc bấm Kiểm tra bản cập nhật)."
