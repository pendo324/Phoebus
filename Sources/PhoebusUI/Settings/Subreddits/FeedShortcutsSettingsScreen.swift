import SwiftUI
import PhoebusCore

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
        .navigationTitle("Subreddit Shortcuts")
        .navigationBarTitleDisplayModeIfAvailable()
    }
}
