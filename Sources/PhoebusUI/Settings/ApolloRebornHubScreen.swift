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
    @Setting(SiriContentSettings.enabled) private var siriIndexingEnabled
    let accountManager: AccountManager

    @Setting(GeneralSettingsStore.storage) private var generalSettings
    @State private var showingRestoreSource = false
    /// Re-read on appear and on any delete, as Reborn's row re-reads.
    @State private var crashReportCount = 0
    @State private var showingLocalBackups = false
    @State private var showingRestoreImporter = false
    @State private var pendingRestoreURL: URL?
    @State private var showingClearCaches = false
    @State private var showingClearBanners = false
    /// Stored as a disable flag, so the switch shows the inverse.
    @AppStorage("ApolloUsageHeartbeatDisabled") private var heartbeatDisabled = false
    private var anonymousInstallCount: Binding<Bool> {
        Binding(get: { !heartbeatDisabled }, set: { heartbeatDisabled = !$0 })
    }
    @State private var debugLogExport: URL?
    @State private var exportingLogs = false

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        List {
            setupSection
            if #available(iOS 27.0, *) { siriSection }
            featuresSection
            shortcutsSection
            dataSection
            advancedSection
            privacySection
            aboutSection
        }
        .apolloSettingsListAppearance()
        // Offsets the hub header's -21 top pull so the first header cap sits where
        // Apollo's does.
        .safeAreaPadding(.top, 7)
        .navigationTitle("Apollo Reborn")
        .onAppear { crashReportCount = CrashManager.shared.pendingReportIDs.count }
        .onReceive(NotificationCenter.default.publisher(for: .phoebusCrashReportsChanged)) { _ in
            crashReportCount = CrashManager.shared.pendingReportIDs.count
        }
        // On the screen, not the Advanced section: a sheet attached to a List
        // section never presents.
        .sheet(isPresented: $debugLogExport.isPresent()) {
            if let debugLogExport {
                ActivityShareSheet(items: [debugLogExport])
            }
        }
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

    // MARK: - Siri & Spotlight

    /// Reborn's opt-in Siri & Spotlight section (#1299), between Setup and
    /// Features. The index needs iOS 27, so the section is hidden before it.
    @available(iOS 27.0, *)
    private var siriSection: some View {
        Section {
            SettingsNavigationRow {
                SiriSpotlightSettingsScreen()
            } label: {
                HubRow(
                    title: "Siri & Spotlight",
                    subtitle: siriIndexingEnabled ? "On" : "Off",
                    systemImage: "sparkle.magnifyingglass",
                    tint: .purple)
            }
            // No rule under the section's last row when a footer follows.
            .apolloSettingsRowInsets(rule: false)
        } footer: {
            Text("Find Phoebus posts and communities with Siri, Spotlight and Shortcuts. Content indexing is off until you enable it.")
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
                InterfaceSettingsScreen()
            } label: {
                HubRow(title: "Interface", systemImage: "slider.horizontal.3", tint: .purple)
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
                ThemeSettingsScreen()
            } label: {
                HubRow(title: "Theme Manager", systemImage: "paintbrush.fill", tint: .indigo)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                // Apollo's "Open in App" screen: per-service app toggles and the
                // browser picker.
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
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                TagFiltersSettingsScreen()
            } label: {
                HubRow(title: "Tag Filters", systemImage: "tag.fill", tint: .orange)
            }
            .apolloSettingsRowInsets()
            HubToggleRow(
                title: "Color Flairs",
                systemImage: "paintpalette.fill",
                tint: .pink,
                isOn: $generalSettings.enableFlairColors
            )
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
            // `about.exportLogs`. Reborn's FLEX Debugging and its two 🔧 rows are left
            // out.
            Button { Task { await exportDebugLogs() } } label: {
                HubRow(title: exportingLogs ? "Preparing Logs…" : "Export Debug Logs",
                       systemImage: "square.and.arrow.up.on.square.fill", tint: .gray, isAction: true)
            }
            .apolloSettingsRowInsets()
            .buttonStyle(.plain)
        } header: {
            Text("Advanced")
                .apolloHubSectionHeader()
        } footer: {
            Text("Notification backend, developer tools and diagnostics.")
                    .apolloHubSectionFooter()
        }
    }

    /// Writes a plain-text log and hands it to the share sheet.
    private func exportDebugLogs() async {
        guard !exportingLogs else { return }
        exportingLogs = true
        defer { exportingLogs = false }
        debugLogExport = await DebugLogExport.write(accountCount: accountManager.accounts.count)
    }

    /// Mirrors Reborn's subtitle block.
    private var notificationBackendSubtitle: String {
        let url = notificationBackendSettings.backendURL ?? ""
        return url.isEmpty ? "Self-hosted apollo-backend · off" : url
    }

    // MARK: - Privacy

    /// Privacy: "Anonymous Install Count" (a switch, `waveform.path.ecg` on pink)
    /// and "Crash Reports" (a push, `bandage` on orange, with the pending count as
    /// its detail). The footer is an attributed string whose "privacy policy" is a
    /// link.

    private var privacySection: some View {
        Section {
            HubToggleRow(title: "Anonymous Install Count", systemImage: "waveform.path.ecg", tint: .pink,
                         isOn: anonymousInstallCount)
                .apolloSettingsRowInsets()
            SettingsNavigationRow {
                CrashReportsScreen()
            } label: {
                HubRow(title: "Crash Reports", systemImage: "bandage", tint: .orange,
                       detail: crashReportCount > 0 ? "\(crashReportCount)" : nil)
            }
            .apolloSettingsRowInsets()
        } header: {
            Text("Privacy")
                .apolloHubSectionHeader()
        } footer: {
            // Reborn's row, but honest about this build: it has no
            // heartbeat to send, so the switch changes nothing.
            Text("Phoebus does not send an install heartbeat; this switch is kept to match Apollo Reborn and has no effect. No Reddit activity, account details, or feature usage is collected.")
                .apolloHubSectionFooter()
        }
    }

    // MARK: - About

    /// About, in order: Feature Requests, Bug Reports, Open Source on GitHub,
    /// Apollo Reborn Subreddit, Thanks To, Privacy Policy, Version. Feature
    /// requests, bug reports and the GitHub row go to Phoebus's own repo.
    private var aboutSection: some View {
        Section {
            HubLinkRow(
                title: "Feature Requests",
                subtitle: "Suggest ideas for Phoebus",
                emoji: "💡",
                tint: .yellow,
                url: "https://github.com/pendo324/Phoebus/issues"
            )
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
            // The GitHub row carries the bundled GitHub mark, not an emoji tile; the
            // subreddit row shows r/ApolloReborn's own icon with 👽 as the placeholder.
            HubLinkRow(
                title: "Open Source on GitHub",
                subtitle: "@pendo324",
                emoji: "🐙",
                tint: .black,
                url: "https://github.com/pendo324/Phoebus",
                artwork: .bundled("reborn-github")
            )
            HubLinkRow(
                title: "Apollo Reborn Subreddit",
                subtitle: "r/ApolloReborn",
                emoji: "👽",
                tint: .orange,
                url: "https://reddit.com/r/ApolloReborn/",
                artwork: .subreddit("ApolloReborn", accountManager.repository)
            )
            SettingsNavigationRow {
                ThanksToScreen()
            } label: {
                // Leading-aligned like its neighbours.
                HStack {
                    HubEmojiRow(title: "Thanks To", emoji: "🙏", tint: .indigo)
                    Spacer()
                    ApolloSettingsChevron()
                }
            }
            .apolloSettingsRowInsets()
            HubLinkRow(
                title: "Privacy Policy",
                emoji: "🔒",
                tint: .green,
                url: "https://apolloreborn.app/privacy"
            )
            // A plain value row: no tile, title at the row's leading edge, "v3.7.1"-style
            // detail trailing.
            HStack {
                Text("Version")
                    .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                Spacer()
                Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                    .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                    .foregroundStyle(Color.apolloSettingsSecondary)
            }
            .apolloPlainSettingsRowInsets(rule: false)
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

/// Switch-alias row, used only by "Color Flairs" (see the Shortcuts doc).
struct HubToggleRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    /// Same tile-to-title geometry as `HubRow` (`hubTileToTitleGap`, with the title
    /// at the pinned title size).
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: ApolloSettingsRowMetrics.hubTileToTitleGap) {
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

struct HubLinkRow: View {
    let title: String
    var subtitle: String?
    let emoji: String
    let tint: Color
    let url: String
    var artwork: HubRowArtwork? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let destination = URL(string: url) {
                openURL(destination)
            }
        } label: {
            HStack {
                HubEmojiRow(title: title, subtitle: subtitle, emoji: emoji, tint: tint, artwork: artwork)
                Spacer()
                ApolloSettingsChevron()
            }
        }
        .apolloSettingsRowInsets()
        .foregroundStyle(.primary)
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
