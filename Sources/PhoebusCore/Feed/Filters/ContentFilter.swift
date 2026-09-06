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
        switch kind {
        case .subreddit:
            return post.subreddit.caseInsensitiveCompare(value) == .orderedSame
        case .author:
            return post.author.caseInsensitiveCompare(value) == .orderedSame
        case .keyword:
            // "…in title, link, or flair", as the section footer says.
            return [post.title, post.url ?? "", post.linkFlairText ?? ""]
                .contains { $0.range(of: value, options: .caseInsensitive) != nil }
        case .domain:
            guard let urlString = post.url, let host = URL(string: urlString)?.host else { return false }
            return host.range(of: value, options: .caseInsensitive) != nil
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

    /// Whether either filter system hides `post`.
    static func shouldHide(
        _ post: RedditPost,
        filters: [ContentFilter],
        postFilters: PostFilterRules
    ) -> Bool {
        if filters.contains(where: { $0.matches(post: post) }) { return true }
        if postFilters.hides(subreddit: post.subreddit,
                             title: post.title,
                             url: post.url,
                             flair: post.linkFlairText) { return true }
        // A crosspost is also tested against its parent, so a crosspost from a
        // filtered subreddit is filtered too. `RedditCrosspostParent` carries no
        // url/flair, so only the parent's subreddit and title are testable.
        if let parent = post.crosspostParent,
           postFilters.hides(subreddit: parent.subreddit,
                             title: parent.title,
                             url: nil,
                             flair: nil) { return true }
        return false
    }
}
