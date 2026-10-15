import SwiftUI
import PhoebusCore

/// Posts: how a post looks in a feed, from Apollo's Appearance screen (its
/// post size, thumbnail, flair and award rows, with the Large and Compact
/// post sections), plus the Info Row and polls. Row titles are Apollo's,
/// backed by Apollo's UserDefaults keys.
///
/// Rows noted inline as WIRED are distinct Apollo settings implemented
/// against their render site. CONSOLIDATED rows read and write an existing
/// `GeneralSettings` field directly, as Apollo surfaces some settings from two
/// entrances (e.g. "Show User Profile Pictures" on General and Interface).
public struct PostsSettingsScreen: View {
    @Setting(AppearanceSettingsStore.storage) private var settings
    @Setting(GeneralSettingsStore.storage) private var generalSettings
    @Setting(VoteCountSettings.self) private var voteCounts
    @Setting(InfoRowSettings.self) private var infoRowSettings
    let accountManager: AccountManager

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        List {
            Section {
                ApolloSettingsPicker("Post Size", selection: $generalSettings.postDisplayStyle,
                                 options: PostDisplayStyle.allCases.map { $0 },
                                 display: { $0 == .compact ? "Compact" : "Large" })
                    .apolloSearchRow("Post Size")
                Toggle("Post Size Per Subreddit", isOn: binding(\.rememberPostSizePerSubreddit))
                    .apolloSearchRow("Post Size Per Subreddit")
                    .accessibilityIdentifier("appearance.postSizePerSubreddit")
                Toggle("Show Subreddit Icons", isOn: binding(\.showSubredditIconsForPosts))
                    .apolloSearchRow("Show Subreddit Icons")
                    .accessibilityIdentifier("appearance.showSubredditIconsForPosts")
                Toggle("Show Subreddit at Top", isOn: binding(\.showSubredditAtTop))
                    .apolloSearchRow("Show Subreddit at Top")
                    .accessibilityIdentifier("appearance.showSubredditAtTop")
                Toggle("Always Show Usernames", isOn: binding(\.alwaysShowUsernames))
                    .apolloSearchRow("Always Show Usernames")
                    .accessibilityIdentifier("appearance.alwaysShowUsernames")
                Toggle("Show Page Endings", isOn: binding(\.showPageEndings))
                    .apolloSearchRow("Show Page Endings")
                    .accessibilityIdentifier("appearance.showPageEndings")
                Toggle("Bold Post Titles", isOn: binding(\.boldPostTitles))
                    .apolloSearchRow("Bold Post Titles")
                    .accessibilityIdentifier("appearance.boldPostTitles")
            } header: {
                Text("Layout")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Show Voting Buttons", isOn: binding(\.largePostsShowVotingButtons))
                    .apolloSearchRow("Show Voting Buttons")
            } header: {
                Text("Large Posts")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Show Voting Buttons", isOn: binding(\.showVotingButtons))
                    // Second "Show Voting Buttons" (Large Posts has the other). Two rows cannot
                    // share one `SettingsSearchRowID`, so this copy is geometry only and search
                    // lands on the Large Posts row.
                    .apolloPlainSettingsRowInsets()
                    .accessibilityIdentifier("appearance.showVotingButtons")
                ApolloSettingsPicker("Voting Buttons Position", selection: binding(\.votingButtonsPosition),
                                 options: Array(AppearanceEdgePosition.allCases),
                                 display: { $0.title })
                    .apolloSearchRow("Voting Buttons Position")
                    .accessibilityIdentifier("appearance.votingButtonsPosition")
            } header: {
                Text("Compact Posts")
                    .apolloSectionHeader()
            }

            Section {
                ApolloSettingsPicker("Thumbnail Size", selection: $generalSettings.thumbnailSize,
                                 options: Array(ThumbnailSize.allCases),
                                 display: { $0.displayName })
                    .apolloSearchRow("Thumbnail Size")
                    .accessibilityIdentifier("appearance.thumbnailSize")
                ApolloSettingsPicker("Thumbnail Position", selection: thumbnailPositionBinding,
                                 options: AppearanceEdgePosition.allCases.map { $0 },
                                 display: { $0.title })
                    .apolloSearchRow("Thumbnail Position")
                    .accessibilityIdentifier("appearance.thumbnailPosition")
                Toggle("Show Self Post Thumbnails", isOn: binding(\.compactShowSelfPostThumbnails))
                    .apolloSearchRow("Show Self Post Thumbnails")
                    .accessibilityIdentifier("appearance.showSelfPostThumbnails")
                Toggle("Text Post Thumbnails", isOn: $generalSettings.textPostThumbnailsEnabled)
                    .apolloSearchRow("Text Post Thumbnails")
            } header: {
                Text("Thumbnails")
                    .apolloSectionHeader()
            }

            Section {
                Toggle("Post Flair", isOn: $generalSettings.showPostFlair)
                    .apolloSearchRow("Post Flair")
                Toggle("User Flair", isOn: $generalSettings.showUserFlair)
                    .apolloSearchRow("User Flair")
                // Phoebus-only: author flair in feed rows; User Flair still governs it.
                Toggle("Show Flair in Feeds", isOn: $generalSettings.showFlairInFeeds)
                    .disabled(!generalSettings.showUserFlair)
                    .apolloSearchRow("Show Flair in Feeds")
                    .accessibilityIdentifier("appearance.showFlairInFeeds")
                Toggle("Color Flairs", isOn: $generalSettings.enableFlairColors)
                    .apolloSearchRow("Color Flairs")
                Toggle("Show Awards", isOn: $generalSettings.showAwards)
                    .apolloSearchRow("Show Awards")
            } header: {
                Text("Flair & Awards")
                    .apolloSectionHeader()
            }

            Section {
                // Value on the trailing edge (Reborn #1351).
                SettingsDrillDownRow(destination: .infoRow, value: infoRowSettings.summaryText)
                Toggle("Hide Post Scores", isOn: $voteCounts.hidePostScores)
                    .apolloSearchRow("Hide Post Scores")
                    .accessibilityIdentifier("appearance.hidePostScores")
            } header: {
                Text("Post Info")
                    .apolloSectionHeader()
            }

            PollsSections(accountManager: accountManager)
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.posts.title)
        .navigationBarTitleDisplayModeIfAvailable()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppearanceSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                $settings[dynamicMember: keyPath].wrappedValue = $0
            }
        )
    }

    private var thumbnailPositionBinding: Binding<AppearanceEdgePosition> {
        Binding(
            get: { generalSettings.thumbnailPosition },
            set: { side in $generalSettings.update { $0.thumbnailPosition = side } }
        )
    }
}
