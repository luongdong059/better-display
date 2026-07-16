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
        try MirrorControl.setMirror(displayID, of: CGMainDisplayID())
    }

    public func turnOn(_ displayID: CGDirectDisplayID) throws {
        try MirrorControl.setMirror(displayID, of: nil)
    }
}
