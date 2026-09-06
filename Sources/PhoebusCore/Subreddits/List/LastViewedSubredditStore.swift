import Foundation

/// Backs Apollo's "Remember Subreddit" setting
/// (`GeneralSettings.rememberSubredditToLoad`, key `RememberRedditToLoad`):
/// the Posts tab reopens whichever subreddit/multireddit/pseudo-feed
/// (Home/Popular/All/Moderator) was last open, rather than restarting at
/// `defaultRedditToLoad`. Reddit has no server-side "last viewed", so like
/// `RecentlyReadStore`/`ReadPostStore` this is a small local UserDefaults
/// record updated whenever a feed is shown.
///
/// A single flat value, not per-account, as in Apollo.
public enum LastViewedSubredditStore {
    private static let key = "com.pendo324.Phoebus.lastViewedFeedDestination"

    /// A destination `SubredditsRootScreen`/`MainTabView` can show. Mirrors
    /// `SubredditsRootDestination` (PhoebusUI, not Codable) with the minimal
    /// case set restorable on a cold launch: a bare path+name round-trips
    /// through UserDefaults.
    public enum Destination: Codable, Sendable, Equatable {
        case home
        case popular
        case all
        case moderator
        case subreddit(String)
        case multireddit(path: String, name: String)
    }

    /// Only `loadIfPresent` is used, so the fallback is never read.
    public static let storage = SettingsStore<Destination>(key: key) { .home }

    public static func record(_ destination: Destination) {
        storage.save(destination)
    }

    /// Convenience for feed screens, which only carry a bare
    /// subreddit/multireddit-path string.
    public static func recordSubreddit(_ name: String) {
        record(.subreddit(name))
    }

    public static func recordMultireddit(path: String, name: String) {
        record(.multireddit(path: path, name: name))
    }

    public static func load() -> Destination? { storage.loadIfPresent() }
}
