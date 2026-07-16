import ArgumentParser
import CoreGraphics
import DisplayCore
import Foundation

@main
struct Displayctl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "displayctl",
        abstract: "Nhận dạng và bật/tắt màn hình trên macOS.",
        version: "0.4.0",
        subcommands: [
            List.self, Off.self, On.self, Restore.self, Watch.self,
            Brightness.self, Modes.self, Resolution.self, Mirror.self, Rotate.self,
        ],
        defaultSubcommand: List.self
    )
}

extension StrategyKind: ExpressibleByArgument {}

// MARK: - Helpers

private func resolveTarget(_ query: String, in displays: [DisplayInfo]) throws -> DisplayInfo {
    if let id = UInt32(query), let match = displays.first(where: { $0.id == id }) {
        return match
    }
    let matches = displays.filter { $0.name.localizedCaseInsensitiveContains(query) }
    switch matches.count {
    case 1:
        return matches[0]
    case 0:
        throw ValidationError("Không tìm thấy màn hình khớp \"\(query)\". Chạy `displayctl list` để xem danh sách.")
    default:
        let names = matches.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        throw ValidationError("\"\(query)\" khớp nhiều màn hình: \(names). Hãy dùng ID.")
    }
}

private func printTable(_ displays: [DisplayInfo]) {
    func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
    print(pad("ID", 12) + pad("TÊN", 22) + pad("TRẠNG THÁI", 12)
        + pad("ĐỘ PHÂN GIẢI", 16) + pad("TẦN SỐ", 9) + pad("LOẠI", 10) + pad("DDC", 6) + "KEY")
    for d in displays {
        let status = d.isEnabled ? (d.isMirrored ? "MIRROR" : "ON") : "OFF"
        let main = d.isMain ? " *" : ""
        print(pad(String(d.id), 12)
            + pad(d.name + main, 22)
            + pad(status, 12)
            + pad("\(Int(d.resolution.width))x\(Int(d.resolution.height))", 16)
            + pad(d.refreshRate > 0 ? "\(Int(d.refreshRate.rounded()))Hz" : "-", 9)
            + pad(d.isBuiltin ? "Tích hợp" : "Ngoài", 10)
            + pad(d.supportsDDC ? "yes" : "no", 6)
            + d.persistentKey)
    }
    if displays.contains(where: \.isMain) {
        print("\n(*) màn hình chính")
    }
}

// MARK: - Subcommands

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Liệt kê các màn hình đang kết nối.")

    @Flag(name: .long, help: "Xuất JSON thay vì bảng.")
    var json = false

    func run() throws {
        let displays = DisplayManager().allDisplays()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try encoder.encode(displays), encoding: .utf8) ?? "[]")
        } else {
            printTable(displays)
        }
    }
}

struct Off: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tắt một màn hình (mặc định: disconnect, fallback mirror/gamma).")

    @Argument(help: "ID hoặc tên màn hình (xem `displayctl list`).")
    var display: String

    @Option(name: .long, help: "Ép dùng một chiến lược: disconnect | mirror | gamma.")
    var strategy: StrategyKind?

    func run() throws {
        let manager = DisplayManager()
        let target = try resolveTarget(display, in: manager.allDisplays())
        let used = try manager.setPower(false, displayID: target.id, preferred: strategy)
        print("Đã tắt \"\(target.name)\" (ID \(target.id)) bằng chiến lược \(used.rawValue).")
        print("Bật lại: displayctl on \(target.id)   |   Cứu hộ: displayctl restore")
        if used == .gamma {
            print("⚠️  Gamma tự reset khi tiến trình thoát — qua CLI hiệu ứng không giữ được lâu dài.")
        }
    }
}

struct On: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Bật lại một màn hình đã tắt.")

    @Argument(help: "ID hoặc tên màn hình.")
    var display: String

    @Option(name: .long, help: "Ép dùng một chiến lược: disconnect | mirror | gamma.")
    var strategy: StrategyKind?

    func run() throws {
        let manager = DisplayManager()
        // Màn hình đã disconnect có thể không còn trong danh sách — cho phép truyền ID thô.
        let displays = manager.allDisplays()
        let targetID: CGDirectDisplayID
        if let found = try? resolveTarget(display, in: displays) {
            targetID = found.id
        } else if let raw = UInt32(display) {
            targetID = raw
        } else {
            throw ValidationError("Không tìm thấy màn hình \"\(display)\". Với màn hình đã disconnect, hãy dùng ID số (xem `displayctl restore` nếu không nhớ).")
        }
        let used = try manager.setPower(true, displayID: targetID, preferred: strategy)
        print("Đã bật màn hình ID \(targetID) bằng chiến lược \(used.rawValue).")
    }
}

struct Restore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Cứu hộ: bật lại TẤT CẢ màn hình từng bị tắt và reset gamma.")

    func run() throws {
        let results = DisplayManager().restoreAll()
        if results.isEmpty {
            print("Không có màn hình nào được ghi nhận là đang tắt. Đã reset gamma toàn cục.")
            return
        }
        for (id, result) in results {
            switch result {
            case .success(let kind):
                print("Đã bật lại màn hình \(id) (chiến lược \(kind.rawValue)).")
            case .failure(let error):
                print("Không bật lại được màn hình \(id): \(error.localizedDescription)")
            }
        }
    }
}

