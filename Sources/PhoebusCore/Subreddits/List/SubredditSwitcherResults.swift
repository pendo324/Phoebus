import Foundation

public struct SubredditSwitcherSection: Equatable, Sendable, Identifiable {
    public var title: String?
    public var names: [String]
    public var id: String { title ?? "" }

    public init(title: String?, names: [String]) {
        self.title = title
        self.names = names
    }
}

/// What the feed's title quick-switcher sheet lists. Reborn "Subreddit
/// Switcher Sheet" (#1313): an empty query shows the favorites, a typed one
/// shows local matches (favorites and subscriptions) ahead of Reddit's
/// autocomplete results.
public enum SubredditSwitcherResults {
    /// A 1-2 character prefix matches an enormous slice of Reddit, so the
    /// autocomplete request waits for this many characters.
    public static let minimumRemoteQueryLength = 3

    public static func sections(
        query: String,
        favorites: [String],
        local: [String],
        remote: [String]
    ) -> [SubredditSwitcherSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return favorites.isEmpty ? [] : [SubredditSwitcherSection(title: "Favorites", names: favorites)]
        }
        var seen = Set<String>()
        func unique(_ names: [String]) -> [String] {
            names.filter { seen.insert($0.lowercased()).inserted }
        }
        let matches = unique(favorites + local).filter { $0.localizedCaseInsensitiveContains(trimmed) }
        // Prefix matches first, each group keeping its incoming order.
        let prefixed = matches.filter { $0.range(of: trimmed, options: [.caseInsensitive, .anchored]) != nil }
        let rest = matches.filter { name in !prefixed.contains(name) }
        let names = prefixed + rest + unique(remote)
        return names.isEmpty ? [] : [SubredditSwitcherSection(title: nil, names: names)]
    }

    /// Favorites in display casing and the user's chosen order. `known` is
    /// the subscription list, which carries the real casing; `storedName`
    /// covers favorites that are not subscriptions.
    public static func favoriteNames(
        ordered: [String],
        known: [String],
        storedName: (String) -> String?,
        sortAlphabetically: Bool
    ) -> [String] {
        let byLowercase = Dictionary(known.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let names = ordered.map { byLowercase[$0.lowercased()] ?? storedName($0) ?? $0 }
        return FavoriteSubredditsStore.applySorting(names, name: { $0 }, sortAlphabetically: sortAlphabetically)
    }

    /// The subreddit a typed Return goes to: trimmed, without a leading
    /// `r/` or `/r/`. Nil for an empty entry.
    public static func destination(for typed: String) -> String? {
        var name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/r/", "r/"] where name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
            break
        }
        return name.isEmpty ? nil : name
    }
}
