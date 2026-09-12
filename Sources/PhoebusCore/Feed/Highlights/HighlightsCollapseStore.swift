import Foundation

/// Per-subreddit collapsed state for the Community Highlights carousel,
/// remembered across navigation and launches. Tapping the header collapses
/// the carousel to its title bar.
///
/// It is persisted rather than held in view-local `@State`, since a
/// push/pop rebuilds the feed row tree and would reset it to expanded.
///
///   - the key is `CollapsedSubredditHighlights`, a plain `UserDefaults`
///     array of names (not a dictionary of booleans);
///   - lookups and writes lowercase the name, so `r/Apple` and `r/apple`
///     are one entry;
///   - it is runtime-mutated state in `standardUserDefaults`, deliberately
///     not part of the settings model.
public enum HighlightsCollapseStore {
    /// Reborn's collapsed-subreddits key, so an Apollo backup's value imports directly.
    public static let defaultsKey = "CollapsedSubredditHighlights"

    /// Whether the subreddit's highlights are collapsed.
    public static func isCollapsed(_ subreddit: String) -> Bool {
        let key = subreddit.lowercased()
        guard !key.isEmpty else { return false }
        return stored().contains(key)
    }

    /// Matches Reborn's collapsed-subreddit tracking.
    public static func setCollapsed(_ collapsed: Bool, for subreddit: String) {
        let key = subreddit.lowercased()
        guard !key.isEmpty else { return }
        var set = stored()
        if collapsed {
            set.insert(key)
        } else {
            set.remove(key)
        }
        // Written back as an array, matching the key's type so backups read it.
        UserDefaults.standard.set(Array(set), forKey: defaultsKey)
    }

    static func stored() -> Set<String> {
        let raw = UserDefaults.standard.array(forKey: defaultsKey) as? [String] ?? []
        return Set(raw)
    }
}
