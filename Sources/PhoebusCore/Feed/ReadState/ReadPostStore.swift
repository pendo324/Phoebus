import Foundation

/// Tracks which posts the user has already viewed, to grey them out or
/// optionally auto-hide them from feeds, matching Apollo's "mark read on
/// scroll" / "hide read posts" behavior.
public struct MarkReadSettings: Codable, Sendable, Equatable {
    /// When true, opening a post detail marks it as read.
    public var markReadOnOpen: Bool
    /// "Hide Posts…": true is Permanently (hidden on Reddit, still in
    /// Profile > Hidden), false is Temporarily (gone until the feed
    /// refreshes). The inverse of the key `HidePostsTemporarily`; Apollo's
    /// default is Permanently.
    public var hideReadPosts: Bool
    /// Key: `AutoHideReadPosts`. Automatically hides read posts on every feed
    /// refresh. Requires `hideReadPosts` (the UI disables this toggle
    /// otherwise).
    public var autoHideReadPosts: Bool
    /// Key: `DisableAutoHideReadPostsInSubreddits`. When true,
    /// `autoHideReadPosts` is suppressed while viewing a specific
    /// subreddit's own feed (as opposed to Home/All/Popular).
    public var disableAutoHideInSubreddits: Bool
    /// Apollo's "Mark Read on Scroll" (Settings > General > Mark Read / Hiding
    /// Posts): marks posts read as they scroll past in the feed, independent
    /// of the open-based marking above.
    public var markReadOnScroll: Bool
    /// Apollo's "Show Hide Read Button": surfaces a manual "Hide Read Posts"
    /// action, separate from the automatic hiding governed by
    /// `autoHideReadPosts`.
    public var showHideReadButton: Bool

    public static let `default` = MarkReadSettings(markReadOnOpen: true, hideReadPosts: true, autoHideReadPosts: false, disableAutoHideInSubreddits: false, markReadOnScroll: false, showHideReadButton: false)

    public init(markReadOnOpen: Bool, hideReadPosts: Bool, autoHideReadPosts: Bool = false, disableAutoHideInSubreddits: Bool = false, markReadOnScroll: Bool = false, showHideReadButton: Bool = false) {
        self.markReadOnOpen = markReadOnOpen
        self.hideReadPosts = hideReadPosts
        self.autoHideReadPosts = autoHideReadPosts
        self.disableAutoHideInSubreddits = disableAutoHideInSubreddits
        self.markReadOnScroll = markReadOnScroll
        self.showHideReadButton = showHideReadButton
    }

    /// Custom decode so settings persisted without the newer
    /// `autoHideReadPosts`/`disableAutoHideInSubreddits` keys still decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markReadOnOpen = try container.decode(Bool.self, forKey: .markReadOnOpen)
        hideReadPosts = try container.decode(Bool.self, forKey: .hideReadPosts)
        autoHideReadPosts = try container.decodeIfPresent(Bool.self, forKey: .autoHideReadPosts) ?? false
        disableAutoHideInSubreddits = try container.decodeIfPresent(Bool.self, forKey: .disableAutoHideInSubreddits) ?? false
        markReadOnScroll = try container.decodeIfPresent(Bool.self, forKey: .markReadOnScroll) ?? false
        showHideReadButton = try container.decodeIfPresent(Bool.self, forKey: .showHideReadButton) ?? false
    }
}

/// Persists the set of read post fullnames and the mark-read settings.
/// Local-only (UserDefaults-backed), matching Apollo's on-device read
/// tracking: Reddit's API doesn't expose per-post read state for arbitrary
/// listings the way it does for the inbox.
public enum ReadPostStore {
    private static let settingsKey = "com.pendo324.Phoebus.markReadSettings"
    private static let readIDsKey = "com.pendo324.Phoebus.readPostIDs"
    /// Cap how many read IDs we retain, to keep UserDefaults small.
    private static let maxTracked = 5000

    /// A stored Temporarily is moved once to Apollo's default, Permanently.
    private static let permanentDefaultKey = "com.pendo324.Phoebus.markRead.permanentDefaultV1"

    public static let settingsStorage = SettingsStore<MarkReadSettings>(key: settingsKey, migrate: { settings, defaults in
        guard !defaults.bool(forKey: permanentDefaultKey) else { return false }
        defaults.set(true, forKey: permanentDefaultKey)
        guard !settings.hideReadPosts else { return false }
        settings.hideReadPosts = true
        return true
    }) { .default }

    public static func loadSettings() -> MarkReadSettings { settingsStorage.load() }

    public static func saveSettings(_ settings: MarkReadSettings) { settingsStorage.save(settings) }

    public static func isRead(_ fullname: String) -> Bool {
        readIDs().contains(fullname)
    }

    public static func markRead(_ fullname: String) {
        guard loadSettings().markReadOnOpen else { return }
        var ids = readIDs()
        ids.insert(fullname)
        // Trim oldest-inserted entries once over the cap. Sets have no insertion
        // order, so this approximates by total count rather than true LRU, which
        // is acceptable for a local read-tracking cache.
        if ids.count > maxTracked {
            ids = Set(ids.sorted().suffix(maxTracked))
        }
        UserDefaults.standard.set(Array(ids), forKey: readIDsKey)
        NotificationCenter.default.post(name: .apolloReadPostsChanged, object: fullname)
    }

    /// Merges read post fullnames from a real Apollo backup
    /// (`ReadPostIDs`). Unlike `markRead`, this ignores the
    /// "mark read on open" setting: it restores history, it does not
    /// record a new read.
    public static func importRead(_ fullnames: [String]) {
        var ids = readIDs()
        ids.formUnion(fullnames)
        if ids.count > maxTracked {
            ids = Set(ids.sorted().suffix(maxTracked))
        }
        UserDefaults.standard.set(Array(ids), forKey: readIDsKey)
    }

    public static func clearAll() {
        UserDefaults.standard.removeObject(forKey: readIDsKey)
    }

    private static func readIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: readIDsKey) ?? [])
    }

    /// Applies hide-read filtering to a listing.
    ///
    /// `autoHideReadPosts` is the gate for automatic hiding on refresh (both
    /// `hideReadPosts` and `autoHideReadPosts` must be on), and
    /// `disableAutoHideInSubreddits` suppresses hiding while the caller reports
    /// being in a specific subreddit's own feed (as opposed to
    /// Home/Popular/All/a multireddit).
    ///
    /// - Parameter isSpecificSubreddit: true when the caller is
    ///   showing one subreddit's own feed (not Home, r/popular,
    ///   r/all, r/mod, or a multireddit).
    public static func apply(_ posts: [RedditPost], isSpecificSubreddit: Bool = false) -> [RedditPost] {
        guard autoHides(loadSettings(), isSpecificSubreddit: isSpecificSubreddit) else { return posts }
        return posts.filter { !isRead($0.name) }
    }

    /// Whether Auto Hide applies here: on, Permanent, and not turned
    /// off for a subreddit's own feed.
    public static func autoHides(_ settings: MarkReadSettings, isSpecificSubreddit: Bool) -> Bool {
        guard settings.hideReadPosts, settings.autoHideReadPosts else { return false }
        return !(settings.disableAutoHideInSubreddits && isSpecificSubreddit)
    }

    /// The read posts among `posts`, which the Hide Read button and
    /// Auto Hide hide.
    public static func readPosts(in posts: [RedditPost]) -> [RedditPost] {
        let ids = readIDs()
        return posts.filter { ids.contains($0.name) }
    }
}
