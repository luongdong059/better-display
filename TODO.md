# TODO — Better Display

Checklist thực hiện theo phase. Mỗi phase có **mục tiêu**, **đầu việc**, và **tiêu chí hoàn thành (DoD)** — chỉ chuyển phase khi DoD đạt.

Tiến độ dự kiến: ~1,5–2 tuần đến hết Phase 4.

> **Cập nhật 2026-07-15:** Phase 0–1 hoàn thành, đã verify trên máy thật (Mac mini M4, macOS 26.5).
> Phase 2 code xong + verify phần an toàn; các mục test tay cần **màn hình thứ 2** và **bật SSH** trước.

---

## Phase 0 — Khởi tạo dự án (0,5 ngày) ✅

Mục tiêu: khung dự án build được.

- [x] Cài Xcode + Command Line Tools — có sẵn (Xcode 26.1.1, Swift 6.2.1)
- [x] `git init`, tạo `.gitignore` (Swift/Xcode: `.build/`, `*.xcuserdata`, `DerivedData/`)
- [x] Tạo `Package.swift` với 3 target:
  - [x] `DisplayCore` (library)
  - [x] `displayctl` (executable, phụ thuộc DisplayCore + `swift-argument-parser`)
  - [x] `DisplayCoreTests` (test target)
  - (Target `App` menu bar sẽ thêm ở Phase 4 bằng Xcode project hoặc giữ SwiftPM thuần)
- [x] Commit đầu tiên

**DoD:** ✅ `swift build` và `swift test` chạy xanh.

---

## Phase 1 — Nhận dạng màn hình (1–2 ngày) ✅ (còn 1 mục test tay)

Mục tiêu: `displayctl list` in đầy đủ thông tin mọi màn hình; `watch` thấy sự kiện cắm/rút.

### DisplayCore
- [x] `DisplayInfo.swift` — struct như mô tả trong ARCHITECTURE.md §3.1
- [x] `DisplayManager.allDisplays()`:
  - [x] Gọi `CGGetOnlineDisplayList` + `CGGetActiveDisplayList`, suy ra `isEnabled` từ hiệu của 2 danh sách
  - [x] Lấy tên qua `NSScreen.localizedName` (map bằng `CGDirectDisplayID` trong `deviceDescription`)
  - [x] Độ phân giải + refresh rate từ `CGDisplayCopyDisplayMode`
  - [x] `isBuiltin`, `isMain`, `isMirrored` (`CGDisplayIsInMirrorSet`)
  - [x] Dựng `persistentKey` từ vendor/model/serial — dùng `CGDisplayVendorNumber`/`ModelNumber`/`SerialNumber` (public API, gọn hơn parse EDID; EDID đầy đủ qua IOKit để dành Phase 3 khi cần map DDC)
- [x] `EventMonitor.swift` — `CGDisplayRegisterReconfigurationCallback`, debounce 300ms, callback `onChange`

### displayctl
- [x] Lệnh `list` (bảng đẹp) và `list --json`
- [x] Lệnh `watch` — in dòng log mỗi khi cắm/rút/đổi cấu hình

### Kiểm thử
- [x] Unit test: dựng `persistentKey` (7/7 test pass)
- [x] Test tay với 1 màn hình: `list` nhận đúng EK241Y (ID, tên, 1920x1080@60Hz, Ngoài, key `v1138-m1877-s16843009`); `watch` khởi động và in trạng thái đúng
- [ ] Test tay với nhiều màn hình: `list` đủ các màn; `watch` rồi rút/cắm cáp — sự kiện hiện ra trong ≤1s

**DoD:** đạt trên cấu hình 1 màn hình; chờ xác nhận với ≥2 màn hình.

---

## Phase 2 — Bật/tắt bằng Disconnect + an toàn (2–4 ngày) 🔶 code xong, chờ test với màn hình thứ 2

Mục tiêu: `displayctl off/on <id>` hoạt động; không thể tự khóa mình ra ngoài.

### Private API
- [x] `Private/SkyLight.swift`: `dlopen` + `dlsym` hàm `SLSConfigureDisplayEnabled` + `SLSMainConnectionID` — đã xác nhận cả 2 symbol tồn tại trên macOS 26.5
  - [x] Nếu symbol không tồn tại → trả `nil`, không crash (điều kiện để fallback)
- [x] `DisconnectStrategy.swift` implement `PowerControlStrategy`
- [x] Xác minh hành vi trên bản macOS đang dùng — **verify 2026-07-16 với 2 màn hình thật**: off/on qua disconnect hoạt động. *Bug đã sửa: tham số đầu của `SLSConfigureDisplayEnabled` là `CGDisplayConfigRef` (transaction), không phải connection ID — truyền cid làm WindowServer dereference số nguyên như con trỏ → SIGSEGV trong `checkCapacity(CGSConfigData*)`.*

