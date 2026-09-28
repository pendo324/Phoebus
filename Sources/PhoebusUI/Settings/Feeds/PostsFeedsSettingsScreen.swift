import SwiftUI
import PhoebusCore

/// Reborn's "Posts & Feeds" (Apollo Reborn -> Features): Recently Read, Feed,
/// Floating Tabs. Row titles and footers are verbatim.
public struct PostsFeedsSettingsScreen: View {
    @Setting(InfoRowSettings.self) private var infoRowSettings
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(RecentlyReadSettingsStore.storage) private var recentlyRead
    @Setting(FeedVideoScrubberStore.storage) private var scrubber
    @Setting(FloatingPostTabsSettingsStore.storage) private var floatingTabs

    public init() {}

    public var body: some View {
        List {
            recentlyReadSection
            feedSection
            floatingTabsSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Posts & Feeds")
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

    /// Row order: Text Post Thumbnails, Info Row (disclosure), Feed Video Scrubber,
    /// Forget Forward Swipe After Scrolling, Block Announcements, Live Interactive
    /// Posts, Show in Feed (shown only while the one above is on).
    private var feedSection: some View {
        Section {
            Toggle("Text Post Thumbnails", isOn: $settings.textPostThumbnailsEnabled)
                    .apolloSearchRow("Text Post Thumbnails")
            // Kept at x 33 like every other row rather than the default x 17.
            SettingsLink {
                InfoRowSettingsScreen()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Info Row")
                    Text(infoRowSettings.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .apolloSearchRow("Info Row")
            Toggle("Feed Video Scrubber", isOn: $scrubber.isEnabled)
                    .apolloSearchRow("Feed Video Scrubber")
            Toggle("Forget Forward Swipe After Scrolling", isOn: $settings.forwardSwipeForgetAfterScrolling)
                    .apolloSearchRow("Forget Forward Swipe After Scrolling")
            Toggle("Live Interactive Posts", isOn: $settings.devvitInteractivePosts)
                    .apolloSearchRow("Live Interactive Posts")
            if settings.devvitInteractivePosts {
                Toggle("Show in Feed", isOn: $settings.devvitFeedWidgets)
                    .apolloSearchRow("Show in Feed", lastBeforeFooter: true)
            }
        } header: {
            Text("Feed")
                .apolloSectionHeader()
        } footer: {
            Text("Feed Video Scrubber: drag the bar under a feed video to scrub it.\n\nForget Forward Swipe After Scrolling: once you've scrolled a few posts on, a forward swipe won't reopen the post you came back from.\n\nLive Interactive Posts: shows live scores, polls, brackets and other interactive posts instead of placeholder text. Show in Feed adds them to the feed as well as comments.")
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
