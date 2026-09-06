import Foundation

/// Subreddits the user moderates but chose to hide from the Subreddits list
/// (Reborn's "Hide Moderated Subreddits", `HiddenModeratorSubreddits`).
///
/// Reddit offers no way to leave some dead subreddits you moderate, so they
/// would sit in the MODERATOR section forever. Hiding is purely a display
/// filter and never affects moderator powers.
///
/// Stored as an array of display names compared case-insensitively. Hidden
/// rows are filtered out of the MODERATOR section in normal mode and
/// reappear in Edit mode (faded, with a green plus) so they can be
/// unhidden inline.
public enum HiddenModeratorSubredditsStore {
    private static let key = "com.pendo324.Phoebus.hiddenModeratorSubreddits"

    public static func load(defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.stringArray(forKey: key) ?? []).map { $0.lowercased() })
    }

    public static func save(_ names: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(names).sorted(), forKey: key)
    }

    /// Case-insensitive membership.
    public static func isHidden(_ name: String, in hidden: Set<String>) -> Bool {
        hidden.contains(name.lowercased())
    }

    public static func toggle(_ name: String, defaults: UserDefaults = .standard) {
        var hidden = load(defaults: defaults)
        let key = name.lowercased()
        if hidden.contains(key) { hidden.remove(key) } else { hidden.insert(key) }
        save(hidden, defaults: defaults)
    }

    /// Applies the display filter, bypassed in Edit mode so hidden rows
    /// reappear and can be unhidden.
    public static func visible<T>(_ subreddits: [T], hidden: Set<String>, isEditing: Bool, name: (T) -> String) -> [T] {
        guard !isEditing, !hidden.isEmpty else { return subreddits }
        return subreddits.filter { !isHidden(name($0), in: hidden) }
    }
}
