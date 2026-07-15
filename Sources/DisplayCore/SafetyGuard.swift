import Foundation

/// Luật an toàn bắt buộc trước mọi lệnh tắt màn hình.
public enum SafetyGuard {
    /// Chặn tắt màn hình đang hoạt động cuối cùng.
    public static func validateTurnOff(target: DisplayInfo, all: [DisplayInfo]) throws {
        guard target.isEnabled else { return }
        let remaining = all.filter { $0.id != target.id && $0.isEnabled }
        if remaining.isEmpty {
            throw PowerControlError.wouldDisableLastDisplay(target.name)
        }
    }
}
