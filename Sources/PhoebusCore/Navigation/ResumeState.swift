import Foundation

/// "Resume Where I Left Off": a cold launch reopens the tab, feed, post
/// and thread the reader left. Phoebus-only; neither Apollo nor Reborn has it.
public struct ResumeSettings: Codable, Sendable, Equatable {
    public var resumeWhereLeftOff: Bool

    public static let `default` = ResumeSettings(resumeWhereLeftOff: false)

    public init(resumeWhereLeftOff: Bool) {
        self.resumeWhereLeftOff = resumeWhereLeftOff
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resumeWhereLeftOff = try container.decode(.resumeWhereLeftOff, default: Self.default, \.resumeWhereLeftOff)
    }
}

public enum ResumeSettingsStore {
    public static let storage = SettingsStore<ResumeSettings>(
        key: "com.pendo324.Phoebus.resumeSettings") { .default }

    public static func load() -> ResumeSettings { storage.load() }
}

extension ResumeSettings: StoredSettingsModel {
    public static var store: SettingsStore<ResumeSettings> { ResumeSettingsStore.storage }
}

/// Where the reader was: the selected tab and, on the Posts tab, the open
/// feed, its topmost post on screen and the post open on top of it. The
/// thread's own position is "Remember Thread Position"'s.
public struct ResumeSnapshot: Codable, Sendable, Equatable {
    public struct OpenPost: Codable, Sendable, Equatable {
        public var id: String
        public var subreddit: String

        public init(id: String, subreddit: String) {
            self.id = id
            self.subreddit = subreddit
        }
    }

    public var savedAt: Date
    /// The signed-in account; another account's snapshot is never restored.
    public var account: String?
    public var tab: Int
    /// nil when the Posts tab was at the Subreddits list.
    public var feed: LastViewedSubredditStore.Destination?
    /// The feed's sort; a feed reopening under another sort keeps its top.
    public var sort: String?
    public var topPostID: String?
    public var openPost: OpenPost?

    public init(savedAt: Date, account: String?, tab: Int, feed: LastViewedSubredditStore.Destination?,
                sort: String?, topPostID: String?, openPost: OpenPost?) {
        self.savedAt = savedAt
        self.account = account
        self.tab = tab
        self.feed = feed
        self.sort = sort
        self.topPostID = topPostID
        self.openPost = openPost
    }

    /// Equal apart from when it was taken.
    public func describesSamePlace(as other: ResumeSnapshot) -> Bool {
        var other = other
        other.savedAt = savedAt
        return self == other
    }
}

/// The one saved snapshot, as a JSON blob. Not part of settings backups
/// (`SettingsDomainSnapshot.excludedKeys`): it says where this device was.
public enum ResumeStore {
    static let key = "com.pendo324.Phoebus.resumeState"

    public static func load(from defaults: UserDefaults = .standard) -> ResumeSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ResumeSnapshot.self, from: data)
    }

    /// Saves `snapshot` while the setting is on. Unless `force`, an
    /// unchanged place is not rewritten.
    public static func record(_ snapshot: ResumeSnapshot, force: Bool = false, defaults: UserDefaults = .standard) {
        guard ResumeSettingsStore.storage.load(from: defaults).resumeWhereLeftOff else { return }
        if !force, let current = load(from: defaults), current.describesSamePlace(as: snapshot) { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

public enum ResumePolicy {
    /// Older than this, the reader has moved on and a launch starts fresh.
    public static let maxAge: TimeInterval = 24 * 60 * 60
    /// Pages fetched in all, the first included, looking for the saved post.
    public static let maxPagesToFind = 3

    /// The snapshot a cold launch should rebuild, or nil to launch as
    /// usual. A launch from a link, widget, notification, quick action or
    /// Shortcut goes where it was sent instead.
    public static func snapshotToRestore(_ snapshot: ResumeSnapshot?, enabled: Bool, account: String?,
                                         now: Date, openedFromLink: Bool) -> ResumeSnapshot? {
        guard enabled, !openedFromLink, let snapshot else { return nil }
        let age = now.timeIntervalSince(snapshot.savedAt)
        guard age >= 0, age < maxAge else { return nil }
        guard let account, let saved = snapshot.account,
              saved.caseInsensitiveCompare(account) == .orderedSame else { return nil }
        return snapshot
    }

    /// Whether to fetch another page looking for `target`.
    public static func shouldLoadMore(toFind target: String, loadedIDs: [String], pagesLoaded: Int,
                                      reachedEnd: Bool) -> Bool {
        !loadedIDs.contains(target) && !reachedEnd && pagesLoaded < maxPagesToFind
    }

    /// The saved top post is scrolled back to only in the listing it came
    /// from, and only when it isn't the feed's first post anyway.
    public static func scrollTarget(for snapshot: ResumeSnapshot, feedSort: String, loadedIDs: [String]) -> String? {
        guard let target = snapshot.topPostID, snapshot.sort == nil || snapshot.sort == feedSort,
              let index = loadedIDs.firstIndex(of: target), index > 0 else { return nil }
        return target
    }

    /// The feed's identity for the snapshot, from what a feed screen
    /// carries: a multireddit path, or a subreddit name where "" is Home.
    public static func feedDestination(subreddit: String, multiredditPath: String?,
                                       multiredditName: String?) -> LastViewedSubredditStore.Destination {
        if let multiredditPath {
            return .multireddit(path: multiredditPath, name: multiredditName ?? multiredditPath)
        }
        switch subreddit.lowercased() {
        case "": return .home
        case "popular": return .popular
        case "all": return .all
        case "mod": return .moderator
        default: return .subreddit(subreddit)
        }
    }
}
