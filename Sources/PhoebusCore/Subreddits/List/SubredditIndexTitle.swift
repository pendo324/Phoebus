import Foundation

/// The Subreddits list's right-edge section index. Four leading glyphs
/// (☰ U+2630, ★ U+2605, ○ U+25CB, ♜ U+265C) above "A", in Apollo's order.
public enum SubredditIndexTitle {
    /// Jumps to the feed shortcuts (Home / Popular / All / Moderator).
    public static let feedShortcuts = "\u{2630}"
    /// Jumps to the Favorites section.
    public static let favorites = "\u{2605}"
    /// Jumps to the Multireddits section.
    public static let multireddits = "\u{25CB}"
    /// Jumps to the Moderator section.
    public static let moderator = "\u{265C}"

    /// The four glyphs, in Apollo's own order.
    public static let leadingGlyphs = [feedShortcuts, favorites, multireddits, moderator]

    /// "A"..."Z".
    public static let letters: [String] = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .compactMap { UnicodeScalar($0).map(String.init) }

    /// The non-alphabetic bucket, which trails "Z" as "#".
    public static let hash = "#"

    /// The full strip: four glyphs, A-Z, then "#". A-Z is always complete
    /// regardless of whether every letter has subreddits, matching a real
    /// `UITableView` section index's fixed scrubbing scale.
    public static func all(includeHash: Bool = true) -> [String] {
        leadingGlyphs + letters + (includeHash ? [hash] : [])
    }

    /// Whether a title is one of the four leading glyphs.
    public static func isGlyph(_ title: String) -> Bool {
        leadingGlyphs.contains(title)
    }

    /// What VoiceOver should say for a title.
    ///
    /// "☰" and "♜" have no useful spoken form, so each glyph
    /// announces the section it jumps to instead of its character
    /// name ("trigram for heaven", "black chess rook").
    public static func accessibilityLabel(for title: String) -> String {
        switch title {
        case feedShortcuts: return "Feeds"
        case favorites: return "Favorites"
        case multireddits: return "Multireddits"
        case moderator: return "Moderator"
        default: return title
        }
    }
}

/// Maps an index title onto the list anchor it should scroll to. A letter
/// with no section of its own scrubs to the nearest following section,
/// like a `UITableView` section index.
public enum SubredditIndexResolver {
    /// - Parameters:
    ///   - title: the tapped/dragged index title.
    ///   - availableLetters: letters that actually head a section, ascending.
    /// - Returns: the anchor id to scroll to, or nil for an empty list.
    public static func anchor(for title: String,
                              availableLetters: [String]) -> String? {
        if SubredditIndexTitle.isGlyph(title) { return title }

        // Exact match first.
        if availableLetters.contains(title) { return title }

        // "#" trails the alphabet, so fall BACK to the last real
        // letter rather than forward past the end of the list.
        if title == SubredditIndexTitle.hash {
            return availableLetters.last
        }

        // Otherwise the next letter that exists, matching UIKit's
        // "nearest section at or after this title" scrubbing.
        if let next = availableLetters.first(where: { $0 >= title }) {
            return next
        }
        return availableLetters.last
    }
}

extension SubredditIndexTitle {
    /// Groups names by first letter for the A-Z sections, sorted
    /// case-insensitively, with names starting with a digit or symbol in
    /// a trailing "#" section (where the index puts it).
    public static func alphabetized<Item>(_ items: [Item], name: (Item) -> String) -> [(letter: String, items: [Item])] {
        let sorted = items.sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
        var groups: [String: [Item]] = [:]
        for item in sorted {
            let first = name(item).first.map(String.init)?.uppercased() ?? hash
            let key = first.first?.isLetter == true ? first : hash
            groups[key, default: []].append(item)
        }
        return groups.keys
            .sorted { ($0 == hash ? 1 : 0, $0) < ($1 == hash ? 1 : 0, $1) }
            .map { ($0, groups[$0]!) }
    }
}
