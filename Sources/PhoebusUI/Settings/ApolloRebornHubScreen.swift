import SwiftUI
import UniformTypeIdentifiers
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// The settings hub, ported from Reborn's flat form, with its seven sections in order:
/// Setup, Features, Shortcuts, Data, Advanced, Privacy, About.
///
/// Reborn's flat form is the *Accounts & API Keys* sub-screen the Setup section
/// discloses to. Section titles, footers, row order, titles, SF Symbol names and
/// tile colors follow Reborn.
///
/// Its row components moved to `Rows/SettingsCategoryRows.swift`, which the
/// category screens share.
public struct ApolloRebornHubScreen: View {
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
    @Setting(AppUpdatePolicy.automaticChecks) private var automaticUpdateChecks
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
        .navigationTitle("Modern Settings")
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

    /// Setup: one row, subtitle "Reddit · Imgur · Giphy · Image Chest · Kagi", `key.fill`
    /// on a systemGray tile.
    private var setupSection: some View {
        Section {
            SettingsNavigationRow {
                AccountsAPIKeysScreen(accountManager: accountManager)
            } label: {
                SettingsCategoryRow(
                    title: "Accounts & API Keys",
                    subtitle: "Reddit · Imgur · Giphy · Image Chest · Kagi",
                    systemImage: "key.fill",
                    tint: .gray
                )
            }
            // No rule under the section's last row when a footer
            // follows.
            .apolloSettingsRowInsets(rule: false)
        } header: {
            Text("Setup")
                .apolloCategorySectionHeader()
        } footer: {
            Text("Your Reddit sign-in credentials, plus optional Imgur, Giphy and Image Chest keys for uploads and GIFs, and a Kagi Session Link for searching Reddit with Kagi.")
                    .apolloCategorySectionFooter()
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
                SettingsCategoryRow(
                    title: "Siri & Spotlight",
                    subtitle: siriIndexingEnabled ? "On" : "Off",
                    systemImage: "sparkle.magnifyingglass",
                    tint: .purple)
            }
            // No rule under the section's last row when a footer follows.
            .apolloSettingsRowInsets(rule: false)
        } footer: {
            Text("Find Phoebus posts and communities with Siri, Spotlight and Shortcuts. Content indexing is off until you enable it.")
                .apolloCategorySectionFooter()
        }
    }

    // MARK: - Features

    /// Features, in order: Posts & Feeds, Comments, Media, Subreddits, User
    /// Profiles, Interface, Rich Link Previews, Polls, Apollo AI.
    private var featuresSection: some View {
        Section {
            SettingsNavigationRow {
                PostsFeedsSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Posts & Feeds", systemImage: "newspaper.fill", tint: .orange)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                CommentsSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Comments", systemImage: "text.bubble.fill", tint: .green)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                MediaSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Media", systemImage: "play.rectangle.fill", tint: .pink)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                SubredditsSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Subreddits", systemImage: "person.3.fill", tint: .red)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                UserProfilesSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "User Profiles", systemImage: "person.crop.circle.fill", tint: .teal)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                InterfaceSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Interface", systemImage: "slider.horizontal.3", tint: .purple)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                LinkPreviewSettingsScreen()
            } label: {
                // Status subtitle: "Body %@ · Comments %@ · %@" with the colour as
                // "#RRGGBB" or "Default color".
                SettingsCategoryRow(
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
                // "On" / "Off" from `UDKeyPollsEnabled`, as a trailing value.
                SettingsCategoryRow(
                    title: "Polls",
                    systemImage: "chart.bar.fill",
                    tint: .yellow,
                    detail: generalSettings.pollsEnabled ? "On" : "Off")
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                ApolloAISettingsScreen()
            } label: {
                SettingsCategoryRow(
                    title: "Phoebus AI",
                    systemImage: "sparkles",
                    tint: .indigo,
                    detail: apolloAISettings.summaryText
                )
            }
            .apolloSettingsRowInsets()
        } header: {
            Text("Features")
                .apolloCategorySectionHeader()
        } footer: {
            Text("Fine-tune posts, comments, media, subreddits, profile layout and the interface.")
                    .apolloCategorySectionFooter()
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
                SettingsCategoryRow(title: "Theme Manager", systemImage: "paintbrush.fill", tint: .indigo)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                // Apollo's "Open in App" screen: per-service app toggles and the
                // browser picker.
                OpenInAppSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Open in App", systemImage: "arrow.up.forward.app.fill", tint: .blue)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                PictureInPictureSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Picture-in-Picture", systemImage: "pip.fill", tint: .purple)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                TranslationSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Translation", systemImage: "character.bubble.fill", tint: .teal)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                SavedCategoriesSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Saved Categories", systemImage: "book.closed.fill", tint: .green)
            }
            .apolloSettingsRowInsets()
            SettingsNavigationRow {
                TagFiltersSettingsScreen()
            } label: {
                SettingsCategoryRow(title: "Tag Filters", systemImage: "tag.fill", tint: .orange)
            }
            .apolloSettingsRowInsets()
            SettingsCategoryToggleRow(
                title: "Color Flairs",
                systemImage: "paintpalette.fill",
                tint: .pink,
                isOn: $generalSettings.enableFlairColors
            )
            // Needed so the tile aligns with every other row's.
            .apolloSettingsRowInsets()
        } header: {
            Text("Shortcuts")
                .apolloCategorySectionHeader()
        } footer: {
            Text("Quick links to settings that also live in their own sections and in Phoebus's settings.")
                    .apolloCategorySectionFooter()
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
                SettingsCategoryRow(title: "Backup Settings", systemImage: "square.and.arrow.up.fill", tint: .blue, isAction: true,
                       showsChevron: true)
            }
            .apolloSettingsRowInsets()
            Button { showingRestoreSource = true } label: {
                SettingsCategoryRow(title: "Restore Settings", systemImage: "square.and.arrow.down.fill", tint: .green, isAction: true)
            }
            .apolloSettingsRowInsets()
            .buttonStyle(.plain)
            Button { showingClearCaches = true } label: {
                SettingsCategoryRow(title: "Clear Tweak Caches", systemImage: "trash.fill", tint: .red, isAction: true)
            }
            .apolloSettingsRowInsets()
            .buttonStyle(.plain)
            Button { showingClearBanners = true } label: {
                SettingsCategoryRow(title: "Clear Custom Banners & Icons", systemImage: "photo.fill", tint: .orange, isAction: true)
            }
            .apolloSettingsRowInsets()
            .buttonStyle(.plain)
        } header: {
            Text("Data")
                .apolloCategorySectionHeader()
        } footer: {
            Text("Back up or restore your settings and API keys, or clear cached data.")
                    .apolloCategorySectionFooter()
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
                    DecodedImageCache.shared.removeAll()
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
                SettingsCategoryRow(
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
                SettingsCategoryRow(title: exportingLogs ? "Preparing Logs…" : "Export Debug Logs",
                       systemImage: "square.and.arrow.up.on.square.fill", tint: .gray, isAction: true)
            }
            .apolloSettingsRowInsets()
            .buttonStyle(.plain)
        } header: {
            Text("Advanced")
                .apolloCategorySectionHeader()
        } footer: {
            Text("Notification backend, developer tools and diagnostics.")
                    .apolloCategorySectionFooter()
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
    /// its detail). The footer is this app's privacy statement.

    private var privacySection: some View {
        Section {
            SettingsCategoryToggleRow(title: "Anonymous Install Count", systemImage: "waveform.path.ecg", tint: .pink,
                         isOn: anonymousInstallCount)
                .apolloSettingsRowInsets()
            // Reborn "In-App Update Prompt" (#1343). Only builds with a release
            // channel have an update source to check.
            if BuildChannel.current != nil {
                SettingsCategoryToggleRow(title: "Automatic Update Checks", systemImage: "arrow.down.circle", tint: .blue,
                             isOn: $automaticUpdateChecks.binding)
                    .apolloSettingsRowInsets()
                    .apolloSearchRow("Automatic Update Checks") // search: requires releaseChannel
                    .accessibilityIdentifier("settings.automaticUpdateChecks")
            }
            SettingsNavigationRow {
                CrashReportsScreen()
            } label: {
                SettingsCategoryRow(title: "Crash Reports", systemImage: "bandage", tint: .orange,
                       detail: crashReportCount > 0 ? "\(crashReportCount)" : nil)
            }
            .apolloSettingsRowInsets()
        } header: {
            Text("Privacy")
                .apolloCategorySectionHeader()
        } footer: {
            // The ported row, but honest about this build: there is no
            // heartbeat to send, so the switch changes nothing.
            Text("Phoebus does not send an install heartbeat, so this switch has no effect. No Reddit activity, account details, or feature usage is collected."
                 + (BuildChannel.current != nil ? " Update checks read Phoebus's AltStore source from GitHub once a day, and GitHub only sees your IP address." : ""))
                .apolloCategorySectionFooter()
        }
    }

    // MARK: - About

    /// About, in order: Feature Requests, Bug Reports, Open Source on GitHub,
    /// Version. Feature requests, bug reports and the GitHub row go to
    /// Phoebus's own repo. The ported privacy-policy row goes to the Privacy
    /// section's own footer, which describes what this app actually sends.
    private var aboutSection: some View {
        Section {
            SettingsCategoryLinkRow(
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
                    SettingsCategoryEmojiRow(
                        title: "Bug Reports",
                        subtitle: "Report a problem on GitHub",
                        emoji: "🐛",
                        tint: .red)
                    Spacer()
                }
            }
            .apolloSettingsRowInsets()
            // The GitHub row draws the SF Symbol mark on its tile.
            SettingsCategoryLinkRow(
                title: "Open Source on GitHub",
                subtitle: "@pendo324",
                emoji: "🐙",
                tint: .black,
                url: "https://github.com/pendo324/Phoebus",
                artwork: .symbol("chevron.left.forwardslash.chevron.right")
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
            CheckForUpdatesRow()
                .apolloPlainSettingsRowInsets(rule: BuildChannel.current != nil)
            if BuildChannel.current != nil {
                UpdateInstallerRow()
                    .apolloPlainSettingsRowInsets(rule: false)
            }
        } header: {
            Text("About")
                .apolloCategorySectionHeader()
        } footer: {
            Text("Request features, report bugs, or browse the source. Phoebus is free and open source.")
                    .apolloCategorySectionFooter()
        }
    }
}
