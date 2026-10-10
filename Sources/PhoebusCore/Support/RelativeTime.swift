import Foundation

/// Apollo's compact single-unit relative-time convention for post/comment
/// timestamps (e.g. "2h", "5h", "3d", "just now"), rather than SwiftUI's
/// multi-unit `Text(date, style: .relative)`, which wraps and breaks the
/// tight feed row layout.
extension Date {
    public var apolloRelativeTime: String {
        let seconds = -timeIntervalSinceNow
        guard seconds >= 60 else { return "now" }
        return Self.apolloCompactDuration(seconds)
    }

    /// The single-unit duration behind `apolloRelativeTime` ("45s", "3m",
    /// "2h", "4d", "1mo", "2y"); negative intervals read as "0s".
    public static func apolloCompactDuration(_ seconds: TimeInterval) -> String {
        switch max(seconds, 0) {
        case ..<60:
            return "\(Int(max(seconds, 0)))s"
        case ..<3600:
            return "\(Int(seconds / 60))m"
        case ..<86400:
            return "\(Int(seconds / 3600))h"
        case ..<(86400 * 30):
            return "\(Int(seconds / 86400))d"
        case ..<(86400 * 365):
            return "\(Int(seconds / (86400 * 30)))mo"
        default:
            return "\(Int(seconds / (86400 * 365)))y"
        }
    }
}
