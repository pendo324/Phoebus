import SwiftUI
import UniformTypeIdentifiers
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Reborn's "Apollo Reborn" settings hub, with its seven sections in order:
/// Setup, Features, Shortcuts, Data, Advanced, Privacy, About.
///
/// Reborn's flat form is the *Accounts & API Keys* sub-screen the Setup section
/// discloses to. Section titles, footers, row order, titles, SF Symbol names and
/// tile colors follow Reborn.
public struct ApolloRebornHubScreen: View {
    @Setting(ApolloAISettings.self) private var apolloAISettings
    let accountManager: AccountManager

    @Setting(GeneralSettingsStore.storage) private var generalSettings
    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        List {
            featuresSection
            shortcutsSection
        }
        .apolloSettingsListAppearance()
        // Offsets the hub header's -21 top pull so the first header cap sits where
        // Apollo's does.
        .safeAreaPadding(.top, 7)
        .navigationTitle("Apollo Reborn")
        .navigationBarTitleDisplayModeIfAvailable()
    }

    // MARK: - Features

    /// Features, in order: Posts & Feeds, Comments, Media, Subreddits, Profile
    /// Layout, Interface, Rich Link Previews, Polls, Apollo AI.
    private var featuresSection: some View {
        Section {
            SettingsNavigationRow {
                PollsSettingsScreen(accountManager: accountManager)
            } label: {
                // "On" / "Off" from `UDKeyPollsEnabled`.
                HubRow(
                    title: "Polls",
                    subtitle: generalSettings.pollsEnabled ? "On" : "Off",
                    systemImage: "chart.bar.fill",
                    tint: .yellow)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                ApolloAISettingsScreen()
            } label: {
                HubRow(
                    title: "Phoebus AI",
                    subtitle: apolloAISettings.summaryText,
                    systemImage: "sparkles",
                    tint: .indigo
                )
            }
            .apolloSettingsRowInsets()
        } header: {
            Text("Features")
                .apolloHubSectionHeader()
        } footer: {
            Text("Fine-tune posts, comments, media, subreddits, profile layout and the interface.")
                    .apolloHubSectionFooter()
        }
    }

    // MARK: - Shortcuts

    /// Shortcuts, in order: Theme Manager, Open in App, Picture-in-Picture,
    /// Translation, Saved Categories, Tag Filters, Color Flairs. These are
    /// second entrances to screens that live elsewhere in settings, not new
    /// features.
    ///
    /// "Color Flairs" is a switch alias, not a disclosure: Appearance → Flair stays
    /// the canonical placement and the same preference changes from either.
    private var shortcutsSection: some View {
        Section {
            SettingsNavigationRow {
                PictureInPictureSettingsScreen()
            } label: {
                HubRow(title: "Picture-in-Picture", systemImage: "pip.fill", tint: .purple)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                TranslationSettingsScreen()
            } label: {
                HubRow(title: "Translation", systemImage: "character.bubble.fill", tint: .teal)
            }
            .apolloSettingsRowInsets()
        } header: {
            Text("Shortcuts")
                .apolloHubSectionHeader()
        } footer: {
            Text("Quick links to settings that also live in their own sections and in Phoebus's settings.")
                    .apolloHubSectionFooter()
        }
    }
}

// MARK: - Row components

/// The hub's disclosure row: a colored rounded tile with a white SF Symbol,
/// the title, and an optional wrapping gray subtitle underneath.
struct HubRow: View {
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
        // under the title. Reborn's image frame is wider than the root's, so the
        // title lands further right.
        //
        // Row height is vertical padding around the content, not a fixed box: a
        // 3-line subtitle needs a third tier a fixed height can't express.
        HStack(spacing: ApolloSettingsRowMetrics.hubTileToTitleGap) {
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
            }
            // The 7x12 #464648 disclosure, same as the root's rows
            // (`SettingsNavigationRow` hides the system one).
            if showsChevron ?? !isAction {
                ApolloSettingsChevron()
                    .padding(.leading, 15 - ApolloSettingsRowMetrics.hubTileToTitleGap)
            }
        }
        .padding(.vertical, (subtitle?.isEmpty == false)
                 ? ApolloSettingsRowMetrics.hubRowVerticalPadWithSubtitle
                 : ApolloSettingsRowMetrics.hubRowVerticalPadNoSubtitle)
    }
}
/// Shared colored-tile glyph used by every hub row: a 29x29 rounded rect at
/// cornerRadius 6 holding a white 16pt medium symbol.
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
