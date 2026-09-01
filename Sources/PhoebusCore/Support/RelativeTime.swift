import Foundation

/// Apollo's compact single-unit relative-time convention for post/comment
/// timestamps (e.g. "2h", "5h", "3d", "just now"), rather than SwiftUI's
/// multi-unit `Text(date, style: .relative)`, which wraps and breaks the
/// tight feed row layout.
extension Date {
    public var apolloRelativeTime: String {
        let seconds = -timeIntervalSinceNow
        guard seconds >= 0 else { return "now" }
        switch seconds {
        case ..<60:
            return "now"
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
