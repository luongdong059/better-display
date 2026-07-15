import CoreGraphics
import Foundation

/// Thông tin một màn hình tại một thời điểm.
public struct DisplayInfo: Identifiable, Codable, Equatable {
    /// ID phiên làm việc của window server — có thể đổi sau khi cắm lại/khởi động.
    public let id: CGDirectDisplayID
    /// Khóa bền vững theo vendor/model/serial — dùng để nhận ra cùng một màn hình
    /// qua các lần cắm/rút. Mọi cấu hình lưu trữ phải khóa theo key này, không theo `id`.
    public let persistentKey: String
    public let name: String
    public let isBuiltin: Bool
    public let isMain: Bool
    public let resolution: CGSize
    public let refreshRate: Double
    /// Màn hình có đang active (được vẽ lên) hay không.
    public let isEnabled: Bool
    public let isMirrored: Bool

    public init(
        id: CGDirectDisplayID,
        persistentKey: String,
        name: String,
        isBuiltin: Bool,
        isMain: Bool,
        resolution: CGSize,
        refreshRate: Double,
        isEnabled: Bool,
        isMirrored: Bool
    ) {
        self.id = id
        self.persistentKey = persistentKey
        self.name = name
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.isEnabled = isEnabled
        self.isMirrored = isMirrored
    }
}
