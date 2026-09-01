import Foundation

/// Reddit's abbreviated-count convention for score/comment counts (e.g.
/// "62.8K", "2.4K", "998"; below 1,000 unabbreviated).
extension Int {
    public var apolloAbbreviated: String {
        let value = Double(self)
        switch abs(self) {
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", value / 1_000)
        default:
            return "\(self)"
        }
    }
}

extension Int {
    /// "1 Comment", "2 Comments", "1.2K Comments": the abbreviated count
    /// with the noun agreeing with it.
    public func apolloCounted(_ singular: String, _ plural: String) -> String {
        "\(apolloAbbreviated) \(self == 1 ? singular : plural)"
    }
}

extension Int {
    /// A subreddit header's member count, as Reborn formats it: whole millions
    /// from 10M ("34M"), one decimal below ("2.5M"), the same for thousands with a
    /// lowercase "k" ("850k", "12.3k").
    public var apolloMemberCount: String {
        let n = Double(self)
        switch self {
        case 10_000_000...: return String(format: "%.0fM members", n / 1_000_000)
        case 1_000_000...: return String(format: "%.1fM members", n / 1_000_000)
        case 100_000...: return String(format: "%.0fk members", n / 1_000)
        case 1_000...: return String(format: "%.1fk members", n / 1_000)
        case 1: return "1 member"
        default: return "\(self) members"
        }
    }
}
