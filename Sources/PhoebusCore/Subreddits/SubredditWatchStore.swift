import Foundation

/// Which subreddits the user has asked for post notifications on.
///
/// Apollo stored this server-side, which is gone. The selection is
/// persisted locally so it survives relaunch and a configured self-hosted
/// backend has a list to register.
public enum SubredditWatchStore {
    private static let key = "com.pendo324.Phoebus.watchedSubreddits"

    /// Stored lowercased, because Reddit treats subreddit names
    /// case-insensitively and the menu can be opened from links that
    /// differ in case from the canonical display name.
    public static func load() -> Set<String> {
        let names = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(names.map { $0.lowercased() })
    }

    public static func save(_ names: Set<String>) {
        UserDefaults.standard.set(Array(names).sorted(), forKey: key)
    }

    public static func isWatching(_ name: String) -> Bool {
        load().contains(name.lowercased())
    }
}
