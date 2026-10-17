import Foundation

/// Apollo's Filters settings: hide posts matching a blocked subreddit,
/// keyword, domain, or author client-side (distinct from Reddit's server-side
/// subreddit blocking).
public enum FilterKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case subreddit
    case keyword
    case author
    case domain

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .subreddit: return "Subreddit"
        case .keyword: return "Keyword"
        case .author: return "Author"
        case .domain: return "Domain"
        }
    }

    public var systemImage: String {
        switch self {
        case .subreddit: return "r.square"
        case .keyword: return "text.magnifyingglass"
        case .author: return "person.crop.circle.badge.xmark"
        case .domain: return "link"
        }
    }
}

public struct ContentFilter: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: FilterKind
    public var value: String

    public init(id: UUID = UUID(), kind: FilterKind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }

    /// Matches a post against this filter, mirroring Apollo's
    /// case-insensitive substring match for keyword/domain filters and
    /// exact match for subreddit/author filters.
    public func matches(post: RedditPost) -> Bool {
        match(post: post) != nil
    }

    /// The rule this filter matches on `post`, or nil. The single matcher per
    /// kind, shared with `FilterExplanation`.
    func match(post: RedditPost) -> PostFilterMatch? {
        switch kind {
        case .subreddit:
            return post.subreddit.caseInsensitiveCompare(value) == .orderedSame ? .subreddit(value) : nil
        case .author:
            return post.author.caseInsensitiveCompare(value) == .orderedSame ? .author(value) : nil
        case .keyword:
            // "…in title, link, or flair", as the section footer says.
            if post.title.range(of: value, options: .caseInsensitive) != nil {
                return .keyword(value: value, field: .title)
            }
            if let url = post.url, url.range(of: value, options: .caseInsensitive) != nil {
                return .keyword(value: value, field: .link)
            }
            if let flair = post.linkFlairText, flair.range(of: value, options: .caseInsensitive) != nil {
                return .keyword(value: value, field: .flair)
            }
            return nil
        case .domain:
            guard let urlString = post.url, let host = URL(string: urlString)?.host else { return nil }
            return host.range(of: value, options: .caseInsensitive) != nil ? .domain(value) : nil
        }
    }
}

/// Persists local content filters across launches (UserDefaults-backed;
/// client-side only, not synced to Reddit).
public enum ContentFilterStore {
    private static let key = "com.pendo324.Phoebus.contentFilters"

    public static let storage = SettingsStore<[ContentFilter]>(key: key) { [] }

    public static func load() -> [ContentFilter] { storage.load() }

    public static func save(_ filters: [ContentFilter]) { storage.save(filters) }

    /// Filters out posts matching any stored filter. Filtered Subreddits apply
    /// only to r/all and r/popular, as in Apollo; opening one still shows it.
    public static func apply(_ posts: [RedditPost], isAllOrPopular: Bool) -> [RedditPost] {
        // Apollo-Reborn's Post Filters run alongside these global filters: per-subreddit
        // keywords, per-subreddit flairs and subreddit-name substrings. See
        // `PostFilterRules`.
        apply(posts, filters: activeFilters(load(), isAllOrPopular: isAllOrPopular), postFilters: PostFilterStore.load())
    }

    public static func activeFilters(_ filters: [ContentFilter], isAllOrPopular: Bool) -> [ContentFilter] {
        isAllOrPopular ? filters : filters.filter { $0.kind != .subreddit }
    }

    /// Testable variant taking an explicit filter list rather than
    /// reading from UserDefaults.
    public static func apply(_ posts: [RedditPost], filters: [ContentFilter]) -> [RedditPost] {
        apply(posts, filters: filters, postFilters: .empty)
    }

    /// Applies BOTH filter systems: Apollo's own global filters and
    /// Apollo-Reborn's per-subreddit Post Filters.
    public static func apply(
        _ posts: [RedditPost],
        filters: [ContentFilter],
        postFilters: PostFilterRules
    ) -> [RedditPost] {
        guard !filters.isEmpty || !postFilters.isEmpty else { return posts }
        var kept: [RedditPost] = []
        kept.reserveCapacity(posts.count)
        for post in posts where !shouldHide(post, filters: filters, postFilters: postFilters) {
            kept.append(post)
        }
        return kept
    }

    /// Whether either filter system hides `post`. Built from the same
    /// per-kind matchers `FilterExplanation` uses, so the feed and the Filters
    /// tester can't disagree.
    public static func shouldHide(
        _ post: RedditPost,
        filters: [ContentFilter],
        postFilters: PostFilterRules
    ) -> Bool {
        FilterExplanation.contentMatch(post, filters: filters) != nil
            || FilterExplanation.postFilterMatch(post, postFilters: postFilters) != nil
    }
}
