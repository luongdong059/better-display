import CoreGraphics
import Foundation

/// Chỉnh độ sáng màn hình ngoài qua DDC/CI — VCP 0x10 (Luminance).
/// Tái dùng kênh IOAVService của Phase 3, có cache service để slider kéo mượt.
public enum BrightnessControl {
    static let luminanceVCP: UInt8 = 0x10

    /// Đọc (giá trị hiện tại, giá trị tối đa). nil = không hỗ trợ/không trả lời.
    public static func brightness(for displayID: CGDirectDisplayID) -> (current: UInt16, max: UInt16)? {
        guard CGDisplayIsBuiltin(displayID) == 0,
              let service = IOAVServiceDDC.cachedService(for: displayID) else { return nil }
        return IOAVServiceDDC.readVCP(service, code: luminanceVCP)
    }

    public static func setBrightness(_ value: UInt16, for displayID: CGDirectDisplayID) throws {
        guard let service = IOAVServiceDDC.cachedService(for: displayID) else {
            throw PowerControlError.strategyUnavailable(.ddc, reason: "không tìm thấy kênh DDC cho màn hình này")
        }
        guard IOAVServiceDDC.writeVCP(service, code: luminanceVCP, value: value) else {
            // Ghi hỏng có thể do cache ôi (cắm lại cáp đổi proxy) — xóa để lần sau dò lại.
            IOAVServiceDDC.invalidateCache()
            throw PowerControlError.operationFailed(.ddc, code: -1)
        }
    }

    /// Gọi khi cấu hình màn hình thay đổi (cắm/rút cáp).
    public static func invalidateCache() {
        IOAVServiceDDC.invalidateCache()
    }
}
