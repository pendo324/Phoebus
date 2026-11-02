import Foundation

/// Per-launch subreddit icon cache behind `SubredditIconView`: one `/about`
/// per subreddit however many rows ask at once, and the feed header's own
/// `/about` feeds it too. A subreddit with no icon is remembered so it isn't
/// refetched for every row; one Reddit won't describe (private, banned) is
/// remembered for `missRetryDelay`; a failed connection is not remembered.
public actor SubredditIconCache {
    public static let shared = SubredditIconCache()

    /// How long a subreddit that has no `/about` page is left alone.
    public static let missRetryDelay: TimeInterval = 5 * 60

    /// Both of a subreddit's icons, so the Use Community Icons switch
    /// takes effect without a refetch.
    public struct Icons: Sendable, Equatable {
        public let classic: String?
        public let community: String?

        public init(classic: String?, community: String?) {
            self.classic = ImageURLCleaning.cleaned(classic)
            self.community = ImageURLCleaning.cleaned(community)
        }

        public func url(useCommunityIcons: Bool) -> String? {
            useCommunityIcons ? (community ?? classic) : classic
        }
    }

    private struct Entry {
        let icons: Icons
        /// nil: kept for the launch.
        let expiresAt: Date?
    }

    private var entries: [String: Entry] = [:]
    private var lookups: [String: Task<RedditSubreddit, Error>] = [:]

    public init() {}

    public func removeAll() { entries.removeAll() }

    /// Seeds the cache from subreddit objects already in hand.
    ///
    /// The cache is memory-only, so without seeding every launch would re-fetch
    /// `/r/<name>/about` once per subreddit before any icon appeared, even when
    /// the list loaded from disk. The cached listing already carries
    /// `communityIcon`/`iconImage` for every row, so the URLs are handed over
    /// directly. Anything already known is left alone, since a live
    /// `info(for:fetch:)` result is fresher than a snapshot.
    public func seed(from subreddits: [RedditSubreddit]) {
        for subreddit in subreddits {
            let key = subreddit.displayName.lowercased()
            guard lookup(key) == nil else { continue }
            entries[key] = Entry(icons: Icons(classic: subreddit.iconImage, community: subreddit.communityIcon), expiresAt: nil)
        }
    }

    /// nil when the subreddit has not been looked up (or its miss has expired).
    public func lookup(_ subreddit: String, now: Date = Date()) -> Icons? {
        let key = subreddit.lowercased()
        guard let entry = entries[key] else { return nil }
        if let expiresAt = entry.expiresAt, expiresAt <= now {
            entries[key] = nil
            return nil
        }
        return entry.icons
    }

    /// Drops what is known about one subreddit (a quarantine opt-in changes what
    /// Reddit serves for it), so the next row asks again.
    public func forget(_ subreddit: String) {
        entries[subreddit.lowercased()] = nil
    }

    public func store(_ value: Icons, for subreddit: String) {
        entries[subreddit.lowercased()] = Entry(icons: value, expiresAt: nil)
    }

    /// The subreddit's `/about`, fetched once while a fetch for it is running,
    /// and its icons remembered. Always asks Reddit (the feed header needs the
    /// moderator and join state fresh); `SubredditIconView` reads `lookup` first.
    public func info(for subreddit: String, now: Date = Date(),
                     fetch: @escaping @Sendable () async throws -> RedditSubreddit) async throws -> RedditSubreddit {
        let key = subreddit.lowercased()
        if let running = lookups[key] { return try await running.value }
        let task = Task { try await fetch() }
        lookups[key] = task
        do {
            let info = try await task.value
            lookups[key] = nil
            entries[key] = Entry(icons: Icons(classic: info.iconImage, community: info.communityIcon), expiresAt: nil)
            return info
        } catch {
            lookups[key] = nil
            if ProfileLookupFailure(error).isDefinitiveMiss {
                entries[key] = Entry(icons: Icons(classic: nil, community: nil), expiresAt: now.addingTimeInterval(Self.missRetryDelay))
            }
            throw error
        }
    }

}
