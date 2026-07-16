import Foundation

/// Nguồn version duy nhất cho CLI. App đọc từ Info.plist của bundle;
/// scripts/release.sh cập nhật cả hai chỗ cùng lúc khi phát hành.
public enum BetterDisplayVersion {
    public static let current = "0.6.0"
}
