#!/bin/bash
# Phát hành phiên bản mới lên GitHub Releases + cập nhật appcast.xml (Sparkle).
#
# Cách dùng:  ./scripts/release.sh 0.6.0 "Mô tả ngắn của bản này"
#
# Yêu cầu:
#   - gh CLI đã đăng nhập (gh auth login)
#   - Private key Sparkle: ~/.config/better-display/sparkle_private_key
#   - Sparkle tools:       ~/.config/better-display/tools/ (hoặc đặt SPARKLE_BIN)
#     Tải tại https://github.com/sparkle-project/Sparkle/releases → giải nén bin/
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Thiếu version, ví dụ: ./scripts/release.sh 0.6.0 \"ghi chú\"}"
NOTES="${2:-Bản cập nhật $VERSION}"
REPO="luongdong059/better-display"
KEY_FILE="$HOME/.config/better-display/sparkle_private_key"
TOOLS_DIR="${SPARKLE_BIN:-$HOME/.config/better-display/tools}"
SIGN_UPDATE="$TOOLS_DIR/sign_update"

# --- Kiểm tra TOÀN BỘ điều kiện trước khi thay đổi bất cứ thứ gì ---
command -v gh >/dev/null 2>&1 || { echo "LỖI: thiếu gh CLI (brew install gh)"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "LỖI: gh chưa đăng nhập — chạy: gh auth login"; exit 1; }
[ -x "$SIGN_UPDATE" ] || { echo "LỖI: không thấy $SIGN_UPDATE — xem hướng dẫn ở đầu script"; exit 1; }
[ -f "$KEY_FILE" ] || { echo "LỖI: không thấy private key $KEY_FILE"; exit 1; }
git diff-index --quiet HEAD -- || { echo "LỖI: cây làm việc chưa sạch — commit/stash trước khi release"; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "LỖI: tag v$VERSION đã tồn tại"; exit 1; }
grep -q "<sparkle:version>$VERSION</sparkle:version>" appcast.xml && { echo "LỖI: appcast.xml đã có bản $VERSION"; exit 1; }

# 1. Bump version: Info.plist + Version.swift (một nguồn cho CLI)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Packaging/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Packaging/Info.plist
sed -i '' "s/public static let current = \"[^\"]*\"/public static let current = \"$VERSION\"/" Sources/DisplayCore/Version.swift

# 2. Build + đóng gói + nén + ký
./scripts/build-app.sh
ZIP="Better-Display-$VERSION.zip"
(cd dist && ditto -c -k --keepParent "Better Display.app" "$ZIP")
SIGNATURE_LINE=$("$SIGN_UPDATE" -f "$KEY_FILE" "dist/$ZIP")
echo "Chữ ký: $SIGNATURE_LINE"

# 3. Chèn item mới vào appcast.xml (mục mới nhất đứng đầu)
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

# 4. Commit + tag + push + GitHub Release
#    Nếu lỗi ở bất kỳ bước nào từ đây, in đúng lệnh cần chạy lại để khắc phục.
recovery() {
    echo ""
    echo "!!! Release dở dang. Sau khi khắc phục nguyên nhân, chạy tiếp các lệnh còn thiếu:"
    echo "    git push && git push origin v$VERSION"
    echo "    gh release create v$VERSION \"dist/$ZIP\" --repo $REPO --title v$VERSION --notes \"$NOTES\""
}
trap recovery ERR

git add Packaging/Info.plist Sources/DisplayCore/Version.swift appcast.xml
git commit -m "Release v$VERSION"
git tag "v$VERSION"
git push
git push origin "v$VERSION"
gh release create "v$VERSION" "dist/$ZIP" --repo "$REPO" --title "v$VERSION" --notes "$NOTES"
trap - ERR

echo ""
echo "==> Đã phát hành v$VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
echo "    App đã cài sẽ thấy update trong vòng 1 ngày (hoặc bấm 'Kiểm tra bản cập nhật…')."
