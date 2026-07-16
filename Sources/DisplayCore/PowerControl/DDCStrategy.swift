import CoreGraphics
import Foundation

/// Chiến lược B — tắt nguồn màn hình ngoài thật sự qua DDC/CI (VCP 0xD6,
/// power mode): 0x01 = bật, 0x04 = standby. Chỉ chạy khi người dùng chọn
/// tường minh (không nằm trong chuỗi fallback mặc định) vì một số màn hình
/// vào standby xong không đánh thức được bằng DDC — phải bấm nút nguồn.
public struct DDCStrategy: PowerControlStrategy {
    public let kind: StrategyKind = .ddc

    static let powerModeVCP: UInt8 = 0xD6
    static let powerOn: UInt16 = 0x01
    static let standby: UInt16 = 0x04

    public init() {}

    /// Khả dụng = tìm được kênh DDC. KHÔNG thử đọc VCP ở đây: màn hình đang
    /// standby không trả lời lệnh đọc nhưng vẫn có thể nhận lệnh ghi wake.
    public func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(displayID) == 0 && IOAVServiceDDC.isAvailable
            && IOAVServiceDDC.avService(for: displayID) != nil
    }

    /// Phép thử đầy đủ cho cột "DDC" trong list: màn hình phải trả lời được
    /// lệnh đọc VCP power mode.
    public func probeSupport(for displayID: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(displayID) == 0, IOAVServiceDDC.isAvailable,
              let service = IOAVServiceDDC.avService(for: displayID)
        else { return false }
        return IOAVServiceDDC.readVCP(service, code: Self.powerModeVCP) != nil
    }

    public func turnOff(_ displayID: CGDirectDisplayID) throws {
        try setPowerMode(displayID, Self.standby)
    }

    public func turnOn(_ displayID: CGDirectDisplayID) throws {
        try setPowerMode(displayID, Self.powerOn)
    }

    private func setPowerMode(_ displayID: CGDirectDisplayID, _ value: UInt16) throws {
        guard IOAVServiceDDC.isAvailable else {
            throw PowerControlError.strategyUnavailable(.ddc, reason: "IOAVService API không tồn tại")
        }
        guard let service = IOAVServiceDDC.avService(for: displayID) else {
            throw PowerControlError.strategyUnavailable(.ddc, reason: "không tìm thấy kênh DDC cho màn hình này")
        }
        guard IOAVServiceDDC.writeVCP(service, code: Self.powerModeVCP, value: value) else {
            throw PowerControlError.operationFailed(.ddc, code: -1)
        }
    }
}
