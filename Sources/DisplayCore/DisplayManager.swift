import AppKit
import CoreGraphics
import Foundation

/// Cửa ngõ chính của DisplayCore: liệt kê màn hình và điều phối bật/tắt.
public final class DisplayManager {
    private let store: StateStore
    private let strategies: [PowerControlStrategy]

    public init(store: StateStore = StateStore()) {
        self.store = store
        // DDC không nằm trong chuỗi fallback mặc định (chỉ chạy khi chọn tường
        // minh) vì một số màn hình standby xong không đánh thức được bằng DDC.
        self.strategies = [DisconnectStrategy(), DDCStrategy(), MirrorStrategy(), GammaStrategy()]
    }

    // MARK: - Liệt kê

    public func allDisplays() -> [DisplayInfo] {
        let online = Self.displayIDs(online: true)
        let active = Set(Self.displayIDs(online: false))
        let ddc = DDCStrategy()
        return online.map { id in
            // Màn hình tắt bằng DDC/gamma vẫn active với CoreGraphics —
            // record trong StateStore mới là trạng thái "đang tắt" thực tế.
            let disabledByUs = store.disabledRecord(for: id) != nil
            return DisplayInfo(
                id: id,
                persistentKey: Self.persistentKey(for: id),
                name: Self.name(for: id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                resolution: CGSize(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id)),
                refreshRate: CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0,
                isEnabled: active.contains(id) && !disabledByUs,
                isMirrored: CGDisplayIsInMirrorSet(id) != 0,
                supportsDDC: ddc.probeSupport(for: id)
            )
        }
    }

    static func displayIDs(online: Bool) -> [CGDirectDisplayID] {
        let counter = online ? CGGetOnlineDisplayList : CGGetActiveDisplayList
        var count: UInt32 = 0
        guard counter(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard counter(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    public static func persistentKey(vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        "v\(vendor)-m\(model)-s\(serial)"
    }

    static func persistentKey(for id: CGDirectDisplayID) -> String {
        persistentKey(
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id))
    }

    static func name(for id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               number.uint32Value == id {
                return screen.localizedName
            }
        }
        return CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display \(id)"
    }

    // MARK: - Bật/tắt

    /// Bật/tắt một màn hình. Trả về chiến lược thực sự được dùng.
    /// `preferred == nil`: thử theo chuỗi fallback Disconnect → Mirror → Gamma.
    /// `preferred != nil`: chỉ dùng đúng chiến lược đó, không fallback.
    @discardableResult
    public func setPower(_ on: Bool, displayID: CGDirectDisplayID, preferred: StrategyKind? = nil) throws -> StrategyKind {
        on ? try turnOn(displayID: displayID, preferred: preferred)
           : try turnOff(displayID: displayID, preferred: preferred)
    }

    private func turnOff(displayID: CGDirectDisplayID, preferred: StrategyKind?) throws -> StrategyKind {
        let displays = allDisplays()
        guard let target = displays.first(where: { $0.id == displayID }) else {
            throw PowerControlError.displayNotFound(displayID)
        }
        try SafetyGuard.validateTurnOff(target: target, all: displays)

        var lastError: Error = PowerControlError.noStrategyAvailable
        for strategy in try chain(preferred: preferred) {
            guard strategy.isAvailable(for: displayID) else { continue }
            // Ghi ý định TRƯỚC khi thực thi — crash giữa chừng thì restore vẫn biết đường bật lại.
            store.recordDisabled(DisabledRecord(
                displayID: displayID,
                persistentKey: target.persistentKey,
                strategy: strategy.kind,
                date: Date(),
                name: target.name))
            do {
                try strategy.turnOff(displayID)
                return strategy.kind
            } catch {
                store.removeDisabled(displayID: displayID)
                lastError = error
            }
        }
        throw lastError
    }

    private func turnOn(displayID: CGDirectDisplayID, preferred: StrategyKind?) throws -> StrategyKind {
        let recorded = store.disabledRecord(for: displayID)
        var lastError: Error = PowerControlError.noStrategyAvailable
        for strategy in try chain(preferred: preferred ?? recorded?.strategy) {
            guard strategy.isAvailable(for: displayID) else { continue }
            do {
                try strategy.turnOn(displayID)
                store.removeDisabled(displayID: displayID)
                return strategy.kind
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Các màn hình đang được ghi nhận là đã tắt (cho UI hiển thị cả màn hình
    /// đã disconnect — chúng không còn xuất hiện trong `allDisplays()`).
    public func disabledRecords() -> [DisabledRecord] {
        store.allDisabled()
    }

    /// Bật lại mọi màn hình từng được ghi nhận là đã tắt, và reset gamma toàn cục.
    /// Đây là lệnh cứu hộ — không bao giờ ném lỗi, trả về kết quả từng màn hình.
    public func restoreAll() -> [(displayID: CGDirectDisplayID, result: Result<StrategyKind, Error>)] {
        var results: [(CGDirectDisplayID, Result<StrategyKind, Error>)] = []
        for record in store.allDisabled() {
            do {
                let kind = try turnOn(displayID: record.displayID, preferred: record.strategy)
                results.append((record.displayID, .success(kind)))
            } catch {
                results.append((record.displayID, .failure(error)))
            }
        }
        CGDisplayRestoreColorSyncSettings()
        return results
    }

    private func chain(preferred: StrategyKind?) throws -> [PowerControlStrategy] {
        guard let preferred else { return strategies.filter { $0.kind != .ddc } }
        guard let strategy = strategies.first(where: { $0.kind == preferred }) else {
            throw PowerControlError.strategyUnavailable(preferred, reason: "chưa được triển khai")
        }
        return [strategy]
    }
}
