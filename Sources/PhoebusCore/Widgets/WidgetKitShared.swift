import Foundation

/// Shared behaviour for the widget suite.
///
/// Nine widgets share three mechanisms, so they live here once rather
/// than being re-derived per widget.
public enum WidgetKitShared {
    // MARK: - Sort

    /// "Where a widget exposes **Sort**: Hot, New, Top: Today, Top:
    /// This Week. Unset falls back to the widget's default."
    public enum Sort: String, CaseIterable, Sendable {
        case hot
        case new
        case topToday
        case topWeek

        public var displayName: String {
            switch self {
            case .hot: return "Hot"
            case .new: return "New"
            case .topToday: return "Top: Today"
            case .topWeek: return "Top: This Week"
            }
        }

        /// The listing path segment and `t` parameter this maps to.
        public var listingPath: String {
            switch self {
            case .hot: return "hot"
            case .new: return "new"
            case .topToday, .topWeek: return "top"
            }
        }

        public var timeframe: String? {
            switch self {
            case .topToday: return "day"
            case .topWeek: return "week"
            case .hot, .new: return nil
            }
        }
    }

    // MARK: - Caption

    /// "A single **Caption** picker controls how much text overlays
    /// the post".
    public enum Caption: String, CaseIterable, Sendable {
        case none
        case title
        case titleAndStats
        case detailed

        public var displayName: String {
            switch self {
            case .none: return "None"
            case .title: return "Title"
            case .titleAndStats: return "Title + Stats"
            case .detailed: return "Detailed"
            }
        }

        /// Whether the title shows at all. "None - clean image, no
        /// text (image posts)."
        public var showsTitle: Bool { self != .none }
        /// "Title + Stats - + score and comments."
        public var showsStats: Bool { self == .titleAndStats || self == .detailed }
        /// "Detailed - + age, author (and the body preview, for text
        /// posts)."
        public var showsDetails: Bool { self == .detailed }
    }

    // MARK: - Rotation

    /// "Rotating widgets (Showerthoughts, Jokes, Post, Photo) cycle
    /// through a pool of top posts: the visible post is a function of
    /// the wall-clock time, advancing ~every 25 min across an ~8 h
    /// window, so glances feel fresh without burning WidgetKit's
    /// reload budget."
    ///
    /// Deriving the index from the clock rather than storing it is the
    /// whole trick: a widget timeline is rebuilt unpredictably, so any
    /// stored cursor would jump around. A pure function of time gives
    /// every rebuild the same answer.
    public enum Rotation {
        /// ~25 minutes.
        public static let step: TimeInterval = 25 * 60
        /// ~8 hours, after which the cycle repeats.
        public static let window: TimeInterval = 8 * 60 * 60

        /// Number of distinct slots in one window.
        public static var slots: Int { Int(window / step) }

        /// Which pool index is visible at `date`, plus a manual
        /// `offset` for the ↻ button ("A circular ↻ button shows the
        /// next one on tap").
        public static func index(at date: Date, poolSize: Int, offset: Int = 0) -> Int {
            guard poolSize > 0 else { return 0 }
            let slot = Int(date.timeIntervalSince1970 / step)
            return ((slot + offset) % poolSize + poolSize) % poolSize
        }

        /// When the next rotation is due, for the timeline policy.
        public static func nextChange(after date: Date) -> Date {
            let elapsed = date.timeIntervalSince1970
            let next = (floor(elapsed / step) + 1) * step
            return Date(timeIntervalSince1970: next)
        }
    }

    // MARK: - Tap targets

    /// Widget tap URLs, in the `phoebus://` forms the app's URL handler
    /// routes: reddit paths through `RedditURLTarget.parseAppScheme`,
    /// tab actions through `QuickAction.parse`.
    public enum DeepLink {
        public static func post(_ post: RedditPost) -> URL {
            URL(string: "phoebus://reddit.com/r/\(post.subreddit)/comments/\(post.id)/")!
        }

        /// `name` is user-typed in the Shortcuts widget, so it is escaped.
        public static func subreddit(_ name: String) -> URL {
            let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? ""
            return URL(string: "phoebus://reddit.com/r/\(escaped)/")!
        }

        public static func quickAction(_ action: QuickAction) -> URL {
            URL(string: "phoebus://reborn/\(action.rawValue)")!
        }
    }

    // MARK: - Content filtering

    /// "Every widget hides NSFW, spoiler, stickied, and removed/deleted
    /// posts."
    ///
    /// Applied to every widget's pool, not per widget, which is why it
    /// lives here. Stickied is included because a pinned mod post is
    /// almost never what a glanceable widget should show.
    public static func filtered(_ posts: [RedditPost]) -> [RedditPost] {
        posts.filter { post in
            !post.over18
                && !post.spoiler
                && !post.stickied
                && !isRemoved(post)
        }
    }

    /// Reddit signals a removed or deleted post by stubbing the author
    /// and body rather than omitting the post.
    static func isRemoved(_ post: RedditPost) -> Bool {
        let author = post.author.lowercased()
        if author == "[deleted]" || author == "[removed]" { return true }
        if let text = post.selftext?.lowercased(),
           text == "[deleted]" || text == "[removed]" { return true }
        return false
    }

    /// "image posts only" for the Photo widget.
    public static func imagePostsOnly(_ posts: [RedditPost]) -> [RedditPost] {
        posts.filter { post in
            guard let url = post.url?.lowercased() else { return false }
            return [".jpg", ".jpeg", ".png", ".gif", ".webp"].contains { url.hasSuffix($0) }
                || url.contains("i.redd.it")
                || url.contains("i.imgur.com")
        }
    }

    /// "filtered to self-text jokes (so there's always a punchline)"
    /// for the Jokes widget.
    public static func selfPostsOnly(_ posts: [RedditPost]) -> [RedditPost] {
        posts.filter { $0.isSelf && !($0.selftext ?? "").isEmpty }
    }
}
