import Foundation

/// Shared loyalty wording. Keys are literals so LocalizationTests can see them.
enum LoyaltyCopy {
    /// "1 point" / "25 points".
    static func points(_ count: Int) -> String {
        if count == 1 {
            return AppLocalization.localized("loyalty.points.one", value: "1 point")
        }
        return String(format: AppLocalization.localized("loyalty.points_fmt", value: "%d points"), count)
    }
}
