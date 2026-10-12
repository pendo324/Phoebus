import Foundation

/// The author's flair in feed rows. Apollo showed it in the info row after the
/// name (`PostInfoNode.showAuthorFlair`); Phoebus keeps it there when it fits
/// and otherwise gives it its own line below the row, rather than truncating
/// the name or the stats.
public enum FeedAuthorFlair {
    public enum Placement: Equatable, Sendable {
        /// After the name, in the info row.
        case inline
        /// On its own line under the info row.
        case below
    }

    /// Show User Flair governs flair everywhere; Show Flair in Feeds then
    /// hides it in feed rows only.
    public static func isShown(showUserFlair: Bool, showFlairInFeeds: Bool, flairText: String?) -> Bool {
        guard showUserFlair, showFlairInFeeds, let flairText else { return false }
        return !flairText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Inline only when the name, the flair and the rest of the row all fit
    /// at their natural widths, `spacing` apart.
    public static func placement(authorWidth: Double, flairWidth: Double, restWidth: Double,
                                 spacing: Double, available: Double) -> Placement {
        authorWidth + spacing + flairWidth + spacing + restWidth <= available + 0.5 ? .inline : .below
    }

    /// The name's width on a row whose flair went below: its natural width,
    /// unless the rest of the row needs the room, as before flair was shown.
    public static func authorWidthBelow(authorWidth: Double, restWidth: Double,
                                        spacing: Double, available: Double) -> Double {
        max(0, min(authorWidth, available - spacing - restWidth))
    }
}
