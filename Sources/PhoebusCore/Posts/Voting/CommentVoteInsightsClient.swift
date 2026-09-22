import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Author-only comment vote insights (Apollo-Reborn's vote insights).
///
/// Reddit does not expose a comment's upvote ratio through the legacy
/// OAuth comment model; the only source is Reddit's own
/// server-rendered `commentstats/t1_<id>` page, visible only to the
/// comment's author.
public struct CommentVoteInsight: Sendable, Equatable {
    /// Upvote ratio as a percentage. `nil` when Reddit omitted the
    /// ratio but still supplied an upvote count.
    public let upvotePercent: Double?
    /// Explicit upvotes reported by Insights. This and Apollo's
    /// separately fetched, fuzzed score can disagree. `nil` when omitted.
    public let reportedUpvotes: Int?
    /// True when Reddit abbreviated the label, e.g. "1.2k upvotes".
    public let reportedUpvotesAreAbbreviated: Bool

    public init(upvotePercent: Double?, reportedUpvotes: Int?, reportedUpvotesAreAbbreviated: Bool) {
        self.upvotePercent = upvotePercent
        self.reportedUpvotes = reportedUpvotes
        self.reportedUpvotesAreAbbreviated = reportedUpvotesAreAbbreviated
    }
}

public enum CommentVoteInsightsClient {
    /// What a stats-page load actually produced. A single optional
    /// would collapse every failure, so a page that never rendered
    /// needs its own outcome distinct from a genuine "no vote details"
    /// case: Reddit answers HTTP 200 with a JS bot-check interstitial
    /// with no comment markup at all.
    public enum Outcome: Sendable, Equatable {
        case insight(CommentVoteInsight)
        /// The stats page rendered, but carried no vote labels.
        case notReported
        /// Reddit rendered the page and explicitly said Insights are
        /// unavailable, carrying its own reason (e.g. "Comment
        /// insights are only available for 90 days").
        case unavailable(reason: String)
        /// Reddit answered with a bot-check/login interstitial instead
        /// of the stats page. Retryable, and NOT a statement about the
        /// comment's votes.
        case blocked
    }

    /// Reddit's explicit "Insights unavailable" state, with its own
    /// explanatory line when present.
    public static func unavailableReason(html: String) -> String? {
        guard let main = firstCapture(html, #"(?s)<main\b[^>]*>(.*?)</main>"#) else { return nil }
        let text = plainText(main)
        guard text.range(of: "insights unavailable", options: .caseInsensitive) != nil
                || text.range(of: "insights aren.t available", options: [.caseInsensitive, .regularExpression]) != nil
        else { return nil }
        // Prefer Reddit's secondary explanation ("only available for 90
        // days"), which is the part that actually tells the user why.
        if let detail = firstCapture(main, #"(?s)<span[^>]*text-16[^>]*>(.*?)</span>"#) {
            let detailText = plainText(detail)
            if !detailText.isEmpty { return detailText }
        }
        return text
    }

    /// Strips tags and collapses whitespace/entities in a markup slice.
    static func plainText(_ markup: String) -> String {
        var text = markup.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, replacement) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the response is Reddit's bot-check interstitial
    /// rather than the stats page.
    public static func isChallengePage(_ html: String) -> Bool {
        let lowered = html.lowercased()
        // Bail on the real page's own routing marker, not "upvote",
        // which every page contains via a CSS variable. The
        // interstitial (a bare self-submitting "solution" form) does
        // not carry the marker.
        if lowered.contains("pagetype=\"comment_insights\"") { return false }
        return lowered.contains("requestsubmit()")
            || lowered.contains("nameditem(\"solution\")")
    }
    /// Stats page endpoint.
    public static func statsURL(commentID: String) -> URL? {
        let id = commentID.hasPrefix("t1_") ? commentID : "t1_" + commentID
        return URL(string: "https://www.reddit.com/commentstats/" + id)
    }

    /// Eligibility: the viewer must be the comment's author, and the thing
    /// must be a comment. Deliberately does not require a stored web session,
    /// so an attempted load can explain how to sign in rather than silently
    /// doing nothing.
    public static func isEligible(fullname: String?, author: String?, currentUsername: String?) -> Bool {
        guard let fullname, fullname.hasPrefix("t1_") else { return false }
        guard let author, let currentUsername, !author.isEmpty, !currentUsername.isEmpty else { return false }
        return author.caseInsensitiveCompare(currentUsername) == .orderedSame
    }

    // Regexes follow Reborn's vote-insights tweak. Reddit writes these
    // labels in two orders, hence the "leading" variants.
    private static let ratioPattern =
        #"aria-label\s*=\s*['"]\s*([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*upvote\s+ratio\s*['"]"#
    private static let ratioLeadingPattern =
        #"aria-label\s*=\s*['"]\s*upvote\s+ratio\s*:?\s*([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*['"]"#
    private static let upvotesPattern =
        #"aria-label\s*=\s*['"]\s*([0-9][0-9,. '\#(nbsp)’]*\s*[kmb]?)\s+upvotes?\s*['"]"#
    private static let upvotesLeadingPattern =
        #"aria-label\s*=\s*['"]\s*upvotes?\s*:?\s*([0-9][0-9,. '\#(nbsp)’]*\s*[kmb]?)\s*['"]"#

    private static let nbsp = "\u{00a0}"

    /// Parses the server-rendered stats page. Kept a pure function so
    /// the markup handling is assertable without the network, since
    /// this is HTML scraping and Reddit's markup will drift.
    public static func parse(html: String) -> CommentVoteInsight? {
        var percent: Double?
        if let value = firstCapture(html, ratioPattern) ?? firstCapture(html, ratioLeadingPattern) {
            percent = Double(value)
        }

        var upvotes: Int?
        var abbreviated = false
        if let raw = firstCapture(html, upvotesPattern) ?? firstCapture(html, upvotesLeadingPattern) {
            let parsed = parseCount(raw)
            upvotes = parsed.value
            abbreviated = parsed.abbreviated
        }

        guard percent != nil || upvotes != nil else { return nil }
        return CommentVoteInsight(
            upvotePercent: percent,
            reportedUpvotes: upvotes,
            reportedUpvotesAreAbbreviated: abbreviated
        )
    }

    /// Count parsing: strips grouping separators (comma, period, space,
    /// non-breaking space, apostrophes) and applies k/m/b multipliers.
    static func parseCount(_ raw: String) -> (value: Int?, abbreviated: Bool) {
        var normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var multiplier = 1.0
        var abbreviated = false
        if normalized.hasSuffix("k") { multiplier = 1_000; abbreviated = true }
        else if normalized.hasSuffix("m") { multiplier = 1_000_000; abbreviated = true }
        else if normalized.hasSuffix("b") { multiplier = 1_000_000_000; abbreviated = true }
        if abbreviated { normalized.removeLast() }

        // Grouping separators to strip.
        let separators = CharacterSet(charactersIn: ", \u{00a0}'’")
        normalized = normalized.components(separatedBy: separators).joined()
        // A period is a decimal point in an abbreviated label ("1.2k")
        // but a grouping separator otherwise ("1.234").
        if !abbreviated { normalized = normalized.replacingOccurrences(of: ".", with: "") }
        normalized = normalized.trimmingCharacters(in: .whitespaces)

        guard let number = Double(normalized) else { return (nil, abbreviated) }
        return (Int((number * multiplier).rounded()), abbreviated)
    }

    private static func firstCapture(_ s: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: s) else { return nil }
        return String(s[range])
    }

    /// Cache lifetime (120s).
    public static let cacheLifetime: TimeInterval = 120

    /// Fetches the author's Insights for a comment. The page is only
    /// rendered for the signed-in author, so this needs the cookie
    /// session, not the OAuth token. Briefly cached (120s).
    public static func fetch(
        commentID: String,
        cookieHeader: String,
        session: URLSession = .shared
    ) async -> Outcome {
        if let entry = cache[commentID], Date().timeIntervalSince(entry.at) < cacheLifetime {
            return entry.outcome
        }
        guard let url = statsURL(commentID: commentID) else { return .blocked }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        // Reddit serves the modern, label-bearing markup to a desktop UA.
        request.setValue(BrowserUserAgent.desktopSafari, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return .blocked }
        let outcome: Outcome
        if let insight = parse(html: html) {
            outcome = .insight(insight)
        } else if isChallengePage(html) {
            outcome = .blocked
        } else if let reason = unavailableReason(html: html) {
            outcome = .unavailable(reason: reason)
        } else {
            outcome = .notReported
        }
        // A blocked load is not cached: it says nothing about the
        // comment, and caching it would make the user's retry a no-op.
        if outcome != .blocked {
            cache[commentID] = (outcome, Date())
        }
        return outcome
    }

    private static let cache = LockedCache<String, (outcome: Outcome, at: Date)>()
}
