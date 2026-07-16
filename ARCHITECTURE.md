# Kiến trúc — Better Display

Tiện ích macOS (cài đặt cá nhân) để **nhận dạng các màn hình** đang kết nối và **bật / tắt từng màn hình**.

- Ngôn ngữ: **Swift 5.9+**
- Nền tảng: **macOS 13+** (Apple Silicon & Intel)
- Hình thức: **Menu bar app** (SwiftUI + AppKit) kèm **CLI** `displayctl` để test và dùng qua terminal/SSH
- Phân phối: chạy trên máy cá nhân, ad-hoc codesign — **được phép dùng private API**

---

## 1. Sơ đồ tổng thể

```
┌────────────────────────┐   ┌────────────────────────┐
│   App (menu bar GUI)   │   │   displayctl (CLI)     │
│  SwiftUI + AppKit      │   │  swift-argument-parser │
└───────────┬────────────┘   └───────────┬────────────┘
            │        cùng dùng chung     │
            ▼                            ▼
┌─────────────────────────────────────────────────────┐
│                  DisplayCore (thư viện lõi)          │
│                                                     │
│  DisplayManager ──── DisplayInfo (model)            │
│       │                                             │
│       ├── EventMonitor (hotplug callback)           │
│       ├── SafetyGuard  (chặn tắt màn hình cuối)     │
│       └── PowerControl (protocol + các strategy)    │
│             ├── DisconnectStrategy  (SkyLight, A)   │
│             ├── DDCStrategy         (I2C/DDC, B)    │
│             ├── MirrorStrategy      (public API, C) │
│             └── GammaStrategy       (public API, D) │
└───────────┬─────────────────────────┬───────────────┘
            ▼                         ▼
   CoreGraphics / AppKit      SkyLight / IOKit (private)
```

Nguyên tắc: **DisplayCore không phụ thuộc UI**. GUI và CLI chỉ là hai lớp vỏ mỏng gọi vào lõi.

---

## 2. Cấu trúc thư mục

```
better-display/
├── Package.swift
├── ARCHITECTURE.md
├── TODO.md
├── Sources/
│   ├── DisplayCore/
│   │   ├── DisplayManager.swift        # Liệt kê màn hình, phát sự kiện thay đổi
│   │   ├── DisplayInfo.swift           # Struct mô tả 1 màn hình
│   │   ├── EventMonitor.swift          # CGDisplayRegisterReconfigurationCallback
│   │   ├── SafetyGuard.swift           # Luật an toàn trước khi tắt
│   │   ├── StateStore.swift            # Lưu/khôi phục trạng thái (JSON ~/Library)
│   │   ├── PowerControl/
│   │   │   ├── PowerControlStrategy.swift   # protocol chung
│   │   │   ├── DisconnectStrategy.swift     # SLSConfigureDisplayEnabled (SkyLight)
│   │   │   ├── DDCStrategy.swift            # VCP 0xD6 qua I2C
│   │   │   ├── MirrorStrategy.swift         # CGConfigureDisplayMirrorOfDisplay
│   │   │   └── GammaStrategy.swift          # CGSetDisplayTransferByFormula
│   │   └── Private/
│   │       ├── SkyLight.swift          # khai báo hàm private (dlopen/dlsym)
│   │       └── IOAVService.swift       # khai báo IOAVService* (Apple Silicon DDC)
│   ├── displayctl/
│   │   └── main.swift                  # CLI: list / on / off / restore / watch
│   └── App/
│       ├── BetterDisplayApp.swift      # @main, MenuBarExtra
│       ├── MenuView.swift              # Danh sách màn hình + toggle
│       └── AppState.swift              # ObservableObject bọc DisplayManager
└── Tests/
    └── DisplayCoreTests/
```

---

## 3. Các thành phần lõi

### 3.1 `DisplayInfo` — model dữ liệu

```swift
struct DisplayInfo: Identifiable, Codable {
    let id: CGDirectDisplayID       // ID phiên làm việc (đổi khi cắm lại)
    let persistentKey: String       // vendor+model+serial → nhận ra màn hình qua các lần cắm
    let name: String                // NSScreen.localizedName
    let isBuiltin: Bool             // CGDisplayIsBuiltin
    let isMain: Bool                // CGDisplayIsMain
    let resolution: CGSize
    let refreshRate: Double
    let isEnabled: Bool             // đang active hay đã bị disconnect
    let isMirrored: Bool
    let supportsDDC: Bool           // dò được kênh DDC hay không
}
```

`persistentKey` quan trọng: `CGDirectDisplayID` thay đổi giữa các lần cắm/khởi động, nên mọi cấu hình lưu trữ phải khóa theo vendor/model/serial (đọc từ EDID), không theo ID.

### 3.2 `DisplayManager`

- `func allDisplays() -> [DisplayInfo]` — hợp nhất `CGGetOnlineDisplayList` (mọi màn hình kể cả đang tắt) và `CGGetActiveDisplayList` (đang hoạt động) để suy ra `isEnabled`.
- `func setPower(_ on: Bool, display: DisplayInfo, using: StrategyKind?) throws`
  - Chạy `SafetyGuard.validate` trước.
  - Nếu không chỉ định strategy: thử theo thứ tự **Disconnect → Mirror → Gamma** (và DDC nếu người dùng chọn "tắt nguồn thật").
