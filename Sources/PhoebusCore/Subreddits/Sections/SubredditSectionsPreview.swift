import Foundation

/// The block list a Subreddit Sections preview should render: sample names,
/// colors, bands and heights follow Reborn's preview.
///
/// Kept in PhoebusCore, separate from the view, because the interesting
/// behaviour is in WHICH blocks exist and in what order, which is assertable
/// without rendering. The sample followed user keeps the SAME key
/// ("row.username") in both placements, so flipping Separate Followed Users
/// makes it slide between the FOLLOWING band and the U letter band rather
/// than disappearing and reappearing.
public struct SubredditSectionsPreviewBlock: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case band
        case row
    }

    /// Sample row tint colors.
    public enum Tint: String, Sendable, Equatable {
        case indigo
        case teal
        case green
        case orange
        case purple
    }

    public let kind: Kind
    /// Identity across renderings. A block whose key survives slides
    /// from its old place to its new one.
    public let key: String
    /// Appearance. A block whose signature changed cross-fades in place.
    public let signature: String
    public let title: String
    /// Rows only.
    public let subtitle: String?
    /// Rows only.
    public let tint: Tint?
    /// Rows only.
    public let starred: Bool
    /// Bands only: accent label + accent rule vs the classic grey
    /// band.
    public let modern: Bool
    public let height: Double

    public var id: String { key }

    /// Band heights and signature.
    static func band(key: String, title: String, modern: Bool) -> SubredditSectionsPreviewBlock {
        SubredditSectionsPreviewBlock(
            kind: .band,
            key: key,
            // Carries Reborn's `modern` flag (`SubredditSectionsSettings.usesModernDividers`)
            // so a band whose style changes cross-fades in place.
            signature: "band|\(title)|\(modern ? 1 : 0)",
            title: title,
            subtitle: nil,
            tint: nil,
            starred: false,
            modern: modern,
            height: bandHeight
        )
    }

    /// Row heights and signature: a row WITH a subtitle is taller (40pt vs 30pt).
    static func row(
        key: String,
        name: String,
        subtitle: String? = nil,
        tint: Tint,
        starred: Bool = false
    ) -> SubredditSectionsPreviewBlock {
        SubredditSectionsPreviewBlock(
            kind: .row,
            key: key,
            signature: "row|\(name)|\(subtitle ?? "")|\(starred ? 1 : 0)",
            title: name,
            subtitle: subtitle,
            tint: tint,
            starred: starred,
            modern: false,
            height: (subtitle?.isEmpty == false) ? detailRowHeight : rowHeight
        )
    }

    // Layout constants.
    public static let bandHeight: Double = 22
    public static let rowHeight: Double = 30
    public static let detailRowHeight: Double = 40
    public static let blockSpacing: Double = 3
    public static let verticalPadding: Double = 8
}

public enum SubredditSectionsPreview {
    /// The blocks the current settings call for.
    public static func blocks(for settings: SubredditSectionsSettings) -> [SubredditSectionsPreviewBlock] {
        let separate = settings.separateFollowedUsers
        // `modern` flag.
        let modern = settings.usesModernDividers
        // Sample multireddit subtitle.
        let multiredditSubtitle = settings.hideMultiredditDescriptions ? nil : "apolloapp, ios, swift"

        var blocks: [SubredditSectionsPreviewBlock] = []
        for token in settings.resolvedOrder {
            switch token {
            case .favorites:
                blocks.append(.band(key: "band.favorites", title: "FAVORITES", modern: modern))
                blocks.append(.row(key: "row.apolloapp", name: "apolloapp", tint: .indigo, starred: true))
            case .multireddits:
                blocks.append(.band(key: "band.multireddits", title: "MULTIREDDITS", modern: modern))
                blocks.append(.row(key: "row.multireddit", name: "My Multireddit", subtitle: multiredditSubtitle, tint: .teal))
            case .moderator:
                blocks.append(.band(key: "band.moderator", title: "MODERATOR", modern: modern))
                blocks.append(.row(key: "row.modclub", name: "modclub", tint: .green))
            case .following:
                // The FOLLOWING band only exists when the separation toggle is on.
                guard separate else { continue }
                blocks.append(.band(key: "band.following", title: "FOLLOWING", modern: modern))
                blocks.append(.row(key: "row.username", name: "u/username", tint: .orange))
            }
        }

        // Tail: where the A-Z list picks up. Without separation the followed user
        // sits in its letter section, with the SAME "row.username" key, so it
        // slides between the two places when the toggle flips.
        blocks.append(.band(key: "band.letter", title: "U", modern: modern))
        blocks.append(.row(key: "row.ukulele", name: "ukulele", tint: .purple))
        if !separate {
            blocks.append(.row(key: "row.username", name: "u/username", tint: .orange))
        }
        return blocks
    }

    /// Two paddings, every block's height, and spacing BETWEEN blocks only.
    public static func height(of blocks: [SubredditSectionsPreviewBlock]) -> Double {
        var height = 2 * SubredditSectionsPreviewBlock.verticalPadding
        for block in blocks { height += block.height }
        if blocks.count > 1 {
            height += Double(blocks.count - 1) * SubredditSectionsPreviewBlock.blockSpacing
        }
        return height
    }
}
