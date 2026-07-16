import CoreGraphics
import Foundation

public enum StrategyKind: String, Codable, CaseIterable {
    /// macOS coi màn hình như đã rút cáp (SkyLight, private API).
    case disconnect
    /// Tắt nguồn màn hình ngoài qua DDC/CI — Phase 3, chưa triển khai.
    case ddc
    /// Màn hình chỉ mirror màn hình chính (public API, màn hình vẫn sáng).
    case mirror
    /// Kéo gamma về đen (public API, chỉ tồn tại khi tiến trình còn sống).
    case gamma
}

public protocol PowerControlStrategy {
    var kind: StrategyKind { get }
    func isAvailable(for displayID: CGDirectDisplayID) -> Bool
    func turnOff(_ displayID: CGDirectDisplayID) throws
    func turnOn(_ displayID: CGDirectDisplayID) throws
}

public enum PowerControlError: LocalizedError, Equatable {
    case displayNotFound(CGDirectDisplayID)
    case wouldDisableLastDisplay(String)
    case strategyUnavailable(StrategyKind, reason: String)
    case operationFailed(StrategyKind, code: Int32)
    case noStrategyAvailable
    case configurationFailed(String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .displayNotFound(let id):
            return "Không tìm thấy màn hình có ID \(id)."
        case .wouldDisableLastDisplay(let name):
            return "Bị chặn vì an toàn: \"\(name)\" là màn hình đang hoạt động cuối cùng. Tắt nó sẽ khiến bạn không nhìn thấy gì."
        case .strategyUnavailable(let kind, let reason):
            return "Chiến lược \(kind.rawValue) không khả dụng: \(reason)"
        case .operationFailed(let kind, let code):
            return "Chiến lược \(kind.rawValue) thất bại (mã lỗi \(code))."
        case .noStrategyAvailable:
            return "Không có chiến lược bật/tắt nào khả dụng cho màn hình này."
        case .configurationFailed(let what, let code):
            return "Thao tác thất bại: \(what)" + (code != 0 ? " (mã lỗi \(code))" : "")
        }
    }
}
