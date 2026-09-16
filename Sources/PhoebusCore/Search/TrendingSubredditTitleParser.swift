import Foundation

/// Parses Reddit's daily r/trendingsubreddits announcement post title
/// into a list of subreddit names. Reddit's own bot posts titles of
/// the form "Your daily trending subreddits | r/aww, r/cats, r/pics"
/// (comma-separated `r/name` mentions after a separator). Reddit has no
/// trending-subreddits JSON endpoint, so this is how Apollo and other
/// clients get the list. Pure string logic, testable without network access.
public enum TrendingSubredditTitleParser {
    public static func parseSubredditNames(fromTitle title: String) -> [String] {
        // Match "r/name" tokens (letters, digits, underscore), which is robust to
        // whatever separator/punctuation surrounds the list without modelling
        // Reddit's exact wording, which varies.
        let pattern = #"r/([A-Za-z0-9_]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(title.startIndex..., in: title)
        let matches = regex.matches(in: title, range: range)
        var seen = Set<String>()
        var names: [String] = []
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: title) else { continue }
            let name = String(title[nameRange])
            // Skip a self-reference to r/trendingsubreddits, which some title
            // formats include.
            guard name.caseInsensitiveCompare("trendingsubreddits") != .orderedSame else { continue }
            if seen.insert(name.lowercased()).inserted {
                names.append(name)
            }
        }
        return names
    }
}
