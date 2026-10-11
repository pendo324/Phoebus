import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Insights for the signed-in user's own post, read from Reddit's
/// server-rendered `/poststats/<id>/` page. Phoebus-only; Apollo never had
/// this screen. Every section is optional: Reddit omits some for new or
/// small posts.
public struct PostInsights: Sendable, Equatable {
    public struct CountryShare: Sendable, Equatable, Identifiable {
        public let name: String
        /// Flag emoji; `nil` for the "Other" bucket.
        public let flag: String?
        public let percent: Double
        public var id: String { name }

        public init(name: String, flag: String?, percent: Double) {
            self.name = name
            self.flag = flag
            self.percent = percent
        }
    }

    public struct TopComment: Sendable, Equatable, Identifiable {
        public let commentID: String
        public let author: String
        /// Reddit's own relative age, e.g. "7 days ago".
        public let ageText: String
        public let votes: Int?
        public let text: String
        /// Site-relative or absolute link to the comment.
        public let permalink: String
        public var id: String { commentID }

        public init(commentID: String, author: String, ageText: String, votes: Int?, text: String, permalink: String) {
            self.commentID = commentID
            self.author = author
            self.ageText = ageText
            self.votes = votes
            self.text = text
            self.permalink = permalink
        }

        /// Absolute URL, for handing to the app's Reddit link routing.
        public var url: URL? {
            if permalink.hasPrefix("http") { return URL(string: permalink) }
            return URL(string: "https://www.reddit.com" + permalink)
        }
    }

    public var postTitle: String?
    public var views: Int?
    /// Views per hour for the first 48 hours; index 0 is hour 1.
    public var hourlyViews: [Int]
    public var countries: [CountryShare]
    public var upvotes: Int?
    /// Percentage, 0...100.
    public var upvoteRatioPercent: Double?
    public var comments: Int?
    public var shares: Int?
    public var reposts: Int?
    public var awards: Int?
    public var topComments: [TopComment]

    public init(postTitle: String? = nil, views: Int? = nil, hourlyViews: [Int] = [],
                countries: [CountryShare] = [], upvotes: Int? = nil, upvoteRatioPercent: Double? = nil,
                comments: Int? = nil, shares: Int? = nil, reposts: Int? = nil, awards: Int? = nil,
                topComments: [TopComment] = []) {
        self.postTitle = postTitle
        self.views = views
        self.hourlyViews = hourlyViews
        self.countries = countries
        self.upvotes = upvotes
        self.upvoteRatioPercent = upvoteRatioPercent
        self.comments = comments
        self.shares = shares
        self.reposts = reposts
        self.awards = awards
        self.topComments = topComments
    }

    /// True when the page rendered but carried none of the sections.
    public var isEmpty: Bool {
        views == nil && hourlyViews.isEmpty && countries.isEmpty && upvotes == nil
            && upvoteRatioPercent == nil && comments == nil && shares == nil
            && reposts == nil && awards == nil && topComments.isEmpty
    }

    /// "Hour N: X views" for the chart's selection readout (`hour` is 1-based).
    public func hourLabel(_ hour: Int) -> String? {
        guard hour >= 1, hour <= hourlyViews.count else { return nil }
        let count = hourlyViews[hour - 1]
        return "Hour \(hour): \(count) \(count == 1 ? "view" : "views")"
    }

    /// The chart's spoken summary: total plus the busiest hour.
    public var chartAccessibilitySummary: String {
        guard let peak = hourlyViews.max(), let index = hourlyViews.firstIndex(of: peak) else {
            return "No views in the first 48 hours"
        }
        let total = hourlyViews.reduce(0, +)
        return "Views for the first 48 hours: \(total) in total, most at hour \(index + 1) with \(peak)"
    }
}

public enum PostInsightsError: Error, Sendable, Equatable, LocalizedError {
    /// The response was not a post stats page (login redirect, 404 shell…).
    case notInsightsPage
    /// Reddit rendered the page but said Insights are unavailable.
    case unavailable(reason: String)
    /// Bot-check interstitial; retryable.
    case blocked
    case requiresWebSession

    public var errorDescription: String? {
        switch self {
        case .notInsightsPage:
            return "Reddit didn't return Insights for this post. Insights are only available to the post's author while signed in on the web."
        case .unavailable(let reason): return reason
        case .blocked: return "Reddit answered with a browser check instead of the Insights page. Try again."
        case .requiresWebSession: return "Post Insights needs a Reddit web session."
        }
    }
}

