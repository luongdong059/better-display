import CoreGraphics
import Foundation

/// Một lựa chọn kích thước (đã gộp các mode trùng WxH, ưu tiên HiDPI
/// rồi tần số quét gần với hiện tại).
public struct DisplaySizeChoice: Identifiable, Equatable {
    public let width: Int
    public let height: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    public let isCurrent: Bool
    public let mode: CGDisplayMode

    public var id: String { "\(width)x\(height)" }
    public var label: String { "\(width)×\(height)" }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Liệt kê và thay đổi display mode — toàn public API.
public enum DisplayModeControl {
    public static func currentMode(for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        CGDisplayCopyDisplayMode(displayID)
    }

    public static func allModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] ?? []
        return modes.filter { $0.isUsableForDesktopGUI() }
    }

    /// Danh sách kích thước cho slider: mỗi WxH một mục, sắp theo diện tích tăng dần.
    public static func sizeChoices(for displayID: CGDirectDisplayID) -> [DisplaySizeChoice] {
        let current = currentMode(for: displayID)
        var bySize: [String: CGDisplayMode] = [:]
        for mode in allModes(for: displayID) {
            let key = "\(mode.width)x\(mode.height)"
            if let existing = bySize[key] {
                if isBetter(mode, than: existing, current: current) { bySize[key] = mode }
            } else {
                bySize[key] = mode
            }
        }
        return bySize.values
            .map { mode in
                DisplaySizeChoice(
                    width: mode.width,
                    height: mode.height,
                    refreshRate: mode.refreshRate,
                    isHiDPI: mode.pixelWidth > mode.width,
                    isCurrent: current.map { mode.width == $0.width && mode.height == $0.height } ?? false,
                    mode: mode)
            }
            .sorted { $0.width * $0.height < $1.width * $1.height }
    }

    /// Ưu tiên: HiDPI trước, rồi tần số quét gần mode hiện tại nhất.
    private static func isBetter(_ a: CGDisplayMode, than b: CGDisplayMode, current: CGDisplayMode?) -> Bool {
        let aHiDPI = a.pixelWidth > a.width, bHiDPI = b.pixelWidth > b.width
        if aHiDPI != bHiDPI { return aHiDPI }
        let target = current?.refreshRate ?? 60
        return abs(a.refreshRate - target) < abs(b.refreshRate - target)
    }

    public static func set(_ mode: CGDisplayMode, for displayID: CGDirectDisplayID) throws {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            throw PowerControlError.configurationFailed("mở transaction cấu hình", code: begin.rawValue)
        }
        let err = CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            throw PowerControlError.configurationFailed("đặt display mode", code: err.rawValue)
        }
        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        guard complete == .success else {
            throw PowerControlError.configurationFailed("hoàn tất cấu hình", code: complete.rawValue)
        }
    }

    public static func setResolution(
        width: Int, height: Int, refreshRate: Double? = nil, for displayID: CGDirectDisplayID
    ) throws {
        if let refreshRate {
            // Chỉ định tần số tường minh: chọn mode WxH có tần số gần nhất.
            let candidates = allModes(for: displayID)
                .filter { $0.width == width && $0.height == height }
            guard let mode = candidates.min(by: {
                abs($0.refreshRate - refreshRate) < abs($1.refreshRate - refreshRate)
            }) else {
                throw PowerControlError.configurationFailed(
                    "màn hình không có mode \(width)x\(height) (xem `displayctl modes`)", code: 0)
            }
            try set(mode, for: displayID)
            return
        }
        guard let choice = sizeChoices(for: displayID)
            .first(where: { $0.width == width && $0.height == height }) else {
            throw PowerControlError.configurationFailed(
                "màn hình không có mode \(width)x\(height) (xem `displayctl modes`)", code: 0)
        }
        try set(choice.mode, for: displayID)
    }
}
