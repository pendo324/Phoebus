import Foundation

/// Community Highlights: the horizontally-scrolling carousel of a subreddit's
/// pinned posts at the top of its feed (Apollo-Reborn 3.7.0). Moderators pin
/// posts; Reddit exposes them in the REST/OAuth listing as `stickied` posts.
///
/// Data rule: a small `/r/{sub}/hot?limit=...` fetch filtered to `stickied`
/// posts, independent of the feed's sort. It is a separate fetch because the
/// feed on screen does not contain the stickied posts when sorted by New.
///
/// Reborn's modes:
///
///   - Off     (`sCommunityHighlights` NO)
///   - Partial (`sCommunityHighlights` YES, `sCommunityHighlightsWeb` NO)
///   - Full    (both YES)
///
/// Only Partial is implemented. Full harvests up to 6 highlights with a hidden
/// `WKWebView` scrape because the OAuth token cannot reach the GraphQL endpoint
/// first-party apps use; Partial renders the stickied posts the REST API
/// returns.
public enum CommunityHighlights {
    /// Maximum posts fetched.
    public static let fetchLimit = 15

    /// A post is "New" for 24h.
    public static let newLifetime: TimeInterval = 24 * 60 * 60

    /// Layout constants, all Reborn's.
    public enum Metrics {
        /// Card width.
        public static let cardWidth: Double = 160
        /// Card height.
        public static let cardHeight: Double = 120
        /// Spacing between cards.
        public static let cardSpacing: Double = 10
        /// Leading/trailing padding.
        public static let sidePadding: Double = 16
        /// Title row height.
        public static let titleRowHeight: Double = 26
        /// Padding above the cards.
        public static let topPadding: Double = 6
        /// Padding below the cards.
        public static let bottomPadding: Double = 6
        /// Card corner radius.
        public static let cardCornerRadius: Double = 14
        /// In-card padding.
        public static let cardPadding: Double = 10

        /// Total header height: title row + top padding + card + bottom padding.
        public static var totalHeight: Double {
            titleRowHeight + topPadding + cardHeight + bottomPadding
        }
    }

    /// Header title, which is also the collapse control.
    public static let title = "Community Highlights"

    /// Badge text.
    public static let newBadgeText = "New"

    /// Accessibility copy.
    public static let newAccessibilityDescription = "New post, created less than 24 hours ago"

    /// Whether a post counts as "New".
    ///
    /// `isNew = age >= 0 && age < newLifetime`. A post with no creation date is
    /// not new.
    public static func isNew(createdAt: Date?, now: Date = Date()) -> Bool {
        guard let createdAt else { return false }
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age < newLifetime
    }

    /// Whether the plain unread dot shows.
    ///
    /// `unread = known && !read`; the dot is hidden when `!unread || isNew`, as a
    /// New post shows the combined New badge instead, never both markers.
    public static func showsUnreadDot(isKnown: Bool, isRead: Bool, isNew: Bool) -> Bool {
        let unread = isKnown && !isRead
        return unread && !isNew
    }

    /// Whether the New badge carries its own unread dot.
    ///
    /// The badge's dot follows `unread` alone, so a New and unread post shows one
    /// combined pill. Reading removes the dot and contracts the pill without
    /// restarting its day.
    public static func newBadgeShowsUnreadDot(isKnown: Bool, isRead: Bool) -> Bool {
        isKnown && !isRead
    }

    /// Splits a Reddit permalink into the subreddit and post id.
    ///
    /// Scraped cards carry only the `href` the carousel linked to, so opening one
    /// needs the ids the post loader takes. Reddit's shape is
    /// `/r/<sub>/comments/<id>/<slug>/`; the scrape strips any query string.
    public static func identifiers(fromPermalink permalink: String) -> (subreddit: String, postID: String)? {
        let parts = permalink.split(separator: "/").map(String.init)
        guard let commentsIndex = parts.firstIndex(of: "comments"),
              commentsIndex >= 2,
              parts[commentsIndex - 2].lowercased() == "r",
              commentsIndex + 1 < parts.count else { return nil }
        let subreddit = parts[commentsIndex - 1]
        let postID = parts[commentsIndex + 1]
        guard !subreddit.isEmpty, !postID.isEmpty else { return nil }
        return (subreddit, postID)
    }

    /// Finds an already-loaded post matching a scraped card.
    ///
    /// A scraped highlight carries only a title and a permalink, so without a
    /// match opening one would wait on a fresh `/comments` fetch. The feed has
    /// usually already loaded the stickied posts, so matching on the post id
    /// (the stable part of the permalink; the slug can differ in case and
    /// punctuation) makes it an ordinary push. Returns nil when the scrape found
    /// something the feed did not.
    public static func matchingPost(
        forPermalink permalink: String,
        in posts: [RedditPost]
    ) -> RedditPost? {
        guard let ids = identifiers(fromPermalink: permalink) else { return nil }
        return posts.first { post in
            // Compare ids, not permalinks: Reddit serves the same post under several slugs.
            post.id.caseInsensitiveCompare(ids.postID) == .orderedSame
                && post.subreddit.caseInsensitiveCompare(ids.subreddit) == .orderedSame
        }
    }

    /// How long fetched highlights are shown as-is: a week, since pinned
    /// posts rarely change. A visit after that shows them at once and
    /// re-checks quietly in the background; pull-to-refresh always re-checks.
    public static let cacheTTL: TimeInterval = 7 * 24 * 60 * 60

    public static func isStale(fetchedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) >= cacheTTL
    }

    /// What a refresh compares to decide whether the carousel needs
    /// rebuilding: the posts, their titles and comment counts.
    public static func signature(of posts: [RedditPost]) -> [String] {
        posts.map { "\($0.id)|\($0.title)|\($0.numComments)" }
    }

    /// The carousel's cards: the highlights minus pinned posts the feed shows
    /// as an interactive widget (a match thread, a game), which stay in the
    /// feed as in Reborn.
    public static func carouselPosts(from highlights: [RedditPost], feedShowsWidget: (RedditPost) -> Bool) -> [RedditPost] {
        highlights.filter { !feedShowsWidget($0) }
    }

    /// The pinned feed rows the carousel already shows, which Reborn hides
    /// from the feed: the REST cards, or the scraped cards' posts when those
    /// replace them.
    public static func feedRowIDsShownInCarousel(carouselPosts: [RedditPost], scrapedPermalinks: [String]) -> Set<String> {
        var ids = Set(carouselPosts.map { $0.id.lowercased() })
        for permalink in scrapedPermalinks {
            if let parts = identifiers(fromPermalink: permalink) { ids.insert(parts.postID.lowercased()) }
        }
        return ids
    }

    /// Whether a feed row is hidden because the carousel shows it.
    public static func feedHides(_ post: RedditPost, shownInCarousel ids: Set<String>) -> Bool {
        post.stickied && ids.contains(post.id.lowercased())
    }

    /// Picks the highlights out of a listing.
    /// Just the `stickied` filter, preserving listing order.
    public static func highlights(from posts: [RedditPost]) -> [RedditPost] {
        posts.filter(\.stickied)
    }
}
