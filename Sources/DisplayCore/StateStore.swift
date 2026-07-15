import CoreGraphics
import Foundation

/// Ghi nhận một màn hình đã bị tắt: bằng chiến lược nào, lúc nào.
/// Được ghi TRƯỚC khi thực thi lệnh tắt — nếu app/CLI chết giữa chừng,
/// lần chạy sau vẫn biết đường khôi phục (`restore`).
public struct DisabledRecord: Codable, Equatable {
    public let displayID: CGDirectDisplayID
    public let persistentKey: String
    public let strategy: StrategyKind
    public let date: Date

    public init(displayID: CGDirectDisplayID, persistentKey: String, strategy: StrategyKind, date: Date) {
        self.displayID = displayID
        self.persistentKey = persistentKey
        self.strategy = strategy
        self.date = date
    }
}

/// Lưu trạng thái ra JSON tại ~/Library/Application Support/displayctl/state.json.
public final class StateStore {
    private struct State: Codable {
        var disabled: [DisabledRecord] = []
    }

    private let fileURL: URL
    private var state: State

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("displayctl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("state.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? decoder.decode(State.self, from: data) {
            self.state = loaded
        } else {
            self.state = State()
        }
    }

    public func recordDisabled(_ record: DisabledRecord) {
        state.disabled.removeAll { $0.displayID == record.displayID }
        state.disabled.append(record)
        save()
    }

    public func removeDisabled(displayID: CGDirectDisplayID) {
        state.disabled.removeAll { $0.displayID == displayID }
        save()
    }

    public func disabledRecord(for displayID: CGDirectDisplayID) -> DisabledRecord? {
        state.disabled.first { $0.displayID == displayID }
    }

    public func allDisabled() -> [DisabledRecord] {
        state.disabled
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
