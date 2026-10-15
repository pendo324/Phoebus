import SwiftUI
import PhoebusCore

/// The tile-row kit: the rows the settings root and About are built from,
/// ported from Reborn's flat settings form with its section footers.
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
    /// A trailing value before the chevron, e.g. Crash Reports' count.
    var detail: String? = nil
    /// Artwork in place of the SF Symbol tile; only App Icon has any (it
    /// shows the selected icon's own art, as Apollo does).
    var artwork: Image? = nil

    var body: some View {
        // Tile 29x29pt, title 17pt regular white, subtitle 15pt regular #8D8D92, 4pt
        // under the title.
        //
        // Row height is vertical padding around the content, not a fixed box: a
        // 3-line subtitle needs a third tier a fixed height can't express.
        HStack(spacing: ApolloSettingsRowMetrics.categoryTileToTitleGap) {
            Group {
                if let artwork {
                    artwork
                        .resizable()
                        .scaledToFill()
                        .frame(width: ApolloSettingsRowMetrics.tileSize,
                               height: ApolloSettingsRowMetrics.tileSize)
                        .clipShape(RoundedRectangle(
                            cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius,
                            style: .continuous))
                } else {
                    SettingsTile(systemImage: systemImage, tint: tint)
                }
            }
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
            if !isAction {
                ApolloSettingsChevron()
                    .padding(.leading, 15 - ApolloSettingsRowMetrics.categoryTileToTitleGap)
            }
        }
        .padding(.vertical, (subtitle?.isEmpty == false)
                 ? ApolloSettingsRowMetrics.categoryRowVerticalPadWithSubtitle
                 : ApolloSettingsRowMetrics.categoryRowVerticalPadNoSubtitle)
    }
}

// MARK: - Destructive action rows

/// A destructive action row on a settings screen, waiting to be
/// confirmed. The row only sets one of these on its tap; the work runs
/// from the alert's confirm button, so nothing is signed out or cleared
/// on a single tap.
struct SettingsCategoryAction: Identifiable {
    let id: String
    let title: String
    let message: String
    /// The confirm button's own title, the way each row names what it
    /// does ("Sign Out", "Clear").
    let confirmTitle: String
    let perform: () -> Void
}

extension View {
    /// Asks before a destructive action row runs it. Wording and button
    /// order match the app's other destructive confirmations
    /// ("Restore Settings?", "Delete Post?"): the destructive button
    /// leads, in red, with Cancel trailing.
    func apolloSettingsActionConfirmation(_ pending: Binding<SettingsCategoryAction?>,
                                         perform: @escaping (SettingsCategoryAction) -> Void) -> some View {
        alert(pending.wrappedValue?.title ?? "",
              isPresented: Binding(get: { pending.wrappedValue != nil },
                                   set: { if !$0 { pending.wrappedValue = nil } }),
              presenting: pending.wrappedValue) { action in
            Button(action.confirmTitle, role: .destructive) {
                pending.wrappedValue = nil
                perform(action)
            }
            Button("Cancel", role: .cancel) {
                pending.wrappedValue = nil
            }
        } message: { action in
            Text(action.message)
        }
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
