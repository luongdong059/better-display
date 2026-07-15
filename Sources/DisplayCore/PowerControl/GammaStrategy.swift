import CoreGraphics
import Foundation

/// Chiến lược D (fallback cuối) — kéo gamma về đen. Màn hình vẫn bật đèn nền.
/// Gamma do window server gắn với tiến trình gọi: tiến trình thoát là tự reset,
/// nên chiến lược này chỉ có ý nghĩa với GUI giữ tiến trình sống, không bền qua CLI.
public struct GammaStrategy: PowerControlStrategy {
    public let kind: StrategyKind = .gamma

    public init() {}

    public func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        true
    }

    public func turnOff(_ displayID: CGDirectDisplayID) throws {
        let code = CGSetDisplayTransferByFormula(displayID, 0, 0, 1, 0, 0, 1, 0, 0, 1)
        guard code == .success else {
            throw PowerControlError.operationFailed(.gamma, code: code.rawValue)
        }
    }

    public func turnOn(_ displayID: CGDirectDisplayID) throws {
        // Reset toàn cục về cấu hình ColorSync — vô hại với các màn hình khác.
        CGDisplayRestoreColorSyncSettings()
    }
}