### An toàn (bắt buộc trước khi thử lệnh tắt lần đầu!)
- [x] `SafetyGuard.validate`: chặn tắt màn hình active cuối cùng — **đã verify trên máy thật**: `off` màn hình duy nhất bị chặn kèm thông báo rõ ràng
- [x] `StateStore.swift`: ghi ý định trước khi tắt, xóa sau khi thành công (lưu tại `~/Library/Application Support/displayctl/state.json`, khóa theo `persistentKey`)
- [x] `displayctl restore` — bật lại **tất cả** màn hình + reset gamma; đã verify chạy an toàn khi không có gì để khôi phục
- [ ] **Bật SSH (Remote Login) trên máy trước khi test** — System Settings → General → Sharing → Remote Login (hiện đang TẮT)

### Fallback (public API)
- [x] `MirrorStrategy.swift` — `CGConfigureDisplayMirrorOfDisplay` (off = mirror màn chính, on = thoát mirror)
- [x] `GammaStrategy.swift` — gamma về đen; CLI in cảnh báo vì gamma tự reset khi process thoát
- [x] Chuỗi fallback trong `DisplayManager.setPower`: Disconnect → Mirror → Gamma; CLI in rõ strategy được dùng; `--strategy` để ép 1 chiến lược cụ thể (không fallback)

### Kiểm thử tay (checklist — cần màn hình thứ 2 + SSH bật)
- [x] Tắt màn hình ngoài → bật lại OK ✅ (verify 2026-07-16 qua CLI: off/on LG FULL HD khi P24FBA làm màn chính)
- [ ] Tắt màn hình chính khi có màn hình phụ → màn phụ thành chính → OK
- [x] Cố tắt màn hình cuối cùng → bị chặn kèm thông báo ✅ (verify 2026-07-15)
- [ ] Tắt màn hình → thoát app/CLI → mở lại → trạng thái được nhận đúng
- [ ] `restore` qua SSH khi đang tắt 1 màn hình → tất cả sáng lại
- [ ] Rút cáp màn hình đang bị tắt rồi cắm lại → không kẹt trạng thái

**DoD:** off/on ổn định qua ≥10 lần liên tiếp; mọi mục checklist an toàn đạt.

---

## Phase 3 — DDC: tắt nguồn thật cho màn hình ngoài (2–3 ngày)

Mục tiêu: `displayctl off <id> --ddc` đưa màn hình ngoài vào standby như bấm nút nguồn.

- [ ] `Private/IOAVService.swift` (Apple Silicon): `IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`, `IOAVServiceReadI2C` qua dlsym
- [ ] Map đúng `DCPAVServiceProxy` ↔ `CGDirectDisplayID` (khó nhất của phase này — đối chiếu EDID; tham khảo m1ddc/MonitorControl)
- [ ] (Nếu còn dùng máy Intel) nhánh I2C qua `IOFramebuffer` — bỏ qua nếu chỉ có Apple Silicon
- [ ] `DDCStrategy.swift`:
  - [ ] `isAvailable`: thử đọc VCP (capabilities hoặc đọc 0xD6) để dò hỗ trợ, cache theo `persistentKey`
  - [ ] `turnOff`: ghi VCP `0xD6` = `0x04` (hoặc `0x05` tùy màn hình); `turnOn`: `0x01`
  - [ ] Retry 2–3 lần với delay (DDC hay lỗi vặt), báo lỗi rõ khi màn hình không hỗ trợ
- [ ] CLI: thêm cờ `--ddc`; `list` hiển thị cột `DDC: yes/no`
- [ ] Test tay: tắt/bật qua DDC trên từng màn hình đang có; thử qua các cổng khác nhau (HDMI/USB-C/qua dock) và ghi lại kết quả vào README

**DoD:** DDC hoạt động trên ít nhất 1 màn hình thật; màn hình không hỗ trợ thì báo lỗi tử tế và tự dùng Disconnect thay thế.

*Ghi chú: một số màn hình khi standby bằng 0xD6 sẽ không đánh thức được bằng DDC (tự rút kênh I2C). Nếu gặp: dùng Disconnect làm mặc định, DDC chỉ là opt-in.*

---

## Phase 4 — Menu bar app (2–3 ngày)

Mục tiêu: điều khiển mọi thứ bằng chuột từ thanh menu — bấm icon trên menu bar là hiện dialog danh sách màn hình với switch bật/tắt.

