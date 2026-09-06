import Foundation

/// On-disk cache of the Subreddits root's own lists, so the screen renders
/// in its first frame instead of waiting for `/subreddits/mine/subscriber`
/// to paginate to completion. The decoded lists are written to disk and
/// read back synchronously at init.
///
/// Unlike `SubscribedSubredditsCache` (in-memory, lowercased names only,
/// for filtering r/all), this holds the full objects and survives a
/// launch. Both are invalidated by the same events, so `invalidate()` here
/// also clears that one.
///
/// The cached copy is always shown first and refreshed behind it, so there
/// is no TTL: a stale list being corrected beats an empty one, and unlike
/// the memory-only, time-bounded `FeedSnapshotCache` this answers "what
/// did this account look like last time".
public enum SubredditListCache {
    /// Everything the root screen draws before its own network load.
    public struct Snapshot: Codable, Sendable {
        public var subscriptions: [RedditSubreddit]
        public var multireddits: [RedditMultireddit]
        public var moderated: [RedditSubreddit]
        /// Which account this belongs to, so switching accounts never shows the
        /// previous user's subreddits.
        public var accountUsername: String

        public init(
            subscriptions: [RedditSubreddit],
            multireddits: [RedditMultireddit],
            moderated: [RedditSubreddit],
            accountUsername: String
        ) {
            self.subscriptions = subscriptions
            self.multireddits = multireddits
            self.moderated = moderated
            self.accountUsername = accountUsername
        }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("subreddit-list-cache.json")
    }

    /// Reads the cached lists for `username`; nil when the cache belongs to a
    /// different account. Synchronous on purpose: the caller needs it during
    /// `init` to have content in the first frame.
    public static func load(for username: String) -> Snapshot? {
        guard !username.isEmpty,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.accountUsername == username
        else { return nil }
        return snapshot
    }

    public static func save(_ snapshot: Snapshot) {
        // A signed-out or not-yet-resolved account would write a
        // snapshot that can never be matched on read, so skip it
        // rather than leaving a file that is dead on arrival.
        guard !snapshot.accountUsername.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Drops the cache. Called on sign-out, since the next user must
    /// not inherit this one's list.
    public static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
