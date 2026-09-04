import Foundation

/// Apollo's subreddit favoriting: starring a subreddit pins it to a
/// "Favorites" section at the top of the Subreddits root screen, above the
/// alphabetized subscription list.
///
/// Also backs Reborn's "Per-Account Favorites" toggle, surfaced on
/// `SubredditSectionsSettingsScreen`: an independent Favorites list for each
/// account; turning it off restores the shared list.
public enum FavoriteSubredditsStore {
    private static let globalKey = "com.pendo324.Phoebus.favoriteSubreddits"
    private static let perAccountEnabledKey = "com.pendo324.Phoebus.favoriteSubreddits.perAccountEnabled"

    private static func perAccountKey(for username: String) -> String {
        "com.pendo324.Phoebus.favoriteSubreddits.account.\(username.lowercased())"
    }

    /// Reborn "Confirm Favorite Changes" (#1173, `ConfirmFavoriteToggle`,
    /// default off): the Subreddits list star asks before changing.
    public static let confirmChangesKey = "ConfirmFavoriteToggle"
    public static var confirmChanges: Bool {
        get { UserDefaults.standard.bool(forKey: confirmChangesKey) }
        set { UserDefaults.standard.set(newValue, forKey: confirmChangesKey) }
    }

    /// The confirmation sheet's title and action, as Reborn words them.
    public static func confirmPrompt(name: String, isFavorite: Bool) -> (title: String, action: String) {
        isFavorite
            ? ("Remove r/\(name) from Favorites?", "Unfavorite")
            : ("Favorite r/\(name)?", "Favorite")
    }

