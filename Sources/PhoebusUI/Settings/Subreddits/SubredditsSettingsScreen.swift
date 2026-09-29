import SwiftUI
import PhoebusCore

/// Reborn's "Subreddits" settings screen (Apollo Reborn → Features): Main,
/// Favorites and Sources sections. Row subtitles are live summaries via each
/// settings model's `summaryText`.
public struct SubredditsSettingsScreen: View {
    @Setting(SubredditSectionsSettings.self) private var subredditSectionsSettings
    @Setting(SubredditLayoutSettings.self) private var subredditLayoutSettings
    @Setting(GeneralSettingsStore.storage) private var settings
    @State private var perAccountFavorites = FavoriteSubredditsStore.perAccountEnabled
    @State private var showingAccountLoading = false
    @State private var confirmFavoriteChanges = FavoriteSubredditsStore.confirmChanges

    public init() {}

    @Setting(CustomSubredditSourceStore.storage) private var sources

    public var body: some View {
        List {
            mainSection
            iconsSection
            favoritesSection
            sourcesSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Subreddits")
        .navigationBarTitleDisplayModeIfAvailable()
        .onChange(of: confirmFavoriteChanges) { _, new in FavoriteSubredditsStore.confirmChanges = new }
        .alert("Account Still Loading", isPresented: $showingAccountLoading) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Apollo could not safely identify the active account yet, so Per-Account Favorites stayed off. Wait a moment, then try again.")
        }
    }

    /// Row order: Feed Shortcuts, Subreddit Sections, Subreddit Layout.
    /// Feed Shortcuts subtitle format is `"{iconStyle} · {layoutStyle}"`.
    private var mainSection: some View {
        Section {
            SettingsLink {
                FeedShortcutsSettingsScreen()
            } label: {
                SubtitleRow(
                    title: "Feed Shortcuts",
                    subtitle: "\(settings.subredditFeedIconStyle.displayName) · \(settings.subredditFeedLayout.displayName)"
                )
            }
            .apolloSearchRow("Feed Shortcuts")
            SettingsLink {
                SubredditSectionsSettingsScreen()
            } label: {
                SubtitleRow(
                    title: "Subreddit Sections",
                    subtitle: subredditSectionsSettings.summaryText
                )
            }
            .apolloSearchRow("Subreddit Sections")
            SettingsLink {
                SubredditLayoutSettingsScreen()
            } label: {
                SubtitleRow(
                    title: "Subreddit Layout",
                    subtitle: subredditLayoutSettings.summaryText
                )
            }
            .apolloSearchRow("Subreddit Layout", lastBeforeFooter: true)
        } footer: {
            Text("Feed Shortcuts customizes the Home, Popular, All and Moderator Posts rows — their icons, layout, visibility and descriptions. Subreddit Sections arranges the rest of the subreddit list — section order, followed users, multireddit descriptions and the list style toggles live there. Subreddit Layout customizes subreddit pages.")
                    .apolloSectionFooter()
        }
    }

    /// Phoebus addition: which of a subreddit's two icons to draw.
    private var iconsSection: some View {
        Section {
            Toggle("Use Community Icons", isOn: $settings.useCommunityIcons)
                .apolloSearchRow("Use Community Icons", lastBeforeFooter: true)
                .accessibilityIdentifier("subreddits.useCommunityIcons")
        } header: {
            Text("Icons")
                .apolloSectionHeader()
        } footer: {
            Text("Shows each subreddit's current icon. Off matches Apollo, which only shows a subreddit's older-style icon and otherwise a letter badge.")
                .apolloSectionFooter()
        }
    }

    /// Footer documents the migration semantics implemented by
    /// `FavoriteSubredditsStore.perAccountEnabled`.
    private var favoritesSection: some View {
        Section {
            Toggle("Per-Account Favorites", isOn: Binding(get: { perAccountFavorites }, set: { on in
                if FavoriteSubredditsStore.setPerAccountEnabled(on) { perAccountFavorites = on } else { showingAccountLoading = true }
            }))
                    .apolloSearchRow("Per-Account Favorites")
            // Reborn #1042, `SortFavoritesAlphabetically` / `FavoriteSortingByAccount`,
            // default off. Per-account when Per-Account Favorites is on.
            Toggle("Sort Favorites Alphabetically", isOn: sortFavoritesBinding)
                    .apolloSearchRow("Sort Favorites Alphabetically")
                .accessibilityIdentifier("subreddits.sortFavoritesAlphabetically")
            // Reborn #1173, `ConfirmFavoriteToggle`, default off.
            Toggle("Confirm Favorite Changes", isOn: $confirmFavoriteChanges)
                    .apolloSearchRow("Confirm Favorite Changes", lastBeforeFooter: true)
                .accessibilityIdentifier("subreddits.confirmFavoriteChanges")
        } header: {
            Text("Favorites")
                .apolloSectionHeader()
        } footer: {
            Text("Per-Account Favorites saves a separate list and sorting preference for each account. First enable copies the current list to existing accounts; new accounts start empty. Turning it off restores the shared list.\nAlphabetical sorting keeps existing and new favorites in order. Turn it off to rearrange them manually while editing the subreddit list.\nConfirm Favorite Changes asks before adding or removing a favorite from the Subreddits list star.")
                    .apolloSectionFooter()
        }
    }

