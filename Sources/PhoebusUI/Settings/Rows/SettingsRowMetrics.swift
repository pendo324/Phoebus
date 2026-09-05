import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The measured geometry and colours shared by every Apollo settings
/// row: the root Settings screen, the Apollo Reborn hub, and the
/// sub-screens that build rows by hand.
///
/// One shared metrics table used by all of them, so the hub and the
/// root screen agree on tile inset and row pitch.
public enum ApolloSettingsRowMetrics {
    /// A 29x29 rounded rect, cornerRadius 6, with a white 16pt medium
    /// SF Symbol centred in it.
    public static let tileSize: CGFloat = 29
    public static let tileCornerRadius: CGFloat = 6
    public static let tileGlyphPointSize: CGFloat = 16
    public static let tileGlyphWeight: Font.Weight = .medium

    /// Tile x 32..61, title x 77, a 16pt gap between them.
    public static let tileLeading: CGFloat = 32
    public static let titleLeading: CGFloat = 77
    public static let tileToTitleGap: CGFloat = 16
    /// The hub's titles land at x 77 like the root's.
    public static let hubTitleLeading: CGFloat = 77
    public static let hubTileToTitleGap: CGFloat = 16

    /// Rows are a dead-flat 52pt everywhere. Two-line hub rows measure
    /// 62pt.
    public static let rowHeight: CGFloat = 52
    public static let twoLineRowHeight: CGFloat = 62

    /// Hub row vertical padding, for rows whose content (title + N-line
    /// subtitle) sizes the row rather than an explicit height: the hub's cells
    /// self-size, so a three-line subtitle makes a taller row instead of
    /// clipping at 62pt.
    ///
    /// Target heights are 52pt with no subtitle, 62pt with one line, 82pt with
    /// two. The pad is tuned against SwiftUI's rendered title/subtitle line
    /// heights (taller than the glyph cap heights, by a different amount for the
    /// 17pt title and the 15pt subtitle), so one pad lands close across all three
    /// tiers.
    public static let hubRowVerticalPadNoSubtitle: CGFloat = 11.5
    public static let hubRowVerticalPadWithSubtitle: CGFloat = 11.5

    /// Separator x 76..361, rgb(50,54,64). It is a full 1pt, not a
    /// hairline: Apollo sets `separatorInset` but keeps UIKit's
    /// separator, which Reborn recolours. Feed and comment separators
    /// are one device pixel and keep their 1/3pt.
    public static let separatorLeading: CGFloat = 76
    public static let separatorTrailing: CGFloat = 32
    public static let separatorHeight: CGFloat = 1
    public static let separatorColorHex = "333640"

    /// Chevron 7x12 at x 353..360 in rgb(70,70,72).
    public static let chevronWidth: CGFloat = 7
    public static let chevronHeight: CGFloat = 12
    public static let chevronColorHex = "464648"

    /// 17pt regular title in #D0D1D6 (pure-black dark), 17pt detail in
    /// #61626A right-aligned ending at x 342.
    public static let titlePointSize: CGFloat = 17
    public static let titleColorHexDark = "D0D1D6"
    public static let detailPointSize: CGFloat = 17
    public static let detailColorHex = "61626A"

    /// Hub subtitle: 15pt regular #8D8D92, 4pt under the title.
    public static let subtitlePointSize: CGFloat = 15
    public static let subtitleColorHex = "8D8D92"
    public static let subtitleTopGap: CGFloat = 4

    /// Section header: 15pt semibold at x 33, with 23pt from the header's cap
    /// bottom to the first tile top.
    public static let headerPointSize: CGFloat = 15
    public static let headerLeading: CGFloat = 33
    public static let headerToFirstRow: CGFloat = 23

    /// Hub footer: 13pt regular #8D8D92 at x 32.3, 22pt below the
    /// separator, next header 30pt below it.
    public static let footerPointSize: CGFloat = 13
    public static let footerLeading: CGFloat = 32
    public static let footerTopGap: CGFloat = 22
    public static let footerToNextHeader: CGFloat = 30

    /// The gap between the pinned search field and the first row of
    /// section 0.
    public static let firstSectionTopPadding: CGFloat = 18

    /// The preview-card family of settings screens (Subreddit
    /// Sections, Feed Shortcuts, Subreddit Layout, Profile Layout)
    /// uses the same 15pt semibold section header as the hub.
    /// Colour and x are unchanged (#8D8D92 at x 33).
    public static let previewScreenHeaderPointSize: CGFloat = 15

    /// The hub's header/footer paddings are negative values tuned
    /// against the hub's own list, and do not transfer to a
    /// preview-card screen (the hub's own values would pull a
    /// following header up through the footer text above it).
    ///
    /// These screens take the plain list's own spacing instead,
    /// matching the measured 22pt-below-the-last-rule /
    /// 30pt-to-the-next-header pattern.
    public static let previewScreenFooterTopGap: CGFloat = -22
    public static let previewScreenFooterBottomGap: CGFloat = 0
    public static let previewScreenHeaderTopGap: CGFloat = 0
    public static let previewScreenHeaderBottomGap: CGFloat = -3.6
}

/// The hand-drawn disclosure chevron, at the measured 7x12 / #464648.
///
/// SwiftUI's own chevron in a plain List is the system grey and a
/// different size, so rows that draw their own accessory use this.
public struct ApolloSettingsChevron: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: ApolloSettingsRowMetrics.chevronHeight,
                          weight: .semibold))
            .foregroundStyle(Color.apolloSettingsChevron)
            .frame(width: ApolloSettingsRowMetrics.chevronWidth,
                   height: ApolloSettingsRowMetrics.chevronHeight)
            .accessibilityHidden(true)
    }
}

public extension Color {
    /// Settings headers, footers, subtitles and values: #666666 on light,
    /// #94969C on dark.
    static var apolloSettingsSecondary: Color { scheme(light: 0x666666, dark: 0x94969C) }

    /// The disclosure chevron: #C5C5C7 on light, #464648 on dark.
    static var apolloSettingsChevron: Color { scheme(light: 0xC5C5C7, dark: 0x464648) }

    private static func scheme(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
        #else
        return Color(hex: String(format: "%06X", dark))
        #endif
    }
}
