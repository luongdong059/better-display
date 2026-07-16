import CoreGraphics
import Foundation

/// Bật/tắt mirror — public API, dùng chung bởi MirrorStrategy và UI Phase 6.
public enum MirrorControl {
    /// Màn hình mà `displayID` đang mirror theo (master), nil nếu không mirror.
    public static func master(of displayID: CGDirectDisplayID) -> CGDirectDisplayID? {
        let master = CGDisplayMirrorsDisplay(displayID)
        return master == kCGNullDirectDisplay ? nil : master
    }

    /// master = nil → thoát mirror.
    public static func setMirror(_ displayID: CGDirectDisplayID, of master: CGDirectDisplayID?) throws {
        guard displayID != master else {
            throw PowerControlError.configurationFailed("không thể mirror màn hình vào chính nó", code: 0)
        }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            throw PowerControlError.configurationFailed("mở transaction cấu hình", code: begin.rawValue)
        }
        let err = CGConfigureDisplayMirrorOfDisplay(config, displayID, master ?? kCGNullDirectDisplay)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            throw PowerControlError.configurationFailed("đặt mirror", code: err.rawValue)
        }
        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        guard complete == .success else {
            throw PowerControlError.configurationFailed("hoàn tất cấu hình", code: complete.rawValue)
        }
    }
}
