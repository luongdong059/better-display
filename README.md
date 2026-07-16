# Better Display

Tiện ích menu bar cho macOS: nhận dạng màn hình, bật/tắt từng màn hình
(disconnect hoặc tắt nguồn thật qua DDC), chỉnh độ sáng, kích thước,
xoay màn hình và mirror — tất cả trong một dialog nhỏ trên thanh menu.

> **EN**: macOS menu bar utility to detect displays and control them per-display:
> power on/off (disconnect or true DDC standby), brightness, resolution,
> rotation, mirroring. Universal binary (Apple Silicon + Intel), macOS 13+,
> auto-updates via Sparkle. Grab the latest `.zip` from
> [Releases](https://github.com/luongdong059/better-display/releases).

## Cài đặt (người dùng)

1. Tải file `Better-Display-x.y.z.zip` mới nhất từ [Releases](https://github.com/luongdong059/better-display/releases)
2. Giải nén, kéo `Better Display.app` vào thư mục **Applications**
3. Lần đầu mở sẽ bị macOS chặn (app chưa notarize): vào **System Settings →
   Privacy & Security** → kéo xuống bấm **"Open Anyway"** — hoặc chạy:
   ```bash
   xattr -cr "/Applications/Better Display.app"
   ```
4. Icon hình màn hình xuất hiện trên menu bar. Từ đây về sau app **tự cập nhật**
   khi có bản mới (không cần làm lại bước 3).

## Yêu cầu hệ thống

- **macOS 13 (Ventura) trở lên**
- **Apple Silicon hoặc Intel** (universal binary từ v0.5.0)
  - Riêng nhóm tính năng DDC (chỉnh độ sáng, tắt nguồn thật màn hình ngoài)
    chỉ có trên **Apple Silicon** — trên Intel các mục này tự ẩn/báo không hỗ trợ,
    những tính năng còn lại (bật/tắt disconnect, mirror, đổi kích thước, xoay)
    hoạt động bình thường. *Chưa test thực tế trên máy Intel.*

**Trạng thái:** Phase 0–1 hoàn thành và đã verify. Phase 2 (bật/tắt) code xong,
đã verify phần an toàn; phần disconnect thật cần màn hình thứ 2 để test.

## Build

```bash
swift build            # build debug
swift test             # chạy unit tests
swift build -c release # build release → .build/release/displayctl
```

## Menu bar app

```bash
./scripts/build-app.sh                          # đóng gói dist/Better Display.app
cp -R "dist/Better Display.app" /Applications/  # cài đặt
open "/Applications/Better Display.app"         # chạy
```

- Icon hình màn hình hiện trên menu bar; bấm vào mở dialog danh sách màn hình
  với switch bật/tắt từng cái. Switch của màn hình cuối cùng tự khóa (an toàn).
- Toggle "Khởi động cùng máy" trong dialog — **nên bật sau khi đã chép app vào
  `/Applications`** (login item đăng ký theo đường dẫn của app đang chạy).
- Nút "Bật tất cả màn hình" = lệnh `displayctl restore` bản GUI.
- Màn hình đã disconnect vẫn hiện trong danh sách (kèm nhãn "Đã tắt") để bật lại.

## Sử dụng

```bash
.build/debug/displayctl list           # liệt kê màn hình (bảng)
.build/debug/displayctl list --json    # xuất JSON
.build/debug/displayctl watch          # theo dõi sự kiện cắm/rút realtime
.build/debug/displayctl off <id|tên>   # tắt màn hình (disconnect → mirror → gamma)
.build/debug/displayctl off <id> --strategy mirror   # ép chiến lược cụ thể
.build/debug/displayctl on <id|tên>    # bật lại
.build/debug/displayctl restore        # CỨU HỘ: bật lại tất cả + reset gamma
```

## Checklist test (với màn hình thứ 2)

Trước khi test: **bật SSH** (System Settings → General → Sharing → Remote Login)
để có đường cứu hộ `displayctl restore` từ máy khác.

1. `displayctl list` — thấy đủ 2 màn hình, đúng tên/độ phân giải
2. `displayctl watch` — rút/cắm cáp màn hình phụ, sự kiện hiện ra trong ~1s
3. `displayctl off <id màn phụ>` — màn phụ tối, cửa sổ dồn về màn chính
4. `displayctl list` — màn phụ hiển thị OFF
5. `displayctl on <id màn phụ>` — màn phụ sáng lại, sắp xếp giữ nguyên
6. `displayctl off <id màn CHÍNH>` — vẫn hoạt động (màn phụ thành chính)
7. Tắt màn phụ → chạy `displayctl restore` → tất cả sáng lại
8. Cố tắt nốt màn hình cuối → phải bị chặn với thông báo an toàn

Đã verify sẵn trên máy 1 màn hình: `off` màn hình duy nhất bị SafetyGuard chặn,
`restore` chạy an toàn khi không có gì để khôi phục.

## Ghi chú kỹ thuật

- **Cập nhật tự động (Sparkle)**: app tự kiểm tra bản mới mỗi ngày qua
  `appcast.xml` (host trên nhánh main của repo này), gói update tải từ GitHub
  Releases và được xác minh chữ ký EdDSA. Kiểm tra thủ công: nút "Kiểm tra bản
  cập nhật…" trong dialog.
- **Phát hành bản mới**: `./scripts/release.sh <version> "<ghi chú>"` — tự bump
  version, build universal, ký zip, cập nhật appcast.xml, tag + GitHub Release.
  Cần `gh` CLI đã đăng nhập và private key tại
  `~/.config/better-display/sparkle_private_key` (giữ cẩn thận, KHÔNG đưa vào repo).
- Chiến lược `disconnect` dùng private API `SLSConfigureDisplayEnabled` (SkyLight),
  nạp runtime bằng `dlopen`/`dlsym` — đã xác nhận tồn tại trên macOS 26.5.
  Nếu bản macOS mới bỏ API, tự chuyển sang `mirror`/`gamma`.
- Trạng thái lưu tại `~/Library/Application Support/displayctl/state.json`,
  khóa theo `persistentKey` (vendor-model-serial), không theo display ID.
- `gamma` chỉ có tác dụng khi tiến trình còn sống — chủ yếu dành cho GUI (Phase 4).
