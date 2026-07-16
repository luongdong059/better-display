import CoreGraphics
import Foundation

/// Xoay màn hình qua framework private MonitorPanel (MPDisplayMgr/MPDisplay,
/// ObjC). Chọn đường ObjC thay vì C API SLSSetDisplayRotation vì introspect
/// được selector trước khi gọi — sai tên chỉ trả lỗi, không corrupt stack.
public enum RotationControl {
    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW)

    public static var isAvailable: Bool {
        handle != nil && NSClassFromString("MPDisplayMgr") != nil
    }

    /// Góc xoay hiện tại (0/90/180/270) — public API, luôn dùng được.
    public static func rotation(for displayID: CGDirectDisplayID) -> Int {
        Int(CGDisplayRotation(displayID).rounded())
    }

    public static func setRotation(_ degrees: Int, for displayID: CGDirectDisplayID) throws {
        guard [0, 90, 180, 270].contains(degrees) else {
            throw PowerControlError.configurationFailed("góc xoay phải là 0/90/180/270", code: 0)
        }
        guard let display = mpDisplay(for: displayID) else {
            throw PowerControlError.configurationFailed(
                "không tìm thấy màn hình trong MonitorPanel (API private có thể đã đổi)", code: 0)
        }
        guard display.responds(to: Selector(("setOrientation:"))) else {
            throw PowerControlError.configurationFailed(
                "MPDisplay không còn selector setOrientation: trên bản macOS này", code: 0)
        }
        // KVC gọi setOrientation: — orientation là NSInteger.
        display.setValue(degrees, forKey: "orientation")
    }

    /// Tìm MPDisplay theo CGDirectDisplayID qua MPDisplayMgr.displays.
    private static func mpDisplay(for displayID: CGDirectDisplayID) -> NSObject? {
        // `handle` là lazy static — phải chạm vào để MonitorPanel thực sự được
        // dlopen trước khi NSClassFromString tra tên class.
        guard handle != nil,
              let mgrClass = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return nil }
        let mgr = mgrClass.init()
        guard mgr.responds(to: Selector(("displays"))),
              let displays = mgr.value(forKey: "displays") as? [NSObject] else { return nil }
        return displays.first {
            guard $0.responds(to: Selector(("displayID"))),
                  let id = $0.value(forKey: "displayID") as? NSNumber else { return false }
            return id.uint32Value == displayID
        }
    }
}
