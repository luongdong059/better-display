import CoreGraphics
import Darwin

/// Nạp private API từ SkyLight.framework lúc runtime bằng dlopen/dlsym.
/// Nếu bản macOS mới bỏ symbol, các thuộc tính trả về nil và DisconnectStrategy
/// tự báo "không khả dụng" để DisplayManager chuyển sang fallback — không crash.
enum SkyLight {
    /// Chữ ký thật (xác nhận từ crash `checkCapacity(CGSConfigData*)` trên macOS 26
    /// + cách dùng của displayplacer): tham số đầu là CGDisplayConfigRef của một
    /// transaction đang mở, KHÔNG phải connection ID.
    private typealias ConfigureDisplayEnabledFn =
        @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> Int32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let configureDisplayEnabled =
        symbol("SLSConfigureDisplayEnabled", as: ConfigureDisplayEnabledFn.self)

    static var isAvailable: Bool {
        configureDisplayEnabled != nil
    }

    /// Bọc lệnh enable/disable trong một transaction cấu hình màn hình.
    /// Trả về mã lỗi (0 = thành công), hoặc nil nếu API không tồn tại.
    static func setDisplayEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> Int32? {
        guard let configureDisplayEnabled else { return nil }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { return begin.rawValue }
        let result = configureDisplayEnabled(config, id, enabled)
        guard result == 0 else {
            CGCancelDisplayConfiguration(config)
            return result
        }
        return CGCompleteDisplayConfiguration(config, .permanently).rawValue
    }
}
