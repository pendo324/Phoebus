import Foundation

/// Text formatting for the Share as Image card, matching Apollo's details
/// line:
///
///     in Aww by ███████
///     ↑ 57.0K  💬 365  🕐 7h  👥😀💲 345
///
/// The byline is "in <sub> by <user>", and the stats row carries the age
/// and the award count as well as score and comments.
public enum ShareCardFormatting {
    /// Abbreviated score, e.g. `57.0K` (the tenth is kept even when zero).
    public static func abbreviated(_ value: Int) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if magnitude >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    /// Compact age, e.g. `7h`.
    ///
    /// The card has one line for everything, so this is the short form
    /// ("7h"), not "7 hours ago".
    public static func compactAge(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = seconds / 60
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(Int(minutes))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours))h" }
        let days = hours / 24
        if days < 30 { return "\(Int(days))d" }
        let months = days / 30
        if months < 12 { return "\(Int(months))mo" }
        return "\(Int(months / 12))y"
    }

    /// The card's byline: `in <subreddit> by <author>`.
    ///
    /// The subreddit carries NO `r/` prefix on the card ("in Aww", not
    /// "in r/Aww"), and the author no `u/`.
    public static func byline(subreddit: String, author: String, hideUsername: Bool) -> String {
        hideUsername ? "in \(subreddit) by " : "in \(subreddit) by \(author)"
    }
}

extension ShareCardFormatting {
    /// The post body a share card can show, or nil when there is none.
    /// Lines that are only an image link are dropped, since the image
    /// itself is already on the card.
    public static func bodyText(of post: RedditPost) -> String? {
        guard let raw = post.selftext else { return nil }
        let text = removingImageOnlyLines(raw)
        return text.isEmpty ? nil : text
    }

    /// `text` without the lines that are only an image link (bare or
    /// markdown), since the card draws those images itself.
    public static func removingImageOnlyLines(_ text: String) -> String {
        let kept = text.components(separatedBy: "\n").filter { line in
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix(")"),
               let open = trimmed.range(of: "](") {
                trimmed = String(trimmed[open.upperBound..<trimmed.index(before: trimmed.endIndex)])
            }
            guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else { return true }
            return InlineMediaDetector.classify(url) == nil
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