public enum PostInsightsParser {
    /// `https://www.reddit.com/poststats/<id>/`.
    public static func statsURL(postID: String) -> URL? {
        let id = postID.hasPrefix("t3_") ? String(postID.dropFirst(3)) : postID
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return URL(string: "https://www.reddit.com/poststats/\(id)/")
    }

    /// Eligibility: a post by the signed-in user.
    public static func isEligible(author: String?, currentUsername: String?) -> Bool {
        guard let author, let currentUsername, !author.isEmpty, !currentUsername.isEmpty else { return false }
        return author.caseInsensitiveCompare(currentUsername) == .orderedSame
    }

    /// Whether the markup is the stats page. `pageType="post_stats"` is the
    /// page's own routing marker; the section tracker names are the fallback.
    public static func looksLikeInsightsPage(html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("pagetype=\"post_stats\"")
            || lowered.contains("page-type=\"post_stats\"")
            || lowered.contains("san=\"post_stats__")
    }

    /// Parses the stats page. Pure, so the markup handling is assertable
    /// without the network. Prefers structured attributes (the chart's
    /// `tooltip-data` JSON, `aria-label`s) over visible text.
    public static func parse(html: String) throws -> PostInsights {
        guard looksLikeInsightsPage(html: html) else {
            if CommentVoteInsightsClient.isChallengePage(html) { throw PostInsightsError.blocked }
            if let reason = CommentVoteInsightsClient.unavailableReason(html: html) {
                throw PostInsightsError.unavailable(reason: reason)
            }
            throw PostInsightsError.notInsightsPage
        }

        // The top comments carry their own "N upvote" labels, so the upvote
        // metrics are read only from the markup before them.
        let commentsStart = html.range(of: "post_stats__click__top_comment")?.lowerBound
            ?? html.range(of: "Number of votes:")?.lowerBound
        let head = commentsStart.map { String(html[..<$0]) } ?? html

        var insights = PostInsights()
        insights.postTitle = postTitle(in: head)
        insights.views = metric(html, #"views?"#)
        insights.upvotes = metric(head, #"upvotes?"#)
        insights.comments = metric(html, #"comments?"#)
        insights.shares = metric(html, #"shares?"#)
        insights.reposts = metric(html, #"reposts?"#)
        insights.awards = metric(html, #"awards?"#)
        if let value = firstCapture(head, #"aria-label\s*=\s*"\s*([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*upvote\s+ratio\s*""#) {
            insights.upvoteRatioPercent = Double(value)
        }
        insights.hourlyViews = hourlyViews(in: head)
        insights.countries = countries(in: head)
        insights.topComments = topComments(in: html)
        return insights
    }

    // MARK: - Sections

    /// The row's `aria-label="<count> <noun>"`.
    private static func metric(_ html: String, _ noun: String) -> Int? {
        let pattern = #"aria-label\s*=\s*"\s*([0-9][0-9,.\#u{00a0}' ]*\s*[kmb]?)\s+"# + noun + #"\s*""#
        guard let raw = firstCapture(html, pattern) else { return nil }
        return CommentVoteInsightsClient.parseCount(raw).value
    }

    private static func postTitle(in html: String) -> String? {
        // The post's title is the first h2 after the page's own h1.
        let scope = html.range(of: "</h1>").map { String(html[$0.upperBound...]) } ?? html
        guard let raw = firstCapture(scope, #"(?s)<h2\b[^>]*>(.*?)</h2>"#) else { return nil }
        let text = CommentVoteInsightsClient.plainText(raw)
        return text.isEmpty ? nil : text
    }

    /// The chart's `<chart-tooltips-controller tooltip-data="{...}">`
    /// (`data.Views`), falling back to the screen-reader list "At hour N:
    /// X views".
    private static func hourlyViews(in html: String) -> [Int] {
        if let tag = SocialLinkScraper.extractTags(html: html, named: "chart-tooltips-controller").first,
           let raw = SocialLinkScraper.attribute(named: "tooltip-data", in: tag),
           let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let series = json["data"] as? [String: Any],
           let views = (series["Views"] ?? series.values.first) as? [Any] {
            let counts = views.compactMap { ($0 as? NSNumber)?.intValue }
            if counts.count == views.count, !counts.isEmpty { return counts }
        }
        guard let regex = try? NSRegularExpression(pattern: #"At hour ([0-9]+): ([0-9]+) views?"#) else { return [] }
        var byHour: [Int: Int] = [:]
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let hourRange = Range(match.range(at: 1), in: html), let countRange = Range(match.range(at: 2), in: html),
                  let hour = Int(html[hourRange]), let count = Int(html[countRange]) else { continue }
            byHour[hour] = count
        }
        guard let last = byHour.keys.max() else { return [] }
        return (1...last).map { byHour[$0] ?? 0 }
    }

    /// Rows after "Top countries by views": `<div>flag</div><p>name</p><p>NN%</p>`.
    private static func countries(in html: String) -> [PostInsights.CountryShare] {
        guard let marker = html.range(of: "Top countries by views") else { return [] }
        var section = String(html[marker.upperBound...])
        if let end = section.range(of: "</section>") { section = String(section[..<end.lowerBound]) }
        let pattern = #"(?s)(?:<div>([^<]*)</div>\s*)?<p\b[^>]*>\s*([^<]*?)\s*</p>\s*<p\b[^>]*>\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var rows: [PostInsights.CountryShare] = []
        for match in regex.matches(in: section, range: NSRange(section.startIndex..., in: section)) {
            guard let nameRange = Range(match.range(at: 2), in: section),
                  let percentRange = Range(match.range(at: 3), in: section),
                  let percent = Double(section[percentRange]) else { continue }
            let name = CommentVoteInsightsClient.plainText(String(section[nameRange]))
            guard !name.isEmpty else { continue }
            var flag: String?
            if let flagRange = Range(match.range(at: 1), in: section) {
                let value = section[flagRange].trimmingCharacters(in: .whitespacesAndNewlines)
                flag = value.isEmpty ? nil : value
            }
            rows.append(.init(name: name, flag: flag, percent: percent))
        }
        return rows
    }

    /// Each top comment is a block starting at its `aria-label="Comment by
    /// <author>, <age>, Number of votes: <n>. <text>"`.
    private static func topComments(in html: String) -> [PostInsights.TopComment] {
        let marker = #"aria-label="Comment by "#
        var starts: [String.Index] = []
        var cursor = html.startIndex
        while let range = html.range(of: marker, range: cursor..<html.endIndex) {
            starts.append(range.lowerBound)
            cursor = range.upperBound
        }
        var comments: [PostInsights.TopComment] = []
        for (offset, start) in starts.enumerated() {
            let end = offset + 1 < starts.count ? starts[offset + 1] : html.endIndex
            let block = String(html[start..<end])
            guard let label = SocialLinkScraper.attribute(named: "aria-label", in: " " + block),
                  let header = captures(label, #"^Comment by ([^,]+), ([^,]+), Number of votes: ([0-9,]+)\.?\s*(.*)$"#),
                  let permalink = firstCapture(block, #"<a\s+href="([^"]*/comments/[^"]+)""#)
            else { continue }
            let path = permalink.split(separator: "/").last.map(String.init) ?? ""
            guard !path.isEmpty else { continue }
            var text = header[3]
            if let body = firstCapture(block, #"(?s)<div\b[^>]*id="[^"]*rtjson-content"[^>]*>(.*?)</div>"#) {
                let plain = CommentVoteInsightsClient.plainText(body)
                if !plain.isEmpty { text = plain }
            }
            comments.append(.init(commentID: path, author: header[0], ageText: header[1],
                                  votes: Int(header[2].replacingOccurrences(of: ",", with: "")),
                                  text: text, permalink: SocialLinkScraper.decodeEntities(permalink)))
        }
        return comments
    }

    // MARK: - Regex helpers

    private static func firstCapture(_ s: String, _ pattern: String) -> String? {
        captures(s, pattern)?.first
    }

    private static func captures(_ s: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: s).map { String(s[$0]) } ?? ""
        }
    }
}

/// Fetches the stats page over the web session.
public enum PostInsightsClient {
    public static func fetch(postID: String, cookieHeader: String, session: URLSession = .shared) async throws -> PostInsights {
        guard let url = PostInsightsParser.statsURL(postID: postID) else { throw PostInsightsError.notInsightsPage }
        guard let html = await CommentVoteInsightsClient.fetchPageHTML(url: url, cookieHeader: cookieHeader, session: session) else {
            throw PostInsightsError.blocked
        }
        return try PostInsightsParser.parse(html: html)
    }
}
