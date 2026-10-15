import SwiftUI
import PhoebusCore

/// The category-row kit: the tile rows every category screen and the
/// settings root are built from, ported from Reborn's flat settings
/// form with its section footers.
///
/// A row is a coloured rounded tile with a white SF Symbol, the title,
/// and an optional wrapping gray subtitle underneath. Rows that write a
/// setting are switches; rows that open a URL draw a chevron of their
/// own; rows on the About screen use emoji tiles.

// MARK: - Disclosure rows

/// The disclosure row: a colored rounded tile with a white SF Symbol,
/// the title, and an optional wrapping gray subtitle underneath.
struct SettingsCategoryRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let tint: Color
    /// Action rows get the accent action colour, no underline, no
    /// chevron.
    var isAction: Bool = false
    /// Backup Settings is an action row that still pushes a screen, and
    /// keeps its chevron.
    var showsChevron: Bool? = nil
    /// A trailing value before the chevron, e.g. Crash Reports' count.
    var detail: String? = nil

    var body: some View {
        // Tile 29x29pt, title 17pt regular white, subtitle 15pt regular #8D8D92, 4pt
        // under the title.
        //
        // Row height is vertical padding around the content, not a fixed box: a
        // 3-line subtitle needs a third tier a fixed height can't express.
        HStack(spacing: ApolloSettingsRowMetrics.categoryTileToTitleGap) {
            SettingsTile(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: ApolloSettingsRowMetrics.subtitleTopGap) {
                Text(title)
                    .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                    .foregroundStyle(isAction ? AnyShapeStyle(Color.apolloAccent) : AnyShapeStyle(.foreground))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .apolloFont(size: ApolloSettingsRowMetrics.subtitlePointSize)
                        .foregroundStyle(Color.apolloSettingsSecondary)
                        // Long subtitles wrap.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Subtitles run close to the chevron. A Spacer sibling would offer the
            // wrappable subtitle only part of the leftover width and wrap early; a greedy
            // frame gives the text column everything up to the chevron.
            .frame(maxWidth: .infinity, alignment: .leading)
            if let detail {
                Text(detail)
                    .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                    .foregroundStyle(Color.apolloSettingsSecondary)
                    .lineLimit(1)
            }
            // The 7x12 #464648 disclosure, same as the root's rows
            // (`SettingsNavigationRow` hides the system one).
            if showsChevron ?? !isAction {
                ApolloSettingsChevron()
                    .padding(.leading, 15 - ApolloSettingsRowMetrics.categoryTileToTitleGap)
            }
        }
        .padding(.vertical, (subtitle?.isEmpty == false)
                 ? ApolloSettingsRowMetrics.categoryRowVerticalPadWithSubtitle
                 : ApolloSettingsRowMetrics.categoryRowVerticalPadNoSubtitle)
    }
}

/// Switch-alias row: same tile-to-title geometry as `SettingsCategoryRow`.
struct SettingsCategoryToggleRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    /// Same tile-to-title geometry as `SettingsCategoryRow`
    /// (`categoryTileToTitleGap`, with the title at the pinned title size).
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: ApolloSettingsRowMetrics.categoryTileToTitleGap) {
                SettingsTile(systemImage: systemImage, tint: tint)
                Text(title)
                    .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                    .lineLimit(1)
            }
        }
        // Geometry lives on the call sites (each applies `.apolloSettingsRowInsets()`
        // as the Section's direct child); this row owns only its tile + title layout.
        .frame(minHeight: ApolloSettingsRowMetrics.rowHeight)
    }
}

// MARK: - About rows

/// About rows use emoji tiles rather than SF Symbols.
struct SettingsCategoryEmojiRow: View {
    let title: String
    var subtitle: String?
    let emoji: String
    let tint: Color
    var artwork: SettingsCategoryRowArtwork? = nil

    var body: some View {
        // Same measured geometry as `SettingsTile`; only the glyph is
        // an emoji rather than an SF Symbol.
        HStack(spacing: ApolloSettingsRowMetrics.categoryTileToTitleGap) {
            ZStack {
                RoundedRectangle(cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius,
                                 style: .continuous)
                    .fill(tint)
                Text(emoji)
                    .font(.system(size: ApolloSettingsRowMetrics.tileGlyphPointSize))
                switch artwork {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: ApolloSettingsRowMetrics.tileGlyphPointSize,
                                      weight: ApolloSettingsRowMetrics.tileGlyphWeight))
                        .foregroundStyle(.white)
                case nil:
                    EmptyView()
                }
            }
            .frame(width: ApolloSettingsRowMetrics.tileSize,
                   height: ApolloSettingsRowMetrics.tileSize)
            VStack(alignment: .leading, spacing: ApolloSettingsRowMetrics.subtitleTopGap) {
                Text(title)
                    .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .apolloFont(size: ApolloSettingsRowMetrics.subtitlePointSize)
                        .foregroundStyle(Color.apolloSettingsSecondary)
                        // Long subtitles wrap, as in `SettingsCategoryRow`.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Explicit vertical padding rather than the `List`'s row inset, which is too
        // tight for a title alone and cramped once a subtitle wraps. Same
        // padding-around-content approach as `SettingsCategoryRow`.
        .padding(.vertical, (subtitle?.isEmpty == false)
                 ? ApolloSettingsRowMetrics.categoryRowVerticalPadWithSubtitle
                 : ApolloSettingsRowMetrics.categoryRowVerticalPadNoSubtitle)
    }
}

/// Artwork for a row that is not an emoji tile.
enum SettingsCategoryRowArtwork {
    /// An SF Symbol drawn on the row's tile.
    case symbol(String)
}

struct SettingsCategoryLinkRow: View {
    let title: String
    var subtitle: String?
    let emoji: String
    let tint: Color
    let url: String
    var artwork: SettingsCategoryRowArtwork? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let destination = URL(string: url) {
                openURL(destination)
            }
        } label: {
            HStack {
                SettingsCategoryEmojiRow(title: title, subtitle: subtitle, emoji: emoji,
                                         tint: tint, artwork: artwork)
                Spacer()
                ApolloSettingsChevron()
            }
        }
        .apolloSettingsRowInsets()
        .foregroundStyle(.primary)
    }
}

/// Shared colored-tile glyph used by every category row: a 29x29
/// rounded rect at cornerRadius 6 holding a white 16pt medium symbol.
struct SettingsTile: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius,
                             style: .continuous)
                .fill(tint)
            Image(systemName: systemImage)
                .font(.system(size: ApolloSettingsRowMetrics.tileGlyphPointSize,
                              weight: ApolloSettingsRowMetrics.tileGlyphWeight))
                .foregroundStyle(.white)
        }
        .frame(width: ApolloSettingsRowMetrics.tileSize,
               height: ApolloSettingsRowMetrics.tileSize)
    }
}
