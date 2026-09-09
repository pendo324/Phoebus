import Foundation

/// Maps Apollo's named menu icons onto SF Symbols.
///
/// Apollo has 189 distinct `option-*` icons, one per menu action (21 for
/// sorting alone). The icon is how rows are told apart at a glance, so one
/// generic glyph per menu would lose that.
///
/// Apollo's artwork is not shipped. The `option-*` names say which concept each
/// row depicts and each maps to the closest system symbol; the names keep the
/// mapping auditable. Where a symbol is not obvious it is justified inline.
public enum ApolloMenuIcon {
    /// Apollo icon name -> SF Symbol.
    private static let mapping: [String: String] = [
        // Sorting. Each sort is its own concept, not a generic arrow. These six
        // match Apollo's "Sort by..." sheet: a trophy, a droplet, lines with an up
        // arrow, a clock, a rising bar chart and crossed arrows.
        "option-sort-best": "trophy",
        "option-sort-hot": "drop",
        "option-sort-new": "clock",
        "option-sort-top": "arrow.up.and.line.horizontal.and.arrow.down",
        "option-sort-rising": "chart.line.uptrend.xyaxis",
        "option-sort-controversial": "scissors",
        // The sheet shows only the six post sorts; these are inferred from their names.
        "option-sort-old": "hourglass",
        "option-sort-qa": "questionmark.circle",
        "option-sort-live": "dot.radiowaves.left.and.right",
        "option-sort-random": "shuffle",
        "option-sort-comments": "bubble.left.and.bubble.right",
        "option-sort-relevance": "scope",
        // Real modmail sorts (`moderatorModmailSortUnread` etc).
        "option-sort-unread": "envelope.badge",
        // Time ranges.
        "option-sort-hour": "clock",
        "option-sort-day": "sun.max",
        "option-sort-week": "calendar",
        "option-sort-month": "calendar",
        "option-sort-year": "calendar",
        "option-sort-all-time": "infinity",

        // Modmail / moderator actions.
        "option-mark-all-read": "envelope.open",
        "option-mark-read": "envelope.open",
        "option-mark-unread": "envelope.badge",
        "option-archive": "archivebox",
        "option-highlight": "star",
        "option-in-progress": "hourglass",
        "option-modmail-notifications": "bell",
        "option-mute-modmail": "bell.slash",
        "option-private-moderator-note": "lock.doc",
        "option-moderator": "shield",
        "option-automoderator": "gearshape.2",
        "option-mod-queue": "tray.full",
        "option-mod-log": "list.bullet.rectangle",
        "option-removal-reason": "exclamationmark.bubble",
        "option-report-card": "doc.text.magnifyingglass",
        "option-approve": "checkmark.shield",
        "option-spam": "xmark.bin",
        "option-ban": "nosign",
        "option-approved-submitters": "person.badge.shield.checkmark",
        "option-mute-notifications": "speaker.slash",
        "option-subreddit": "person.3",
        "option-author": "person",
        "option-filter": "line.3.horizontal.decrease",
        "option-filter-funnel": "line.3.horizontal.decrease.circle",
    ]

    /// The SF Symbol for a real Apollo icon name.
    ///
    /// Returns `nil` for a name with no mapping so a caller can fall back
    /// deliberately rather than render a wrong glyph.
    public static func symbol(_ apolloName: String) -> String? {
        mapping[apolloName]
    }

    /// Non-optional lookup with an explicit fallback.
    public static func symbol(_ apolloName: String, fallback: String) -> String {
        mapping[apolloName] ?? fallback
    }

    /// Every mapped name, for auditing.
    public static var mappedNames: [String] { mapping.keys.sorted() }
}
