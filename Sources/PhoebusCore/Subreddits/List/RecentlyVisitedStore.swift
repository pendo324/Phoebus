import Foundation

/// One subreddit, profile or multireddit the user opened.
public struct RecentlyVisitedEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case subreddit
        case user
        case multireddit
    }

    public var kind: Kind
    /// The display casing it was opened with ("iOSProgramming", "spez").
    public var name: String
    /// A multireddit's path (`/user/<owner>/m/<name>`); nil otherwise.
    public var path: String?
    public var visitedAt: Date

    public init(kind: Kind, name: String, path: String? = nil, visitedAt: Date = Date()) {
        self.kind = kind
        self.name = name
        self.path = path
        self.visitedAt = visitedAt
    }

    /// Identity for de-duplication: Reddit names are case-insensitive, and a
    /// multireddit is identified by its path rather than its (unowned) name.
    public var id: String { "\(kind.rawValue):\((path ?? name).lowercased())" }
}

/// Recently visited subreddits, profiles and multireddits, newest first.
/// Not an Apollo or Reborn feature (inspired by Continuum's history); kept
/// per account, with the signed-out state as its own bucket.
public enum RecentlyVisitedStore {
    private static let key = "com.pendo324.Phoebus.recentlyVisited"

    /// How many entries each account keeps.
    public static let limit = 50

    /// Lowercased username → that account's entries; "" is signed out.
    public static let storage = SettingsStore<[String: [RecentlyVisitedEntry]]>(key: key) { [:] }

    /// The bucket for `username`; nil (signed out) maps to "".
    public static func bucket(for username: String?) -> String {
        username?.lowercased() ?? ""
    }

    private static var currentBucket: String {
        bucket(for: FavoriteSubredditsAccountContext.currentUsernameProvider())
    }

    /// Whether opening this feed counts as a visit: not Home, Popular, All,
    /// Moderator or other meta feeds, and not an ad-hoc `a+b` combination.
    public static func isRecordableSubreddit(_ name: String) -> Bool {
        let lowered = name.trimmingCharacters(in: .whitespaces).lowercased()
        let metaFeeds: Set<String> = ["", "home", "popular", "all", "mod", "moderator", "friends", "random", "randnsfw"]
        return !metaFeeds.contains(lowered) && !lowered.contains("+") && !lowered.hasPrefix("all-")
    }

    /// `entries` with `entry` moved to the front, de-duplicated and capped.
    public static func recording(_ entry: RecentlyVisitedEntry, into entries: [RecentlyVisitedEntry],
                                 limit: Int = limit) -> [RecentlyVisitedEntry] {
        Array(([entry] + entries.filter { $0.id != entry.id }).prefix(limit))
    }

    /// The account's entries, optionally only one kind.
    public static func entries(kind: RecentlyVisitedEntry.Kind? = nil, username: String?? = nil,
                               in defaults: UserDefaults = .standard) -> [RecentlyVisitedEntry] {
        let all = storage.load(from: defaults)[bucketKey(username)] ?? []
        guard let kind else { return all }
        return all.filter { $0.kind == kind }
    }

    public static func record(_ entry: RecentlyVisitedEntry, username: String?? = nil,
                              in defaults: UserDefaults = .standard) {
        let bucket = bucketKey(username)
        let current = storage.load(from: defaults)[bucket] ?? []
        // Popping back onto a feed reappears it; skip the write when nothing moves.
        if current.first?.id == entry.id { return }
        storage.update(in: defaults) { $0[bucket] = recording(entry, into: current) }
    }

    public static func recordSubreddit(_ name: String) {
        guard isRecordableSubreddit(name) else { return }
        record(RecentlyVisitedEntry(kind: .subreddit, name: name))
    }

    public static func recordUser(_ name: String) {
        // Your own profile is not a visit.
        guard !name.isEmpty, bucket(for: name) != currentBucket else { return }
        record(RecentlyVisitedEntry(kind: .user, name: name))
    }

    public static func recordMultireddit(path: String, name: String) {
        guard !path.isEmpty else { return }
        record(RecentlyVisitedEntry(kind: .multireddit, name: name, path: path))
    }

    public static func remove(_ entry: RecentlyVisitedEntry, username: String?? = nil,
                              in defaults: UserDefaults = .standard) {
        let bucket = bucketKey(username)
        storage.update(in: defaults) { $0[bucket]?.removeAll { $0.id == entry.id } }
    }

    /// Clears the account's list; other accounts keep theirs.
    public static func clear(username: String?? = nil, in defaults: UserDefaults = .standard) {
        let bucket = bucketKey(username)
        storage.update(in: defaults) { $0[bucket] = nil }
    }

    /// `username` as passed (`.some(nil)` is signed out), or the active
    /// account when omitted.
    private static func bucketKey(_ username: String??) -> String {
        switch username {
        case .some(let name): return bucket(for: name)
        case .none: return currentBucket
        }
    }
}
