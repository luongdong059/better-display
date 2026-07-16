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

**DoD:** ✅ off/on ổn định 10/10 chu kỳ liên tiếp (stress test 2026-07-16, disconnect trên LG FULL HD); các mục test tay còn lại (SSH restore, rút cáp khi đang tắt) là tùy chọn.

---

## Phase 3 — DDC: tắt nguồn thật cho màn hình ngoài ✅ (verify 2026-07-16)

Mục tiêu: đưa màn hình ngoài vào standby như bấm nút nguồn.

- [x] `Private/IOAVService.swift` (Apple Silicon): `IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`, `IOAVServiceReadI2C` qua dlsym
  - *Bẫy đã gặp: `IOAVServiceCopyEDID` trả về IOReturn (out-param), không phải CFData — gọi sai chữ ký là SIGSEGV. Đã bỏ, đọc EDID qua `IOAVServiceReadI2C` chip 0x50.*
- [x] Map `DCPAVServiceProxy` ↔ `CGDirectDisplayID`: property "EDID UUID" đã biến mất khỏi proxy trên macOS 26 → đọc EDID trực tiếp qua I2C của từng proxy rồi so vendor/model/serial với CG. Màn hình standby không trả lời EDID → fallback "proxy im lặng duy nhất" để wake được.
- [x] ~~Nhánh Intel IOFramebuffer~~ — bỏ, chỉ hỗ trợ Apple Silicon
- [x] `DDCStrategy.swift`:
  - [x] `probeSupport` (đọc VCP 0xD6) cho cột DDC trong list; `isAvailable` chỉ cần tìm được kênh (màn standby vẫn nhận lệnh ghi wake)
  - [x] `turnOff`: VCP `0xD6` = `0x04` (standby); `turnOn`: `0x01`
  - [x] Retry 3 lần với delay; báo lỗi rõ khi không có kênh DDC
- [x] CLI: `off/on --strategy ddc`; `list` có cột `DDC: yes/no`
- [x] Test tay trên LG FULL HD (USB-C): tắt → standby thật ✅, bật lại từ standby ✅. P24FBA (HDMI): dò DDC yes, chưa test chu kỳ đầy đủ.
- [x] DDC **không** nằm trong chuỗi fallback mặc định — chỉ chạy khi chọn tường minh (an toàn trước màn hình không wake được)

**DoD:** ✅ đạt — DDC off/on hoạt động trên màn hình thật; lỗi báo tử tế.

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
  - [x] Menu phụ mỗi màn hình (nút ⋯): chọn cách tắt — Tự động / Disconnect / DDC (chỉ hiện khi hỗ trợ) / Gamma
  - [x] Nút "Bật tất cả màn hình" (restore) + "Thoát"
- [x] Dialog tự cập nhật realtime khi cắm/rút cáp *(code xong — cần test tay khi có màn hình thứ 2)*

### Settings (trong dialog)
- [x] **Khởi động cùng máy (Launch at Login)**: toggle dùng `SMAppService.mainApp.register()`/`unregister()`, tự hoàn tác + báo lỗi nếu thất bại
- [x] Lưu tùy chọn bằng `UserDefaults`: strategy ưa thích theo `persistentKey` từng màn hình
- [x] Footer dialog: "Design by Dong" + số phiên bản (v0.3.0)

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

## Phase 6 — Điều khiển nâng cao từng màn hình ✅ (verify 2026-07-16, app v0.4.0)

Mục tiêu: mỗi hàng màn hình trong dialog có **nút xổ xuống** mở khu điều khiển riêng: độ sáng (slider), kích thước (slider), xoay màn hình, mirror.

### 6A. Độ sáng — slider ✅
- [x] `BrightnessControl.swift`: đọc/ghi VCP `0x10` qua `IOAVServiceDDC`
- [x] Cache DDC service theo display (dò registry + EDID mỗi lần quá chậm cho slider); tự xóa khi cắm/rút cáp hoặc ghi lỗi; chỉ cache kết quả match EDID chắc chắn
- [x] Throttle ghi 150ms trong AppState (UI cập nhật ngay, DDC ghi trễ)
- [x] CLI: `displayctl brightness <id> [0-100]`
- [x] UI: Slider ☀️ + %; thông báo với màn không hỗ trợ DDC
- [x] Test thật: đọc cả 2 màn (100%, 97%); set LG 50% → đọc lại đúng → trả về 97% ✅

