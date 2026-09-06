import Foundation

/// Backs Apollo's "Post Size Per Subreddit" setting
/// (`AppearanceSettings.rememberPostSizePerSubreddit`, key
/// `RememberRedditPostSize`): the last post display style picked in a
/// subreddit is reused when its feed reopens, instead of the global
/// `GeneralSettings.postDisplayStyle`.
///
/// Mirrors `PostSortMemoryStore`'s subreddit-keyed, setting-gated design.
public enum PostSizeMemoryStore {
    private static let key = "Phoebus.postSizeBySubreddit"

    /// Records the display style just picked for this subreddit via the feed's
    /// overflow menu. No-ops when the setting is off, or for aggregate
    /// feeds/multireddits (empty `subreddit`).
    /// True when the size was kept for this subreddit only; the caller
    /// then leaves the global size alone.
    @discardableResult
    public static func recordSizeChange(subreddit: String, style: PostDisplayStyle) -> Bool {
        guard AppearanceSettingsStore.load().rememberPostSizePerSubreddit, !subreddit.isEmpty else { return false }
        var sizes = sizeMap()
        sizes[subreddit.lowercased()] = style.rawValue
        UserDefaults.standard.set(sizes, forKey: key)
        return true
    }

    /// The remembered display style for a subreddit, if the setting is on and
    /// one was recorded; `nil` falls through to the caller's default chain.
    public static func rememberedStyle(subreddit: String) -> PostDisplayStyle? {
        guard AppearanceSettingsStore.load().rememberPostSizePerSubreddit, !subreddit.isEmpty else { return nil }
        guard let raw = sizeMap()[subreddit.lowercased()] else { return nil }
        return PostDisplayStyle(rawValue: raw)
    }

    private static func sizeMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
