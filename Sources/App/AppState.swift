import AppKit
import CoreGraphics
import DisplayCore
import ServiceManagement
import Sparkle
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

    /// Sparkle — chỉ khởi động khi chạy từ bundle có khai báo SUFeedURL
    /// (chạy binary trần lúc dev thì không có, tránh Sparkle báo lỗi).
    private let updaterController: SPUStandardUpdaterController? =
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil

    var canCheckForUpdates: Bool { updaterController != nil }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    init() {
        let store = StateStore()
        self.store = store
        self.manager = DisplayManager(store: store)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        if let raw = UserDefaults.standard.dictionary(forKey: Self.preferencesKey) as? [String: String] {
            self.preferredStrategies = raw.compactMapValues(StrategyKind.init(rawValue:))
        }
        refresh()
        monitor.onChange = { [weak self] in
            // Cắm/rút cáp có thể đổi proxy DDC — xóa cache để dò lại.
            BrightnessControl.invalidateCache()
            self?.refresh()
        }
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

    // MARK: - Phase 6: độ sáng

    struct BrightnessState {
        var percent: Double
        var maxValue: UInt16
    }

    @Published var brightnessStates: [CGDirectDisplayID: BrightnessState] = [:]
    private var brightnessPending: [CGDirectDisplayID: DispatchWorkItem] = [:]

    /// Đọc độ sáng khi mở khu điều khiển — chạy nền vì DDC chậm (~50-100ms).
    func loadBrightness(for row: Row) {
        let id = row.info.id
        guard row.info.supportsDDC, brightnessStates[id] == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = BrightnessControl.brightness(for: id)
            DispatchQueue.main.async {
                guard let self, let result else { return }
                self.brightnessStates[id] = BrightnessState(
                    percent: Double(result.current) / Double(max(result.max, 1)) * 100,
                    maxValue: result.max)
            }
        }
    }

    /// Cập nhật UI ngay, ghi DDC trễ 150ms (gộp các lần kéo slider liên tiếp).
    func setBrightness(percent: Double, for row: Row) {
        let id = row.info.id
        guard var state = brightnessStates[id] else { return }
        state.percent = percent
        brightnessStates[id] = state

        brightnessPending[id]?.cancel()
        let maxValue = state.maxValue
        let item = DispatchWorkItem {
            let raw = UInt16((percent / 100 * Double(maxValue)).rounded())
            DispatchQueue.global(qos: .userInitiated).async {
                try? BrightnessControl.setBrightness(raw, for: id)
            }
        }
        brightnessPending[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    // MARK: - Phase 6: kích thước (kèm đếm ngược hoàn tác)

    struct PendingRevert {
        let displayID: CGDirectDisplayID
        let displayName: String
        let previousMode: CGDisplayMode
        var seconds: Int
    }

    @Published var pendingRevert: PendingRevert?
    private var revertTimer: Timer?

    func sizeChoices(for row: Row) -> [DisplaySizeChoice] {
        DisplayModeControl.sizeChoices(for: row.info.id)
    }

    func applySize(_ choice: DisplaySizeChoice, for row: Row) {
        guard let previous = DisplayModeControl.currentMode(for: row.info.id) else { return }
        do {
            try DisplayModeControl.set(choice.mode, for: row.info.id)
            startRevertCountdown(for: row, previous: previous)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    private func startRevertCountdown(for row: Row, previous: CGDisplayMode) {
        revertTimer?.invalidate()
        pendingRevert = PendingRevert(
            displayID: row.info.id, displayName: row.info.name,
            previousMode: previous, seconds: 10)
        revertTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, var pending = self.pendingRevert else { return }
            pending.seconds -= 1
            if pending.seconds <= 0 {
                self.revertModeChange()
            } else {
                self.pendingRevert = pending
            }
        }
    }

    func confirmModeChange() {
        revertTimer?.invalidate()
        revertTimer = nil
        pendingRevert = nil
    }

    func revertModeChange() {
        if let pending = pendingRevert {
            try? DisplayModeControl.set(pending.previousMode, for: pending.displayID)
        }
        confirmModeChange()
        refresh()
    }

    // MARK: - Phase 6: xoay màn hình

    func rotation(for row: Row) -> Int {
        RotationControl.rotation(for: row.info.id)
    }

    func setRotation(_ degrees: Int, for row: Row) {
        do {
            try RotationControl.setRotation(degrees, for: row.info.id)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    // MARK: - Phase 6: mirror

    func mirrorMaster(for row: Row) -> CGDirectDisplayID {
        MirrorControl.master(of: row.info.id) ?? 0
    }

    /// Các màn hình có thể làm master cho row này.
    func mirrorCandidates(for row: Row) -> [Row] {
        rows.filter { $0.id != row.id && $0.info.isEnabled && !$0.isGhost }
    }

    func setMirror(master: CGDirectDisplayID, for row: Row) {
        do {
            try MirrorControl.setMirror(row.info.id, of: master == 0 ? nil : master)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
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