### 6B. Kích thước màn hình — slider ✅
- [x] `DisplayModeControl.swift`: `sizeChoices` gộp mode trùng WxH (ưu tiên HiDPI, tần số gần hiện tại), sắp theo diện tích
- [x] Đổi mode qua transaction `CGConfigureDisplayWithDisplayMode`
- [x] **Đếm ngược hoàn tác 10s** trong app (banner Giữ/Hoàn tác, tự revert khi hết giờ)
- [x] CLI: `displayctl modes <id>` (17 mode trên LG) và `displayctl resolution <id> <WxH>`
- [x] UI: slider bậc thang, chỉ áp dụng khi thả tay
- [x] Test thật: LG 1920×1080 → 1280×720 → 1920×1080@75Hz ✅

### 6C. Mirror ✅
- [x] `MirrorControl.setMirror(display, of: master?)` + `master(of:)`; MirrorStrategy refactor để gọi chung
- [x] CLI: `displayctl mirror <id> --of <id>` / `--off` / không tham số = đọc trạng thái
- [x] UI: Picker "Mirror: Tắt / <màn hình khác>"; vẫn truy cập được khi màn đang mirror (để thoát)
- [x] Test thật: LG mirror P24FBA → thoát ✅. Lưu ý: màn bị mirror rời active list, mất tên NSScreen (hiện "Display <id>")

### 6D. Xoay màn hình ✅ — dùng MonitorPanel.framework (ObjC), KHÔNG dùng SLSSetDisplayRotation
- [x] Thăm dò bằng `dyld_info -exports`: SkyLight có `SLSSetDisplayRotation` (C, chữ ký rủi ro) và MonitorPanel có `MPDisplayMgr`/`MPDisplay` (ObjC) → chọn ObjC vì introspect được selector trước khi gọi, sai tên không corrupt stack
- [x] `RotationControl.swift`: `MPDisplayMgr.displays` → match `displayID` → KVC `setValue(_:forKey:"orientation")` (gọi `setOrientation:`); kiểm tra `responds(to:)` từng bước
  - *Bẫy đã gặp: static `let handle` (dlopen) là lazy — không chạm vào thì `NSClassFromString` trả nil. Phải guard `handle != nil` trước.*
- [x] Đọc góc: `CGDisplayRotation` (public)
- [x] CLI: `displayctl rotate <id> [0|90|180|270]`
- [x] UI: Picker segmented 4 góc
- [x] Test thật: LG 0° → 90° (list báo 1080x1920) → 0° ✅

### UI xổ xuống ✅
- [x] Chevron xổ xuống trên mỗi hàng (animation xoay 90°); hàng chính giữ nguyên tên + switch + menu ⋯
- [x] Chỉ đọc DDC khi mở khu điều khiển (`onAppear` → `loadBrightness`)
- [x] `ScrollView` maxHeight 420 khi >3 màn hình
- [x] Trạng thái mở/đóng là `@State` theo phiên
- [x] Màn đang mirror: chỉ hiện mục Mirror (để thoát); màn ghost/tắt: không xổ được

**DoD:** ✅ đạt toàn bộ qua CLI trên 2 màn hình thật; UI dialog xổ xuống hoạt động (app v0.4.0 đã cài).

---

## Sổ tay rủi ro (đọc lại khi gặp sự cố)

| Rủi ro | Phòng ngừa |
|---|---|
| Private API đổi/mất sau update macOS | dlsym trả nil → fallback tự động; checklist re-test mỗi bản macOS |
| Tắt hết màn hình, không thấy gì | SafetyGuard + `displayctl restore` qua SSH (bật Remote Login sẵn) |
| DDC không ăn với màn hình/dock cụ thể | Dò `isAvailable` + cache; DDC là opt-in, Disconnect là mặc định |
| `CGDirectDisplayID` đổi sau reboot/cắm lại | Mọi cấu hình khóa theo `persistentKey` (EDID), không theo ID |
| Gamma reset khi process chết | Chỉ dùng Gamma làm fallback cuối; GUI giữ process sống |