- Phát sự kiện qua `AsyncStream<[DisplayInfo]>` (hoặc Combine) để UI tự cập nhật.

### 3.3 `EventMonitor`

Bọc `CGDisplayRegisterReconfigurationCallback`. Debounce ~300ms (một lần cắm màn hình sinh nhiều callback liên tiếp) rồi mới yêu cầu `DisplayManager` refresh.

### 3.4 `PowerControlStrategy` (protocol)

```swift
protocol PowerControlStrategy {
    var kind: StrategyKind { get }
    func isAvailable(for display: DisplayInfo) -> Bool
    func turnOff(_ display: DisplayInfo) throws
    func turnOn(_ display: DisplayInfo) throws
}
```

| Strategy | Cơ chế | API | Phạm vi | Rủi ro |
|---|---|---|---|---|
| **Disconnect** (A — mặc định) | macOS coi màn hình như đã rút cáp | `SLSConfigureDisplayEnabled(config, id, enabled)` (SkyLight, private) — tham số đầu là `CGDisplayConfigRef`, phải gọi trong transaction `CGBeginDisplayConfiguration`/`CGCompleteDisplayConfiguration` | Mọi màn hình | Private API có thể đổi giữa các bản macOS |
| **DDC** (B — "tắt nguồn thật") | Gửi VCP `0xD6` (power mode) tới màn hình | Apple Silicon: `IOAVService` + `AVServiceWriteI2C` (private); Intel: I2C qua IOFramebuffer | Chỉ màn hình ngoài, không qua DisplayLink | Tùy màn hình có hỗ trợ |
| **Mirror** (C — fallback) | Màn hình chỉ mirror màn hình chính | `CGConfigureDisplayMirrorOfDisplay` (public) | Mọi màn hình | Màn hình vẫn sáng |
| **Gamma** (D — fallback cuối) | Kéo gamma về đen | `CGSetDisplayTransferByFormula` (public) | Mọi màn hình | Vẫn sáng đèn nền; reset khi app thoát |

Private API được nạp **runtime bằng `dlopen`/`dlsym`** (không link tĩnh) — nếu macOS mới bỏ hàm, app vẫn chạy và tự chuyển sang fallback thay vì crash.

### 3.5 `SafetyGuard`

Luật bắt buộc trước mọi lệnh tắt:

1. **Không bao giờ** cho tắt màn hình đang active cuối cùng.
2. Ghi "ý định tắt" vào `StateStore` **trước khi** thực thi; app khởi động lại thấy trạng thái dở dang → tự khôi phục.
3. CLI `displayctl restore` bật lại toàn bộ màn hình — lối thoát khi mất hình (chạy được qua SSH).
4. (GUI, tùy chọn) đếm ngược 10s "giữ thay đổi?" kiểu như khi đổi độ phân giải.

### 3.6 `StateStore`

JSON tại `~/Library/Application Support/BetterDisplay/state.json`: trạng thái mong muốn theo `persistentKey`, thao tác dở dang, strategy ưa thích của từng màn hình.

---

## 4. CLI `displayctl`

```
displayctl list [--json]      # liệt kê màn hình + trạng thái
displayctl off <id|tên>       # tắt (mặc định Disconnect)
displayctl off <id> --ddc     # tắt nguồn thật qua DDC
displayctl on  <id|tên>
displayctl restore            # bật lại tất cả (cứu hộ)
displayctl watch              # in sự kiện cắm/rút realtime
```

CLI ra đời **trước** GUI: là công cụ test từng strategy và là phương án cứu hộ.

---

## 5. Menu bar app

- `MenuBarExtra` (SwiftUI, macOS 13+), không có cửa sổ chính, ẩn Dock icon (`LSUIElement`).
- Mỗi màn hình một hàng: tên + độ phân giải + `Toggle` bật/tắt.
- `AppState: ObservableObject` subscribe stream từ `DisplayManager` → UI luôn khớp thực tế kể cả khi cắm/rút cáp.
- Launch at login qua `SMAppService` (phase 5).

---

## 6. Xử lý lỗi & kiểm thử

- Lỗi có ngữ cảnh: `PowerControlError.strategyUnavailable(kind, reason)` → UI/CLI hiển thị rõ "màn hình X không hỗ trợ DDC" thay vì fail im lặng.
- Unit test cho phần thuần logic (SafetyGuard, StateStore, parse EDID) — mock danh sách màn hình.
- Phần gọi API hệ thống test thủ công bằng CLI theo checklist trong TODO.md (cần màn hình thật).

## 7. Tài liệu tham khảo

- [MonitorControl](https://github.com/MonitorControl/MonitorControl) — mã mở, DDC đầy đủ cho Intel + Apple Silicon
- [m1ddc](https://github.com/waydabber/m1ddc) — DDC tối giản trên Apple Silicon (cùng tác giả BetterDisplay)
- [displayplacer](https://github.com/jakehilborn/displayplacer) — thao tác cấu hình màn hình bằng CGS API
- VESA MCCS spec — ý nghĩa các VCP code (0xD6 = power mode)
