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
    @Setting(ProfileLayoutSettings.self) private var profileLayoutSettings
    @Setting(LinkPreviewSettings.self) private var linkPreviewSettings
    @Setting(ApolloAISettings.self) private var apolloAISettings
    @Setting(NotificationBackendSettings.self) private var notificationBackendSettings
    let accountManager: AccountManager

    @Setting(GeneralSettingsStore.storage) private var generalSettings
    @State private var showingRestoreSource = false
    @State private var showingLocalBackups = false
    @State private var showingRestoreImporter = false
    @State private var pendingRestoreURL: URL?
    @State private var showingClearCaches = false
    @State private var showingClearBanners = false
    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        List {
            setupSection
            featuresSection
            shortcutsSection
            dataSection
            advancedSection
            aboutSection
        }
        .apolloSettingsListAppearance()
        // Offsets the hub header's -21 top pull so the first header cap sits where
        // Apollo's does.
        .safeAreaPadding(.top, 7)
        .navigationTitle("Apollo Reborn")
        .navigationBarTitleDisplayModeIfAvailable()
    }

    // MARK: - Setup

    /// Setup: one row, subtitle "Reddit · Imgur · Giphy · Image Chest", `key.fill`
    /// on a systemGray tile.
    private var setupSection: some View {
        Section {
            SettingsNavigationRow {
                AccountsAPIKeysScreen(accountManager: accountManager)
            } label: {
                HubRow(
                    title: "Accounts & API Keys",
                    subtitle: "Reddit · Imgur · Giphy · Image Chest",
                    systemImage: "key.fill",
                    tint: .gray
                )
            }
            // No rule under the section's last row when a footer
            // follows.
            .apolloSettingsRowInsets(rule: false)
        } header: {
            Text("Setup")
                .apolloHubSectionHeader()
        } footer: {
            Text("Your Reddit sign-in credentials, plus optional Imgur, Giphy and Image Chest keys for uploads and GIFs.")
                    .apolloHubSectionFooter()
        }
    }

    // MARK: - Features

    /// Features, in order: Posts & Feeds, Comments, Media, Subreddits, Profile
    /// Layout, Interface, Rich Link Previews, Polls, Apollo AI.
    private var featuresSection: some View {
        Section {
            SettingsNavigationRow {
                PostsFeedsSettingsScreen()
            } label: {
                HubRow(title: "Posts & Feeds", systemImage: "newspaper.fill", tint: .orange)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                CommentsSettingsScreen()
            } label: {
                HubRow(title: "Comments", systemImage: "text.bubble.fill", tint: .green)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                MediaSettingsScreen()
            } label: {
                HubRow(title: "Media", systemImage: "play.rectangle.fill", tint: .pink)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                SubredditsSettingsScreen()
            } label: {
                HubRow(title: "Subreddits", systemImage: "person.3.fill", tint: .red)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                ProfileLayoutSettingsScreen()
            } label: {
                HubRow(
                    title: "Profile Layout",
                    subtitle: profileLayoutSettings.summaryText,
                    systemImage: "person.crop.circle.fill",
                    tint: .teal
                )
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                LinkPreviewSettingsScreen()
            } label: {
                // Status subtitle: "Body %@ · Comments %@ · %@" with the colour as
                // "#RRGGBB" or "Default color".
                HubRow(
                    title: "Rich Link Previews",
                    subtitle: {
                        let s = linkPreviewSettings
                        return "Body \(s.bodyDisplayMode.title) · Comments \(s.commentsDisplayMode.title) · \(s.displayColorText)"
                    }(),
                    systemImage: "link",
                    tint: .blue)
            }
            .apolloSettingsRowInsets()
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
                // Apollo's "Open in App" screen is a three-section hub (per-service app
                // toggles, the browser picker, and Link Companion); the picker is one row of
                // it.
                OpenInAppSettingsScreen()
            } label: {
                HubRow(title: "Open in App", systemImage: "arrow.up.forward.app.fill", tint: .blue)
            }
            .apolloSettingsRowInsets()
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
            SettingsNavigationRow {
                SavedCategoriesSettingsScreen()
            } label: {
                HubRow(title: "Saved Categories", systemImage: "book.closed.fill", tint: .green)
            }
            // Needed so the tile aligns with every other row's.
            .apolloSettingsRowInsets()
        } header: {
            Text("Shortcuts")
                .apolloHubSectionHeader()
        } footer: {
            Text("Quick links to settings that also live in their own sections and in Phoebus's settings.")
                    .apolloHubSectionFooter()
        }
    }

    // MARK: - Data

    /// Data, row for row: Backup Settings (a push, to the Automatic Backups
    /// screen), Restore Settings (an inline action that asks Local or Cloud), Clear
    /// Tweak Caches and Clear Custom Banners & Icons (inline confirmation alerts).
    private var dataSection: some View {
        Section {
            SettingsNavigationRow {
                AutomaticBackupSettingsScreen()
            } label: {
                HubRow(title: "Backup Settings", systemImage: "square.and.arrow.up.fill", tint: .blue, isAction: true,
                       showsChevron: true)
            }
            .apolloSettingsRowInsets()
            Button { showingRestoreSource = true } label: {
                HubRow(title: "Restore Settings", systemImage: "square.and.arrow.down.fill", tint: .green, isAction: true)
            }
            .apolloSettingsRowInsets()
            .buttonStyle(.plain)
            Button { showingClearCaches = true } label: {
                HubRow(title: "Clear Tweak Caches", systemImage: "trash.fill", tint: .red, isAction: true)
            }
            .apolloSettingsRowInsets()
            .buttonStyle(.plain)
            Button { showingClearBanners = true } label: {
                HubRow(title: "Clear Custom Banners & Icons", systemImage: "photo.fill", tint: .orange, isAction: true)
            }
            .apolloSettingsRowInsets()
            .buttonStyle(.plain)
        } header: {
            Text("Data")
                .apolloHubSectionHeader()
        } footer: {
            Text("Back up or restore your Reborn settings and API keys, or clear cached data.")
                    .apolloHubSectionFooter()
        }
        // Restore Settings: asks Local or Cloud.
        .confirmationDialog("Restore Settings", isPresented: $showingRestoreSource, titleVisibility: .visible) {
            Button("Local Backup") { showingLocalBackups = true }
            Button("Cloud Backup") { showingRestoreImporter = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose where the backup is stored.")
        }
        .settingsDestination(isPresented: $showingLocalBackups) {
            LocalBackupsScreen()
        }
        .apolloDocumentImporter(isPresented: $showingRestoreImporter, allowedContentTypes: BackupFileTypes.restorable) { result in
            if case .success(let url) = result { pendingRestoreURL = url }
        }
        .settingsDestination(isPresented: $pendingRestoreURL.isPresent()) {
            BackupRestoreSettingsScreen(importURL: pendingRestoreURL)
        }
        // Reborn's clear-all-caches copy.
        .alert("Clear Tweak Caches?", isPresented: $showingClearCaches) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await AvatarCache.shared.clear()
                    await LinkPreviewCache.shared.clear()
                    // The in-memory copies too, so nothing stale redraws.
                    await ImageCache.shared.removeAll()
                    await DownsampleCache.shared.removeAll()
                    await SubredditIconCache.shared.removeAll()
                    await AccountAgeCache.shared.removeAll()
                    URLCache.shared.removeAllCachedResponses()
                }
            }
        } message: {
            Text("This removes cached profile pictures, banners, link previews, badge books, and remembered banned-profile dismissals.")
        }
        // Reborn's clear-custom-banners copy.
        .alert("Clear Custom Banners & Icons?", isPresented: $showingClearBanners) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                // Custom art store (Reborn #266).
                SubredditCustomArtStore.shared.clearAll()
            }
        } message: {
            Text("Locally saved custom subreddit banner and icon images will be removed. Official Reddit art will show again where available.")
        }
    }

    // MARK: - Advanced

    /// Advanced. Notification Backend subtitle: the configured URL, else
    /// "Self-hosted apollo-backend · off". FLEX/debug rows are omitted.
    private var advancedSection: some View {
        Section {
            SettingsNavigationRow {
                NotificationBackendSettingsScreen()
            } label: {
                HubRow(
                    title: "Notification Backend",
                    subtitle: notificationBackendSubtitle,
                    systemImage: "bell.badge.fill",
                    tint: .red
                )
            }
            .apolloSettingsRowInsets()
        } header: {
            Text("Advanced")
                .apolloHubSectionHeader()
        } footer: {
            Text("Notification backend, developer tools and diagnostics.")
                    .apolloHubSectionFooter()
        }
    }
    /// Mirrors Reborn's subtitle block.
    private var notificationBackendSubtitle: String {
        let url = notificationBackendSettings.backendURL ?? ""
        return url.isEmpty ? "Self-hosted apollo-backend · off" : url
    }

    // MARK: - About

    /// About, in order: Feature Requests, Bug Reports, Open Source on GitHub,
    /// Apollo Reborn Subreddit, Thanks To, Privacy Policy, Version. Feature
    /// requests, bug reports and the GitHub row go to Phoebus's own repo.
    private var aboutSection: some View {
        Section {
            // A push to the in-app report form, not a link.
            SettingsNavigationRow {
                BugReportScreen()
            } label: {
                HStack {
                    HubEmojiRow(
                        title: "Bug Reports",
                        subtitle: "Report a problem on GitHub",
                        emoji: "🐛",
                        tint: .red)
                    Spacer()
                }
            }
            .apolloSettingsRowInsets()
        } header: {
            Text("About")
                .apolloHubSectionHeader()
        } footer: {
            Text("Request features, report bugs, or browse the source. Apollo Reborn is free and open source.")
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

/// About rows use emoji tiles rather than SF Symbols.
struct HubEmojiRow: View {
    let title: String
    var subtitle: String?
    let emoji: String
    let tint: Color
    var artwork: HubRowArtwork? = nil

    var body: some View {
        // Same measured geometry as `SettingsTile`; only the glyph is
        // an emoji rather than an SF Symbol.
        HStack(spacing: ApolloSettingsRowMetrics.hubTileToTitleGap) {
            ZStack {
                RoundedRectangle(cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius,
                                 style: .continuous)
                    .fill(tint)
                Text(emoji)
                    .font(.system(size: ApolloSettingsRowMetrics.tileGlyphPointSize))
                switch artwork {
                case .bundled(let name):
                    #if canImport(UIKit)
                    if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "StockIcons"),
                       let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius, style: .continuous))
                    }
                    #endif
                case .subreddit(let name, let repository):
                    HubSubredditIcon(subreddit: name, repository: repository)
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
                        // Long subtitles wrap, as in `HubRow`.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Explicit vertical padding rather than the `List`'s row inset, which is too
        // tight for a title alone and cramped once a subtitle wraps. Same
        // padding-around-content approach as `HubRow`.
        .padding(.vertical, (subtitle?.isEmpty == false)
                 ? ApolloSettingsRowMetrics.hubRowVerticalPadWithSubtitle
                 : ApolloSettingsRowMetrics.hubRowVerticalPadNoSubtitle)
    }
}

/// The subreddit row's tile: the subreddit's community icon filling the
/// rounded tile, as Apollo shows r/ApolloReborn's, over the emoji placeholder
/// until it loads. Feeds keep the classic `icon_img` only.
struct HubSubredditIcon: View {
    let subreddit: String
    let repository: RedditRepository
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: ApolloSettingsRowMetrics.tileCornerRadius, style: .continuous))
            } else {
                Color.clear
            }
        }
        .task(id: subreddit) {
            guard let info = try? await repository.fetchSubredditInfo(name: subreddit) else { return }
            let raw = [info.communityIcon, info.iconImage].compactMap { $0 }.first { !$0.isEmpty }
            url = raw.flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) }
        }
    }
}

/// An About row that opens an external URL.
/// Artwork for a hub row that is not an emoji tile.
enum HubRowArtwork {
    /// A PNG in `Resources/StockIcons`.
    case bundled(String)
    /// A subreddit's live icon, with the emoji tile as placeholder.
    case subreddit(String, RedditRepository)
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
