import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Apollo's "Follow Thread" Live Activity, with Reborn's paired "Start Live
/// Activity" / "End Live Activity" menu rows.
///
/// Only the local half is implemented: starting it, updating it while the
/// app is open, and ending it. Apollo's push half posted the ActivityKit
/// push token to its own push server, which no longer exists, so comment
/// counts refresh while the app runs and then go stale.
public struct FollowThreadActivityState: Codable, Hashable, Sendable {
    /// The thread's comment count, the number the activity tracks.
    public var commentCount: Int
    /// The score, shown beside it.
    public var score: Int
    /// When the count was last refreshed, so the activity can say so
    /// rather than implying it is current.
    public var updatedAt: Date

    public init(commentCount: Int, score: Int, updatedAt: Date = Date()) {
        self.commentCount = commentCount
        self.score = score
        self.updatedAt = updatedAt
    }
}

/// The activity's fixed attributes.
public struct FollowThreadActivityAttributes: Codable, Hashable, Sendable {
    public var postID: String
    public var title: String
    public var subreddit: String

    public init(postID: String, title: String, subreddit: String) {
        self.postID = postID
        self.title = title
        self.subreddit = subreddit
    }
}

#if canImport(ActivityKit)
/// The ActivityKit-facing type. It lives in PhoebusCore because the
/// lock-screen view is built in the widget extension, and both targets must
/// share the same `ActivityAttributes` type to match the running activity.
@available(iOS 16.1, *)
public struct FollowThreadActivity: ActivityAttributes {
    public typealias ContentState = FollowThreadActivityState

    public var postID: String
    public var title: String
    public var subreddit: String

    public init(postID: String, title: String, subreddit: String) {
        self.postID = postID
        self.title = title
        self.subreddit = subreddit
    }
}
#endif

/// Tracks which threads have a running activity. Kept separate from
/// ActivityKit so the menu can show "Start" vs "End" where ActivityKit is
/// unavailable and so state survives the menu being rebuilt.
public enum FollowThreadActivityStore {
    public static let defaultsKey = "PhoebusFollowThreadActivities"

    public static func activePostIDs(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    public static func isActive(postID: String, _ defaults: UserDefaults = .standard) -> Bool {
        activePostIDs(defaults).contains(postID)
    }

    public static func setActive(postID: String, active: Bool,
                                 _ defaults: UserDefaults = .standard) {
        var ids = activePostIDs(defaults)
        if active { ids.insert(postID) } else { ids.remove(postID) }
        defaults.set(Array(ids).sorted(), forKey: defaultsKey)
    }
}
