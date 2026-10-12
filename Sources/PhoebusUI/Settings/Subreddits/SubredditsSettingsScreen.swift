import SwiftUI
import PhoebusCore

/// Reborn's "Subreddits" settings screen (Apollo Reborn → Features): Subreddit
/// List, Subreddit Appearance and Search Tab Sources sections. Row values are
/// live summaries via each settings model's `summaryText`.
public struct SubredditsSettingsScreen: View {
    @Setting(SubredditSectionsSettings.self) private var subredditSectionsSettings
    @Setting(SubredditLayoutSettings.self) private var subredditLayoutSettings
    @Setting(GeneralSettingsStore.storage) private var settings
    @State private var perAccountFavorites = FavoriteSubredditsStore.perAccountEnabled
    @State private var showingAccountLoading = false
    @State private var confirmFavoriteChanges = FavoriteSubredditsStore.confirmChanges

    public init() {}

    @Setting(CustomSubredditSourceStore.storage) private var sources
    @Setting(SearchHistorySettings.self) private var searchHistory
    @State private var confirmingClearSearchHistory = false

    public var body: some View {
        List {
            listSection
            appearanceSection
            iconsSection
            sourcesSection
            searchSection
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

    /// Reborn "Clean up Subreddits settings" (#1350): the list organization
    /// rows and the favorites toggles share one "Subreddit List" section.
    /// Feed Shortcuts detail format is `"{iconStyle} · {layoutStyle}"`. The
    /// Per-Account Favorites switch writes through
    /// `FavoriteSubredditsStore.perAccountEnabled`'s migration semantics.
    private var listSection: some View {
        Section {
            SettingsLink {
                FeedShortcutsSettingsScreen()
            } label: {
                ValueRow(
                    title: "Feed Shortcuts",
                    value: "\(settings.subredditFeedIconStyle.displayName) · \(settings.subredditFeedLayout.displayName)"
                )
            }
            .apolloSearchRow("Feed Shortcuts")
            SettingsLink {
                SubredditSectionsSettingsScreen()
            } label: {
                Text("Subreddit Sections")
            }
            .apolloSearchRow("Subreddit Sections")
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
            Text("Subreddit List")
                .apolloSectionHeader()
        }
    }

    private var appearanceSection: some View {
        Section {
            SettingsLink {
                SubredditLayoutSettingsScreen()
            } label: {
                ValueRow(title: "Subreddit Layout", value: subredditLayoutSettings.summaryText)
            }
            .apolloSearchRow("Subreddit Layout", lastBeforeFooter: true)
        } header: {
            Text("Subreddit Appearance")
                .apolloSectionHeader()
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

    /// Per-account resolution lives in `FavoriteSubredditsStore`.
    private var sortFavoritesBinding: Binding<Bool> {
        Binding(
            get: { FavoriteSubredditsStore.sortAlphabetically },
            set: { FavoriteSubredditsStore.sortAlphabetically = $0 }
        )
    }

    /// Trending/Random sources, Show RandNSFW in Search and RandNSFW Source
    /// (Reborn's "Search Tab Sources"); each source field's placeholder is its
    /// default URL.
    private var sourcesSection: some View {
        Section {
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
            Text("Search Tab Sources")
                .apolloSectionHeader()
        }
    }
}

extension SubredditsSettingsScreen {
    /// Phoebus addition beside the Search tab's other sources: search history.
    /// Not in Apollo or Reborn.
    private var searchSection: some View {
        Section {
            Toggle("Save Search History", isOn: $searchHistory.saveHistory)
                .apolloSearchRow("Save Search History")
                .accessibilityIdentifier("subreddits.saveSearchHistory")
            Button("Clear Search History", role: .destructive) { confirmingClearSearchHistory = true }
                .apolloSearchRow("Clear Search History", lastBeforeFooter: true)
                .accessibilityIdentifier("subreddits.clearSearchHistory")
        } header: {
            Text("Search")
                .apolloSectionHeader()
        } footer: {
            Text("Recent searches show under the search field, for all of Reddit on the Search tab and per subreddit in a feed's search. Saved searches are kept until you remove them.")
                .apolloSectionFooter()
        }
        .alert("Clear Search History?", isPresented: $confirmingClearSearchHistory) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { SearchHistoryStore.clearAllRecent() }
        } message: {
            Text("Recent searches for every account are removed. Saved searches are kept.")
        }
    }
}

/// A title with a grey value on the trailing edge, before the disclosure
/// chevron the enclosing link draws.
struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .foregroundStyle(.secondary)
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
