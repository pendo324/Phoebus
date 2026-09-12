import Foundation
import PhoebusCore

/// Short-lived, in-memory cache of a feed screen's one-time fetches.
///
/// Swiping forward from the Subreddits root back into a feed re-sets
/// the `navigationDestination(item:)` binding, so SwiftUI builds a new
/// `FeedScreen` whose `@State` starts empty (a pop keeps the view
/// alive, so its own guards suffice). The cache therefore lives outside
/// the view, so the feed header and Community Highlights carousel don't
/// reload (Reborn #1037).
///
/// Memory-only and time-bounded: it is for undoing a back swipe, not
/// persistence, since a stale feed restored minutes later is worse than
/// a refetch, and pull-to-refresh always wins.
@MainActor
public final class FeedSnapshotCache {
    public static let shared = FeedSnapshotCache()

    public struct Snapshot {
        public var posts: [RedditPost]
        public var highlights: [RedditPost]
        /// Full-mode scraped carousel cards, rendered alongside the REST
        /// highlights.
        public var scrapedHighlights: [ScrapedHighlight]
        /// The subreddit's own metadata: banner, subscriber count,
        /// description, subscribe state. `checkModeratorStatus` fetches it
        /// alongside the moderator flag and the restore path skips that
        /// fetch, so it must travel in the snapshot.
        public var subredditInfo: RedditSubreddit?
        public var isModerator: Bool
        public var signedInUsername: String?
        public var afterToken: String?
        public var reachedEnd: Bool
        var storedAt: Date
    }

    /// How long a snapshot stays usable.
    ///
    /// Covers a back-then-forward swipe (seconds) without letting a
    /// feed reappear stale after the user has been away.
    private static let lifetime: TimeInterval = 120
    /// A handful of feeds, not an unbounded map: the user can only
    /// swipe back through so many.
    private static let capacity = 8

    private var snapshots: [String: Snapshot] = [:]
    private var order: [String] = []

    private init() {}

    public func store(
        key: String,
        posts: [RedditPost],
        highlights: [RedditPost],
        scrapedHighlights: [ScrapedHighlight],
        subredditInfo: RedditSubreddit?,
        isModerator: Bool,
        signedInUsername: String?,
        afterToken: String?,
        reachedEnd: Bool
    ) {
        guard !key.isEmpty else { return }
        snapshots[key] = Snapshot(posts: posts,
                                  highlights: highlights,
                                  scrapedHighlights: scrapedHighlights,
                                  subredditInfo: subredditInfo,
                                  isModerator: isModerator,
                                  signedInUsername: signedInUsername,
                                  afterToken: afterToken,
                                  reachedEnd: reachedEnd,
                                  storedAt: Date())
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.capacity, let oldest = order.first {
            order.removeFirst()
            snapshots.removeValue(forKey: oldest)
        }
    }

    public func snapshot(for key: String) -> Snapshot? {
        guard let snapshot = snapshots[key] else { return nil }
        guard Date().timeIntervalSince(snapshot.storedAt) < Self.lifetime else {
            snapshots.removeValue(forKey: key)
            order.removeAll { $0 == key }
            return nil
        }
        return snapshot
    }

    /// Drops a feed's snapshot, so the next appearance fetches fresh.
    /// Used by the deliberate reload paths.
    public func invalidate(key: String) {
        snapshots.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    public func removeAll() {
        snapshots.removeAll()
        order.removeAll()
    }
}