    /// Per-account resolution lives in `FavoriteSubredditsStore`.
    private var sortFavoritesBinding: Binding<Bool> {
        Binding(
            get: { FavoriteSubredditsStore.sortAlphabetically },
            set: { FavoriteSubredditsStore.sortAlphabetically = $0 }
        )
    }

    /// Trending/Random sources, Show RandNSFW in Search and RandNSFW Source;
    /// each source field's placeholder is its default URL.
    private var sourcesSection: some View {
        Section {
            // Explicit row insets to line up with the Favorites section above.
            ApolloSettingsTextFieldRow("Trending Subreddits Limit", placeholder: "(unlimited)", text: Binding(
                get: { settings.trendingSubredditsLimit > 0 ? String(settings.trendingSubredditsLimit) : "" },
                set: { v in $settings.update { $0.trendingSubredditsLimit = Int(v) ?? 0 } }), keyboard: .numberPad)
                .apolloPlainSettingsRowInsets()
            ApolloSettingsTextFieldRow("Trending Source", placeholder: CustomSubredditSourceSettings.defaultTrendingSourceURL, text: Binding(
                get: { sources.trendingSourceURL ?? "" },
                set: { $sources.trendingSourceURL.wrappedValue = $0.isEmpty ? nil : $0 }), keyboard: .URL)
                .apolloPlainSettingsRowInsets()
            ApolloSettingsTextFieldRow("Random Source", placeholder: CustomSubredditSourceSettings.defaultRandomSourceURL, text: Binding(
                get: { sources.randomSourceURL ?? "" },
                set: { $sources.randomSourceURL.wrappedValue = $0.isEmpty ? nil : $0 }), keyboard: .URL)
                .apolloPlainSettingsRowInsets()
            Toggle("Show RandNSFW in Search", isOn: Binding(
                get: { sources.showRandNSFWInSearch },
                set: { $sources.showRandNSFWInSearch.wrappedValue = $0 }))
                .apolloSearchRow("Show RandNSFW in Search")
            ApolloSettingsTextFieldRow("RandNSFW Source", placeholder: "(empty)", text: Binding(
                get: { sources.randomNSFWSourceURL ?? "" },
                set: { $sources.randomNSFWSourceURL.wrappedValue = $0.isEmpty ? nil : $0 }), keyboard: .URL)
                .apolloSearchRow("RandNSFW Source")
        } header: {
            Text("Sources")
                .apolloSectionHeader()
        }
    }
}

/// A title-over-gray-subtitle disclosure row.
struct SubtitleRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Feed Shortcuts: a visibility section and a controls section, under a live
/// preview card (`FeedShortcutsPreviewMock`) that reacts to visibility, Icon
/// Style, Feed Layout and Hide Feed Descriptions.
public struct FeedShortcutsSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings

    public init() {}

    public var body: some View {
        SettingsPreviewScreenLayout(screen: .feedShortcuts) {
            FeedShortcutsPreviewMock(settings: settings)
        } content: {
            Section {
                // Rows read positively ("Show Popular") while the stored keys are
                // negative (`UDKeyHideRPopularRedditList`), so each binding inverts.
                Toggle("Show Popular", isOn: Binding(
                    get: { !settings.hidePopularInSubredditList },
                    set: { on in $settings.update { $0.hidePopularInSubredditList = !on } }
                ))
                    .apolloSearchRow("Show Popular")
                Toggle("Show All Posts", isOn: Binding(
                    get: { !settings.hideAllInSubredditList },
                    set: { v in $settings.update { $0.hideAllInSubredditList = !v } }
                ))
                    .apolloSearchRow("Show All Posts")
                Toggle("Show Moderator Posts", isOn: Binding(
                    get: { !settings.hideModeratorInSubredditList },
                    set: { v in $settings.update { $0.hideModeratorInSubredditList = !v } }
                ))
                    .apolloSearchRow("Show Moderator Posts", lastBeforeFooter: true)
            } header: {
                Text("Visible Shortcuts")
                    .apolloPreviewScreenSectionHeader()
            } footer: {
                Text("Home is always shown. Choose which other shortcuts appear.")
                    .apolloPreviewScreenSectionFooter()
            }

            Section {
                ApolloSettingsPicker("Icon Style", selection: $settings.subredditFeedIconStyle,
                                 options: FeedIconStyle.allCases.map { $0 },
                                 display: { $0.displayName })
                    .apolloSearchRow("Icon Style")
                ApolloSettingsPicker("Feed Layout", selection: $settings.subredditFeedLayout,
                                 options: FeedShortcutLayout.allCases.map { $0 },
                                 display: { $0.displayName })
                    .apolloSearchRow("Feed Layout")
                // Reborn shows this only for the Rows layout.
                if settings.subredditFeedLayout == .rows {
                    Toggle("Hide Feed Descriptions", isOn: $settings.hideFeedDescriptions)
                        .apolloSearchRow("Hide Feed Descriptions")
                }
            } header: {
                Text("Appearance")
                    .apolloPreviewScreenSectionHeader()
            }
        }
        .navigationTitle("Feed Shortcuts")
        .navigationBarTitleDisplayModeIfAvailable()
    }
}
