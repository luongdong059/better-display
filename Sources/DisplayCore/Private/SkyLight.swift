import CoreGraphics
import Darwin

/// Nạp private API từ SkyLight.framework lúc runtime bằng dlopen/dlsym.
/// Nếu bản macOS mới bỏ symbol, các thuộc tính trả về nil và DisconnectStrategy
/// tự báo "không khả dụng" để DisplayManager chuyển sang fallback — không crash.
enum SkyLight {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias ConfigureDisplayEnabledFn = @convention(c) (Int32, CGDirectDisplayID, Bool) -> Int32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let mainConnectionID =
        symbol("SLSMainConnectionID", as: MainConnectionIDFn.self)
    private static let configureDisplayEnabled =
        symbol("SLSConfigureDisplayEnabled", as: ConfigureDisplayEnabledFn.self)

    static var isAvailable: Bool {
        mainConnectionID != nil && configureDisplayEnabled != nil
    }

    /// Trả về mã lỗi của window server (0 = thành công), hoặc nil nếu API không tồn tại.
    static func setDisplayEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> Int32? {
        guard let mainConnectionID, let configureDisplayEnabled else { return nil }
        return configureDisplayEnabled(mainConnectionID(), id, enabled)
    }
}
