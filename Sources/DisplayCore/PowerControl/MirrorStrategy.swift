import CoreGraphics
import Foundation

/// Chiến lược C (fallback) — cho màn hình mirror màn hình chính, "tắt" về mặt logic.
/// Chỉ dùng public API nên bền qua các bản macOS, nhưng màn hình vẫn sáng.
public struct MirrorStrategy: PowerControlStrategy {
    public let kind: StrategyKind = .mirror

    public init() {}

    public func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        displayID != CGMainDisplayID()
    }

    public func turnOff(_ displayID: CGDirectDisplayID) throws {
        try configureMirror(displayID, master: CGMainDisplayID())
    }

    public func turnOn(_ displayID: CGDirectDisplayID) throws {
        try configureMirror(displayID, master: kCGNullDirectDisplay)
    }

    private func configureMirror(_ displayID: CGDirectDisplayID, master: CGDirectDisplayID) throws {
        guard displayID != master else {
            throw PowerControlError.strategyUnavailable(
                .mirror, reason: "không thể mirror màn hình chính vào chính nó")
        }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            throw PowerControlError.operationFailed(.mirror, code: begin.rawValue)
        }
        let mirror = CGConfigureDisplayMirrorOfDisplay(config, displayID, master)
        guard mirror == .success else {
            CGCancelDisplayConfiguration(config)
            throw PowerControlError.operationFailed(.mirror, code: mirror.rawValue)
        }
        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        guard complete == .success else {
            throw PowerControlError.operationFailed(.mirror, code: complete.rawValue)
        }
    }
}