struct Brightness: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Đọc/đặt độ sáng màn hình ngoài qua DDC (VCP 0x10).")

    @Argument(help: "ID hoặc tên màn hình.")
    var display: String

    @Argument(help: "Độ sáng 0-100 (%). Bỏ trống để đọc giá trị hiện tại.")
    var value: Int?

    func run() throws {
        let target = try resolveTarget(display, in: DisplayManager().allDisplays())
        guard let current = BrightnessControl.brightness(for: target.id) else {
            throw ValidationError("\"\(target.name)\" không trả lời lệnh đọc độ sáng qua DDC.")
        }
        if let value {
            guard (0...100).contains(value) else { throw ValidationError("Độ sáng phải trong khoảng 0-100.") }
            let raw = UInt16((Double(value) / 100 * Double(current.max)).rounded())
            try BrightnessControl.setBrightness(raw, for: target.id)
            print("Đã đặt độ sáng \"\(target.name)\" = \(value)% (\(raw)/\(current.max)).")
        } else {
            let percent = Int((Double(current.current) / Double(max(current.max, 1)) * 100).rounded())
            print("\(target.name): \(percent)% (\(current.current)/\(current.max))")
        }
    }
}

struct Modes: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Liệt kê các display mode khả dụng của màn hình.")

    @Argument(help: "ID hoặc tên màn hình.")
    var display: String

    func run() throws {
        let target = try resolveTarget(display, in: DisplayManager().allDisplays())
        print("Các kích thước của \"\(target.name)\" (dùng cho `displayctl resolution`):")
        for choice in DisplayModeControl.sizeChoices(for: target.id) {
            let marks = [
                choice.isCurrent ? "← hiện tại" : nil,
                choice.isHiDPI ? "HiDPI" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            print("  \(choice.label)\t\(Int(choice.refreshRate.rounded()))Hz" + (marks.isEmpty ? "" : "\t(\(marks))"))
        }
    }
}

struct Resolution: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Đổi kích thước màn hình, ví dụ: displayctl resolution 1 1920x1080")

    @Argument(help: "ID hoặc tên màn hình.")
    var display: String

    @Argument(help: "Kích thước dạng WxH, ví dụ 1920x1080.")
    var size: String

    func run() throws {
        let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { throw ValidationError("Kích thước phải có dạng WxH, ví dụ 1920x1080.") }
        let target = try resolveTarget(display, in: DisplayManager().allDisplays())
        try DisplayModeControl.setResolution(width: parts[0], height: parts[1], for: target.id)
        print("Đã đổi \"\(target.name)\" sang \(parts[0])×\(parts[1]). Đổi lại nếu cần: displayctl modes \(target.id)")
    }
}

struct Mirror: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Bật/tắt mirror: displayctl mirror <id> --of <id màn chính> | --off")

    @Argument(help: "ID hoặc tên màn hình sẽ đi mirror màn khác.")
    var display: String

    @Option(name: .long, help: "ID hoặc tên màn hình được mirror theo (master).")
    var of: String?

    @Flag(name: .long, help: "Thoát chế độ mirror.")
    var off = false

    func run() throws {
        let displays = DisplayManager().allDisplays()
        let target = try resolveTarget(display, in: displays)
        if off {
            try MirrorControl.setMirror(target.id, of: nil)
            print("\"\(target.name)\" đã thoát mirror.")
        } else if let of {
            let master = try resolveTarget(of, in: displays)
            try MirrorControl.setMirror(target.id, of: master.id)
            print("\"\(target.name)\" đang mirror \"\(master.name)\".")
        } else {
            if let master = MirrorControl.master(of: target.id),
               let info = displays.first(where: { $0.id == master }) {
                print("\"\(target.name)\" đang mirror \"\(info.name)\".")
            } else {
                print("\"\(target.name)\" không mirror màn hình nào. Dùng --of <id> hoặc --off.")
            }
        }
    }
}

struct Rotate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Xoay màn hình: displayctl rotate <id> <0|90|180|270>")

    @Argument(help: "ID hoặc tên màn hình.")
    var display: String

    @Argument(help: "Góc xoay 0/90/180/270. Bỏ trống để đọc góc hiện tại.")
    var degrees: Int?

    func run() throws {
        let target = try resolveTarget(display, in: DisplayManager().allDisplays())
        if let degrees {
            try RotationControl.setRotation(degrees, for: target.id)
            print("Đã xoay \"\(target.name)\" sang \(degrees)°.")
        } else {
            print("\(target.name): \(RotationControl.rotation(for: target.id))°")
        }
    }
}

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Theo dõi realtime sự kiện cắm/rút/đổi cấu hình màn hình.")

    func run() throws {
        let manager = DisplayManager()
        let monitor = EventMonitor()
        print("Đang theo dõi sự kiện màn hình (Ctrl+C để thoát)…\n")
        printTable(manager.allDisplays())
        monitor.onChange = {
            print("\n[\(ISO8601DateFormatter().string(from: Date()))] Cấu hình màn hình thay đổi:")
            printTable(manager.allDisplays())
        }
        monitor.start()
        CFRunLoopRun()
    }
}