    /// Whether favorites are partitioned per signed-in account. Turning it on
    /// copies the shared list to every existing account with no list of its
    /// own yet; new accounts start empty. Turning it off leaves the per-account
    /// lists in place and reads the shared list again.
    public static var perAccountEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: perAccountEnabledKey) }
        set { _ = setPerAccountEnabled(newValue) }
    }

    /// Like setting `perAccountEnabled`, but refuses to turn it on while the
    /// active account isn't known yet, as Reborn does ("Account Still
    /// Loading"). Returns whether the change applied.
    @discardableResult
    public static func setPerAccountEnabled(_ enabled: Bool) -> Bool {
        guard enabled != perAccountEnabled else { return true }
        if enabled {
            guard FavoriteSubredditsAccountContext.currentUsernameProvider() != nil else { return false }
            let shared = loadGlobalOnly()
            for username in FavoriteSubredditsAccountContext.allUsernamesProvider()
            where UserDefaults.standard.object(forKey: perAccountKey(for: username)) == nil {
                UserDefaults.standard.set(shared, forKey: perAccountKey(for: username))
            }
        }
        UserDefaults.standard.set(enabled, forKey: perAccountEnabledKey)
        return true
    }

    /// Reborn "Sort Favorites Alphabetically" (#1042). Default off: favorites
    /// keep Apollo's native order (the order they were favorited).
    ///
    /// Per-account like the favorites list itself, so turning it on for one
    /// account does not reorder another's.
    private static let sortAlphabeticallyKey = "com.pendo324.Phoebus.favoriteSubreddits.sortAlphabetically"
    private static let sortAlphabeticallyByAccountKey = "com.pendo324.Phoebus.favoriteSubreddits.sortAlphabeticallyByAccount"

    public static var sortAlphabetically: Bool {
        get {
            guard perAccountEnabled,
                  let username = FavoriteSubredditsAccountContext.currentUsernameProvider() else {
                return UserDefaults.standard.bool(forKey: sortAlphabeticallyKey)
            }
            let byAccount = UserDefaults.standard.dictionary(forKey: sortAlphabeticallyByAccountKey) as? [String: Bool] ?? [:]
            return byAccount[username.lowercased()] ?? false
        }
        set {
            guard perAccountEnabled,
                  let username = FavoriteSubredditsAccountContext.currentUsernameProvider() else {
                UserDefaults.standard.set(newValue, forKey: sortAlphabeticallyKey)
                return
            }
            var byAccount = UserDefaults.standard.dictionary(forKey: sortAlphabeticallyByAccountKey) as? [String: Bool] ?? [:]
            byAccount[username.lowercased()] = newValue
            UserDefaults.standard.set(byAccount, forKey: sortAlphabeticallyByAccountKey)
        }
    }

    /// Applies the sort to a favorites list: stable, using
    /// `localizedStandardCompare` (Finder-style, so "r/sub10" follows "r/sub9").
    /// When off, the list is returned untouched in native order.
    public static func applySorting<T>(_ items: [T], name: (T) -> String, sortAlphabetically: Bool) -> [T] {
        guard sortAlphabetically else { return items }
        return items.enumerated().sorted { lhs, rhs in
            let result = name(lhs.element).localizedStandardCompare(name(rhs.element))
            if result == .orderedSame { return lhs.offset < rhs.offset }  // stable
            return result == .orderedAscending
        }.map(\.element)
    }

    /// The active storage key given current mode + active account:
    /// the shared global key when per-account favorites are off, or
    /// have no resolvable active account (e.g. signed out); otherwise
    /// that account's own dedicated key.
    private static func activeKey() -> String {
        guard perAccountEnabled, let username = FavoriteSubredditsAccountContext.currentUsernameProvider() else {
            return globalKey
        }
        return perAccountKey(for: username)
    }

    private static func loadGlobalOnly() -> [String] {
        guard let array = UserDefaults.standard.stringArray(forKey: globalKey) else { return [] }
        return array.map { $0.lowercased() }
    }

    public static func load() -> Set<String> {
        Set(loadOrdered())
    }

    /// Favorites in Apollo's native order: the order they were
    /// favorited, or the order of an imported backup's
    /// `FavoriteSubreddits` array.
    public static func loadOrdered() -> [String] {
        guard let array = UserDefaults.standard.stringArray(forKey: activeKey()) else { return [] }
        var seen = Set<String>()
        return array.map { $0.lowercased() }.filter { seen.insert($0).inserted }
    }

    public static func isFavorite(_ subredditName: String) -> Bool {
        load().contains(subredditName.lowercased())
    }

    /// Adds at the end (Apollo appends a new favorite) or removes.
    public static func setFavorite(_ subredditName: String, isFavorite: Bool) {
        var current = loadOrdered()
        let name = subredditName.lowercased()
        current.removeAll { $0 == name }
        if isFavorite {
            current.append(name)
            rememberDisplayNames([subredditName])
        }
        UserDefaults.standard.set(current, forKey: activeKey())
    }

    /// Replaces the order with `names` (a backup's list), keeping any
    /// favorite not in it after them.
    public static func setOrder(_ names: [String]) {
        rememberDisplayNames(names)
        var seen = Set<String>()
        let ordered = names.map { $0.lowercased() }.filter { seen.insert($0).inserted }
        let rest = loadOrdered().filter { !seen.contains($0) }
        UserDefaults.standard.set(ordered + rest, forKey: activeKey())
    }

    private static let displayNamesKey = "com.pendo324.Phoebus.favoriteSubreddits.displayNames"

    /// The casing a favorite was saved with ("iOSProgramming"), for rows
    /// that have no subscription to supply it.
    public static func displayName(for lowercased: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: displayNamesKey) as? [String: String])?[lowercased]
    }

    private static func rememberDisplayNames(_ names: [String]) {
        var map = UserDefaults.standard.dictionary(forKey: displayNamesKey) as? [String: String] ?? [:]
        for name in names { map[name.lowercased()] = name }
        UserDefaults.standard.set(map, forKey: displayNamesKey)
    }

    /// A favorite's position in the native order, for sorting rows.
    public static func orderIndex() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: loadOrdered().enumerated().map { ($1, $0) })
    }

    public static func toggle(_ subredditName: String) {
        setFavorite(subredditName, isFavorite: !isFavorite(subredditName))
    }
}

/// Bridges `FavoriteSubredditsStore` (PhoebusCore, no account-model
/// dependency) to the active account identity owned by `AccountManager`
/// (PhoebusUI). `AccountManager` sets this provider at init and on every
/// account switch/add/remove.
public enum FavoriteSubredditsAccountContext {
    /// `nil` means signed out / no resolvable active account; favorites then
    /// use the shared global list.
    public nonisolated(unsafe) static var currentUsernameProvider: () -> String? = { nil }
    /// Every signed-in account's username.
    public nonisolated(unsafe) static var allUsernamesProvider: () -> [String] = {
        currentUsernameProvider().map { [$0] } ?? []
    }
}
