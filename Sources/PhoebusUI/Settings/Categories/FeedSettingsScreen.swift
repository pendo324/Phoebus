import SwiftUI
import PhoebusCore

/// Feed: how the feed loads and sorts, what counts as read, the posts it
/// remembers and keeps open, and the subreddit list. Apollo's General Posts
/// rows, its Mark Read / Hiding Posts and Subreddits screens and Reborn's
/// Posts & Feeds are its sections. Row titles and footers are verbatim.
public struct FeedSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(RecentlyReadSettingsStore.storage) private var recentlyRead
    @Setting(FloatingPostTabsSettingsStore.storage) private var floatingTabs

    public init() {}

    public var body: some View {
        List {
            FeedBehaviourSections()
            ReadPostsSections()
            recentlyReadSection
            floatingTabsSection
            interactivePostsSection
            SubredditListSections()
            searchSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.feed.title)
        .navigationBarTitleDisplayModeIfAvailable()
    }

    /// Recently Read Thumbnails (`UDKeyShowRecentlyReadThumbnails`), Recently Read
    /// Posts Limit (`sReadPostMaxCount`, numeric, placeholder "(unlimited)"), Hide
    /// NSFW in Recently Read (`UDKeyFilterNSFWRecentlyRead`).
    private var recentlyReadSection: some View {
        Section {
            Toggle("Recently Read Thumbnails", isOn: $recentlyRead.showThumbnails)
                    .apolloSearchRow("Recently Read Thumbnails")
            // Reborn's numeric field; empty means unlimited.
            HStack {
                Text("Recently Read Posts Limit")
                Spacer()
                TextField("(unlimited)", text: Binding(
                    get: { recentlyRead.maxCount.map(String.init) ?? "" },
                    set: { text in
                        let value = Int(text.filter(\.isNumber)).flatMap { $0 > 0 ? $0 : nil }
                        $recentlyRead.maxCount.wrappedValue = value
                        RecentlyReadStore.trim(to: value)
                    }))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 120)
            }
                    .apolloSearchRow("Recently Read Posts Limit")
            Toggle("Hide NSFW in Recently Read", isOn: $recentlyRead.filterNSFW)
                    .apolloSearchRow("Hide NSFW in Recently Read", lastBeforeFooter: true)
        } header: {
            Text("Recently Read")
                .apolloSectionHeader()
        } footer: {
            Text("Show thumbnails on posts you've already read, and cap how many Phoebus remembers.")
                    .apolloSectionFooter()
        }
    }

    /// Where the Search tab gets its trending and random subreddits, and its history.
    private var searchSection: some View {
        Section {
            SettingsDrillDownRow(destination: .searchSources, lastBeforeFooter: true)
        } header: {
            Text("Search")
                .apolloSectionHeader()
        }
    }

    /// Reborn's Feed rows that remain here: Feed Video Scrubber, Forget Forward Swipe
    /// After Scrolling, Live Interactive Posts and Show in Feed (shown only while the
    /// one above is on). Text Post Thumbnails and Info Row are Posts rows.
    private var interactivePostsSection: some View {
        Section {
            Toggle("Live Interactive Posts", isOn: $settings.devvitInteractivePosts)
                    .apolloSearchRow("Live Interactive Posts", lastBeforeFooter: !settings.devvitInteractivePosts)
            if settings.devvitInteractivePosts {
                Toggle("Show in Feed", isOn: $settings.devvitFeedWidgets)
                    .apolloSearchRow("Show in Feed", lastBeforeFooter: true)
            }
        } header: {
            Text("Interactive Posts")
                .apolloSectionHeader()
        } footer: {
            Text("Live Interactive Posts: shows live scores, polls, brackets and other interactive posts instead of placeholder text. Show in Feed adds them to the feed as well as comments.")
                    .apolloSectionFooter()
        }
    }

    /// Floating Post Tabs / Magnetic Stacking / Hold to Preview; the latter two are
    /// shown only while the master switch is on.
    private var floatingTabsSection: some View {
        Section {
            Toggle("Floating Post Tabs", isOn: $floatingTabs.enabled)
                    .apolloSearchRow("Floating Post Tabs")
            if floatingTabs.enabled {
                Toggle("Magnetic Stacking", isOn: $floatingTabs.magneticStacking)
                    .apolloSearchRow("Magnetic Stacking")
                Toggle("Hold to Preview", isOn: $floatingTabs.holdToPreview)
                    .apolloSearchRow("Hold to Preview", lastBeforeFooter: true)
            }
        } header: {
            Text("Floating Tabs")
                .apolloSectionHeader()
        } footer: {
            Text("Keep up to 5 posts open as floating bubbles. In a post, choose Keep in Floating Tab from the ••• menu. Tap a bubble to jump back to the post, or drag it onto the ✕ to close it. Magnetic Stacking piles bubbles together when you drop one on another. Hold to Preview shows the post while you hold a bubble down, and opens it when you let go.")
                    .apolloSectionFooter()
        }
    }
}
