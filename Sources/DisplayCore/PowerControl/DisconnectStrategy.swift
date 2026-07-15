import CoreGraphics
import Foundation

/// Chiến lược A — macOS coi màn hình như đã rút cáp. Cửa sổ dồn về màn hình còn lại.
public struct DisconnectStrategy: PowerControlStrategy {
    public let kind: StrategyKind = .disconnect

    public init() {}

    public func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        SkyLight.isAvailable
    }

    public func turnOff(_ displayID: CGDirectDisplayID) throws {
        try setEnabled(displayID, false)
    }

    public func turnOn(_ displayID: CGDirectDisplayID) throws {
        try setEnabled(displayID, true)
    }

    private func setEnabled(_ displayID: CGDirectDisplayID, _ enabled: Bool) throws {
        guard let code = SkyLight.setDisplayEnabled(displayID, enabled) else {
            throw PowerControlError.strategyUnavailable(
                .disconnect, reason: "SkyLight API không tồn tại trên bản macOS này")
        }
        guard code == 0 else {
            throw PowerControlError.operationFailed(.disconnect, code: code)
        }
    }
}
