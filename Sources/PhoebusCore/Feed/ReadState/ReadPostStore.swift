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
        readIDs.contains(fullname)
    }

    public static func markRead(_ fullname: String) {
        guard loadSettings().markReadOnOpen else { return }
        if readIDs.insert(fullname, cap: maxTracked) {
            UserDefaults.standard.set(readIDs.ordered, forKey: readIDsKey)
        }
        NotificationCenter.default.post(name: .apolloReadPostsChanged, object: fullname)
    }

    /// Merges read post fullnames from a real Apollo backup
    /// (`ReadPostIDs`). Unlike `markRead`, this ignores the
    /// "mark read on open" setting: it restores history, it does not
    /// record a new read.
    public static func importRead(_ fullnames: [String]) {
        var changed = false
        for fullname in fullnames where readIDs.insert(fullname, cap: maxTracked) { changed = true }
        if changed { UserDefaults.standard.set(readIDs.ordered, forKey: readIDsKey) }
    }

    public static func clearAll() {
        readIDs.reset()
        UserDefaults.standard.removeObject(forKey: readIDsKey)
    }

    /// Only this store writes the key, so it is read from defaults once.
    /// Rows ask on every appearance, and Mark Read on Scroll writes every
    /// time a row leaves the top: rebuilding a set of thousands each time
    /// stalled the scroll.
    private static let readIDs = ReadIDs { UserDefaults.standard.stringArray(forKey: readIDsKey) ?? [] }

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
        posts.filter { readIDs.contains($0.name) }
    }
}

/// The read fullnames, oldest first, so the cap drops the oldest.
private final class ReadIDs: @unchecked Sendable {
    private let lock = NSLock()
    private let load: @Sendable () -> [String]
    private var isLoaded = false
    private var list: [String] = []
    private var set: Set<String> = []

    init(load: @escaping @Sendable () -> [String]) {
        self.load = load
    }

    var ordered: [String] {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        return list
    }

    func contains(_ fullname: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        return set.contains(fullname)
    }

    /// False when it was already there.
    func insert(_ fullname: String, cap: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        loadIfNeeded()
        guard set.insert(fullname).inserted else { return false }
        list.append(fullname)
        if list.count > cap {
            let dropped = list.count - cap
            set.subtract(list.prefix(dropped))
            list.removeFirst(dropped)
        }
        return true
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        isLoaded = true
        list = []
        set = []
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        list = load().filter { set.insert($0).inserted }
    }
}
