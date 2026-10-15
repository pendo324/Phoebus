import SwiftUI
import PhoebusCore

/// Reborn's Subreddits settings (Apollo Reborn → Features), as the Subreddit
/// List section of Feed: the list organization rows and the favorites
/// toggles, the layout drill-down and the icon choice. Row values are live
/// summaries via each settings model's `summaryText`.
struct SubredditListSections: View {
    @Setting(SubredditLayoutSettings.self) private var subredditLayoutSettings
    @Setting(GeneralSettingsStore.storage) private var settings
    @State private var perAccountFavorites = FavoriteSubredditsStore.perAccountEnabled
    @State private var showingAccountLoading = false
    @State private var confirmFavoriteChanges = FavoriteSubredditsStore.confirmChanges

    var body: some View {
        Section {
            listRows
            SettingsDrillDownRow(destination: .subredditLayout, value: subredditLayoutSettings.summaryText)
            Toggle("Use Community Icons", isOn: $settings.useCommunityIcons)
                .apolloSearchRow("Use Community Icons", lastBeforeFooter: true)
                .accessibilityIdentifier("subreddits.useCommunityIcons")
        } header: {
            Text("Subreddit List")
                .apolloSectionHeader()
        } footer: {
            Text("Use Community Icons shows each subreddit's current icon. Off matches Apollo, which only shows a subreddit's older-style icon and otherwise a letter badge.")
                .apolloSectionFooter()
        }
    }

    /// Reborn "Clean up Subreddits settings" (#1350): the list organization
    /// rows and the favorites toggles share one "Subreddit List" section.
    /// Feed Shortcuts detail format is `"{iconStyle} · {layoutStyle}"`. The
    /// Per-Account Favorites switch writes through
    /// `FavoriteSubredditsStore.perAccountEnabled`'s migration semantics.
    @ViewBuilder
    private var listRows: some View {
        SettingsDrillDownRow(
            destination: .feedShortcuts,
            value: "\(settings.subredditFeedIconStyle.displayName) · \(settings.subredditFeedLayout.displayName)")
        SettingsDrillDownRow(destination: .subredditSections)
        Toggle("Per-Account Favorites", isOn: Binding(get: { perAccountFavorites }, set: { on in
            if FavoriteSubredditsStore.setPerAccountEnabled(on) { perAccountFavorites = on } else { showingAccountLoading = true }
        }))
            .apolloSearchRow("Per-Account Favorites")
            .alert("Account Still Loading", isPresented: $showingAccountLoading) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Apollo could not safely identify the active account yet, so Per-Account Favorites stayed off. Wait a moment, then try again.")
            }
        // Reborn #1042, `SortFavoritesAlphabetically` / `FavoriteSortingByAccount`,
        // default off. Per-account when Per-Account Favorites is on.
        Toggle("Sort Favorites Alphabetically", isOn: sortFavoritesBinding)
            .apolloSearchRow("Sort Favorites Alphabetically")
            .accessibilityIdentifier("subreddits.sortFavoritesAlphabetically")
        // Reborn #1173, `ConfirmFavoriteToggle`, default off.
        Toggle("Confirm Favorite Changes", isOn: $confirmFavoriteChanges)
            .apolloSearchRow("Confirm Favorite Changes")
            .accessibilityIdentifier("subreddits.confirmFavoriteChanges")
            .onChange(of: confirmFavoriteChanges) { _, new in FavoriteSubredditsStore.confirmChanges = new }
    }

    /// Per-account resolution lives in `FavoriteSubredditsStore`.
    private var sortFavoritesBinding: Binding<Bool> {
        Binding(
            get: { FavoriteSubredditsStore.sortAlphabetically },
            set: { FavoriteSubredditsStore.sortAlphabetically = $0 }
        )
    }
}
