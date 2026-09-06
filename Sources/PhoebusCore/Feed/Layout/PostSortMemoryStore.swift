import Foundation

/// Backs Apollo's "Remember Subreddit Sort (Posts)" setting
/// (`GeneralSettings.rememberPostsSortPerSubreddit`, key
/// `RememberRedditPostsSort`): the last sort (and, for Top/Controversial,
/// the time range) picked in a subreddit is reused when it reopens,
/// instead of the global Default Posts Sort.
///
/// The subreddit-only counterpart of `CommentSortMemoryStore`.
public enum PostSortMemoryStore {
    private static let sortKey = "Phoebus.postSortBySubreddit"
    private static let timeframeKey = "Phoebus.postSortTimeframeBySubreddit"

    /// Records the sort (and, when relevant, the time range) just picked for
    /// this subreddit. No-ops when the setting is off, so a stale entry does
    /// not reappear after re-enabling.
    public static func recordSortChange(subreddit: String, sort: String, timeframe: String?) {
        guard GeneralSettingsStore.load().rememberPostsSortPerSubreddit, !subreddit.isEmpty else { return }
        var sorts = sortMap()
        sorts[subreddit.lowercased()] = sort
        UserDefaults.standard.set(sorts, forKey: sortKey)
        if let timeframe {
            var timeframes = timeframeMap()
            timeframes[subreddit.lowercased()] = timeframe
            UserDefaults.standard.set(timeframes, forKey: timeframeKey)
        }
    }

    /// The remembered sort for a subreddit, if the setting is on and one was
    /// recorded; `nil` falls through to the caller's default chain. Never
    /// consulted for Home/All/Popular/Moderator/multireddits (empty `subreddit`).
    public static func rememberedSort(subreddit: String) -> String? {
        guard GeneralSettingsStore.load().rememberPostsSortPerSubreddit, !subreddit.isEmpty else { return nil }
        return sortMap()[subreddit.lowercased()]
    }

    public static func rememberedTimeframe(subreddit: String) -> String? {
        guard GeneralSettingsStore.load().rememberPostsSortPerSubreddit, !subreddit.isEmpty else { return nil }
        return timeframeMap()[subreddit.lowercased()]
    }

    private static func sortMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: sortKey) as? [String: String] ?? [:]
    }

    private static func timeframeMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: timeframeKey) as? [String: String] ?? [:]
    }
}