### Khung app
- [x] Icon ứng dụng: `Resources/AppIcon.icns` (đủ 10 kích thước 16→1024, vẽ lại vector-sharp từ `monitor.png` gốc 128px; bản master `Resources/AppIcon-1024.png`)
- [x] Tạo target `App` — dùng SwiftPM thuần (`Sources/App/`, product `BetterDisplay`) + script đóng gói `scripts/build-app.sh`, không cần Xcode project
- [x] `LSUIElement = YES` (chỉ hiện trên menu bar, không chiếm Dock), gắn `AppIcon.icns` vào bundle (`Packaging/Info.plist`)

### Icon trên thanh menu (menu bar)
- [x] `BetterDisplayApp.swift` — `MenuBarExtra` hiển thị icon thường trực trên menu bar
- [x] Icon template tự đảo màu theo light/dark mode — dùng SF Symbol `display` (biến thể đen-trắng từ monitor.png để dành khi muốn cá nhân hóa)

### Dialog danh sách màn hình (bấm icon để mở)
- [x] `MenuBarExtra(style: .window)` → bấm icon mở popover/dialog thay vì menu chữ
- [x] `AppState.swift` — subscribe `DisplayManager` + `EventMonitor`; hiển thị cả màn hình đã disconnect (ghost row từ `StateStore`, có lưu tên) để bật lại được
- [x] `MenuView.swift` — mỗi màn hình 1 hàng: tên + độ phân giải + trạng thái + **nút switch bật/tắt** gọi `DisplayManager.setPower`
  - [x] Switch của màn hình active cuối cùng bị disable + tooltip giải thích (SafetyGuard)
  - [ ] Menu phụ mỗi màn hình: chọn strategy (Disconnect / DDC / Gamma) — *để sau, hiện dùng chuỗi fallback mặc định*
  - [x] Nút "Bật tất cả màn hình" (restore) + "Thoát"
- [x] Dialog tự cập nhật realtime khi cắm/rút cáp *(code xong — cần test tay khi có màn hình thứ 2)*

### Settings (trong dialog)
- [x] **Khởi động cùng máy (Launch at Login)**: toggle dùng `SMAppService.mainApp.register()`/`unregister()`, tự hoàn tác + báo lỗi nếu thất bại
- [ ] Lưu tùy chọn bằng `UserDefaults`: strategy ưa thích từng màn hình — *để sau, cùng lúc với menu phụ strategy*

### Hoàn thiện phase
- [x] Xử lý app thoát khi đang dùng GammaStrategy: `applicationWillTerminate` bật lại gamma, dọn record mồ côi trong state.json
- [x] Ad-hoc codesign + build Release qua `scripts/build-app.sh` → `dist/Better Display.app`; người dùng tự chép vào `/Applications`

**DoD:** dùng app cả ngày không cần mở terminal; bấm icon menu bar → dialog hiện đủ màn hình với switch hoạt động; bật "khởi động cùng máy" rồi reboot → app tự chạy; cắm/rút màn hình UI khớp thực tế; không crash.

---

## Phase 5 — Hoàn thiện (tùy chọn, làm dần)

- ~~Launch at login~~ → đã chuyển lên Phase 4 (mục Settings)
- [ ] Phím tắt toàn cục bật/tắt màn hình (ví dụ ⌥⌘1/2/3) — `Carbon RegisterEventHotKey` hoặc thư viện `HotKey`
- [ ] Ghi nhớ strategy ưa thích theo từng màn hình (`StateStore`)
- [ ] Tùy chọn: tự tắt màn hình X khi rút màn hình Y (rule engine đơn giản)
- [ ] Icon menu bar đổi trạng thái (số màn hình đang tắt)
- [ ] README.md: hướng dẫn build, cài, ma trận màn hình đã test, ghi chú tương thích macOS
- [ ] Khi lên bản macOS mới: chạy lại checklist Phase 2 để xác minh private API còn sống

---

## Sổ tay rủi ro (đọc lại khi gặp sự cố)

| Rủi ro | Phòng ngừa |
|---|---|
| Private API đổi/mất sau update macOS | dlsym trả nil → fallback tự động; checklist re-test mỗi bản macOS |
| Tắt hết màn hình, không thấy gì | SafetyGuard + `displayctl restore` qua SSH (bật Remote Login sẵn) |
| DDC không ăn với màn hình/dock cụ thể | Dò `isAvailable` + cache; DDC là opt-in, Disconnect là mặc định |
| `CGDirectDisplayID` đổi sau reboot/cắm lại | Mọi cấu hình khóa theo `persistentKey` (EDID), không theo ID |
| Gamma reset khi process chết | Chỉ dùng Gamma làm fallback cuối; GUI giữ process sống |
