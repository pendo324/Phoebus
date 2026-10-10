import Foundation

/// Apollo's green "Stickied Post" banner. A post is stickied in its own
/// subreddit, so the banner shows only in that subreddit's feed: on Home,
/// Popular, All, Moderator or a multireddit it would mark posts pinned
/// somewhere the reader isn't.
public enum StickiedPostBanner {
    public static func shows(isStickied: Bool, isAggregateFeed: Bool) -> Bool {
        isStickied && !isAggregateFeed
    }
}
