import SwiftUI
import PhoebusCore

/// Reborn's Search Tab Sources (the Subreddits screen's last section), with
/// the search history Phoebus keeps beside them: where the Search tab gets
/// its trending and random subreddits, and whether it remembers searches.
public struct SearchSourcesSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(CustomSubredditSourceStore.storage) private var sources
    @Setting(SearchHistorySettings.self) private var searchHistory
    @State private var confirmingClearSearchHistory = false

    public init() {}

    public var body: some View {
        List {
            sourcesSection
            searchSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Search Sources")
        .navigationBarTitleDisplayModeIfAvailable()
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
            Text("History")
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