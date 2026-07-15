import ArgumentParser
import CoreGraphics
import DisplayCore
import Foundation

@main
struct Displayctl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "displayctl",
        abstract: "Nhận dạng và bật/tắt màn hình trên macOS.",
        version: "0.1.0",
        subcommands: [List.self, Off.self, On.self, Restore.self, Watch.self],
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
        + pad("ĐỘ PHÂN GIẢI", 16) + pad("TẦN SỐ", 9) + pad("LOẠI", 10) + "KEY")
    for d in displays {
        let status = d.isEnabled ? (d.isMirrored ? "MIRROR" : "ON") : "OFF"
        let main = d.isMain ? " *" : ""
        print(pad(String(d.id), 12)
            + pad(d.name + main, 22)
            + pad(status, 12)
            + pad("\(Int(d.resolution.width))x\(Int(d.resolution.height))", 16)
            + pad(d.refreshRate > 0 ? "\(Int(d.refreshRate.rounded()))Hz" : "-", 9)
            + pad(d.isBuiltin ? "Tích hợp" : "Ngoài", 10)
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
