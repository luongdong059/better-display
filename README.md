# better-display

Tiện ích macOS nhận dạng các màn hình đang kết nối và bật/tắt từng màn hình.
Xem [ARCHITECTURE.md](ARCHITECTURE.md) (kiến trúc) và [TODO.md](TODO.md) (tiến độ).

**Trạng thái:** Phase 0–1 hoàn thành và đã verify. Phase 2 (bật/tắt) code xong,
đã verify phần an toàn; phần disconnect thật cần màn hình thứ 2 để test.

## Build

```bash
swift build            # build debug
swift test             # chạy unit tests
swift build -c release # build release → .build/release/displayctl
```

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

- Chiến lược `disconnect` dùng private API `SLSConfigureDisplayEnabled` (SkyLight),
  nạp runtime bằng `dlopen`/`dlsym` — đã xác nhận tồn tại trên macOS 26.5.
  Nếu bản macOS mới bỏ API, tự chuyển sang `mirror`/`gamma`.
- Trạng thái lưu tại `~/Library/Application Support/displayctl/state.json`,
  khóa theo `persistentKey` (vendor-model-serial), không theo display ID.
- `gamma` chỉ có tác dụng khi tiến trình còn sống — chủ yếu dành cho GUI (Phase 4).
