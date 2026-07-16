import AppKit
import CoreGraphics
import DisplayCore
import ServiceManagement
import SwiftUI

/// Trạng thái trung tâm của app: danh sách màn hình (kể cả màn hình đã
/// disconnect — không còn trong danh sách online), lỗi gần nhất, và settings.
final class AppState: ObservableObject {
    struct Row: Identifiable {
        let info: DisplayInfo
        /// Màn hình đã disconnect, chỉ còn trong StateStore — hiển thị để bật lại được.
        let isGhost: Bool
        var id: CGDirectDisplayID { info.id }
    }

    @Published private(set) var rows: [Row] = []
    @Published var lastError: String?
    /// Strategy ưa thích theo persistentKey (nil = tự động: Disconnect → fallback).
    @Published private(set) var preferredStrategies: [String: StrategyKind] = [:]
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchToggle, launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            applyLaunchAtLogin()
        }
    }

    private let store: StateStore
    private let manager: DisplayManager
    private let monitor = EventMonitor()
    private var isSyncingLaunchToggle = false
    private static let preferencesKey = "preferredStrategies"

    init() {
        let store = StateStore()
        self.store = store
        self.manager = DisplayManager(store: store)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        if let raw = UserDefaults.standard.dictionary(forKey: Self.preferencesKey) as? [String: String] {
            self.preferredStrategies = raw.compactMapValues(StrategyKind.init(rawValue:))
        }
        refresh()
        monitor.onChange = { [weak self] in self?.refresh() }
        monitor.start()
    }

    func refresh() {
        let live = manager.allDisplays()
        let liveIDs = Set(live.map(\.id))
        let ghosts = manager.disabledRecords()
            .filter { !liveIDs.contains($0.displayID) }
            .map { record in
                Row(
                    info: DisplayInfo(
                        id: record.displayID,
                        persistentKey: record.persistentKey,
                        name: record.name ?? "Màn hình \(record.displayID)",
                        isBuiltin: false,
                        isMain: false,
                        resolution: .zero,
                        refreshRate: 0,
                        isEnabled: false,
                        isMirrored: false),
                    isGhost: true)
            }
        rows = live.map { Row(info: $0, isGhost: false) } + ghosts
    }

    func setPower(_ on: Bool, for row: Row) {
        do {
            try manager.setPower(on, displayID: row.info.id,
                                 preferred: preferredStrategies[row.info.persistentKey])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func setPreferredStrategy(_ kind: StrategyKind?, for row: Row) {
        if let kind {
            preferredStrategies[row.info.persistentKey] = kind
        } else {
            preferredStrategies.removeValue(forKey: row.info.persistentKey)
        }
        UserDefaults.standard.set(
            preferredStrategies.mapValues(\.rawValue), forKey: Self.preferencesKey)
    }

    func restoreAll() {
        let failures = manager.restoreAll().filter {
            if case .failure = $0.result { return true } else { return false }
        }
        lastError = failures.isEmpty ? nil : "Không bật lại được \(failures.count) màn hình."
        refresh()
    }

    /// Switch của màn hình active cuối cùng phải bị khóa (SafetyGuard sẽ chặn,
    /// nhưng khóa từ UI để người dùng hiểu ngay).
    func isLastActive(_ row: Row) -> Bool {
        row.info.isEnabled && !rows.contains { $0.info.isEnabled && $0.id != row.id }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "Không đặt được khởi động cùng máy: \(error.localizedDescription)"
            isSyncingLaunchToggle = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isSyncingLaunchToggle = false
        }
    }
}
