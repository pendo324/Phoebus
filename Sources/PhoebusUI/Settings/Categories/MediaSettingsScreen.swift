import SwiftUI
import PhoebusCore

/// Media: how pictures, videos and GIFs behave. Reborn's Media screen
/// (Apollo Reborn → Features) minus its sharing and upload hosts, which are
/// Links & Sharing, with the media rows of Apollo's General screen and
/// Appearance's Show GIF Progress. Picture-in-Picture is a drill-down.
public struct MediaSettingsScreen: View {
    @Setting(GalleryAutoplaySettings.self) private var galleryAutoplaySettings
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(AppearanceSettingsStore.storage) private var appearance
    @Setting(VideoHoldSpeedStore.storage) private var holdSpeed
    @Setting(VideoPlaybackSettingsStore.storage) private var playback

    public init() {}

    public var body: some View {
        List {
            browsingSection
            playbackSection
            nsfwSection
            savingSection
            pictureInPictureSection
            networkSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.media.title)
        .navigationBarTitleDisplayModeIfAvailable()
    }

    private func galleryAutoplayBinding(_ keyPath: WritableKeyPath<GalleryAutoplaySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { galleryAutoplaySettings[keyPath: keyPath] },
            set: { value in GalleryAutoplayStore.storage.update { $0[keyPath: keyPath] = value } }
        )
    }

    private var browsingSection: some View {
        Section {
            Toggle("Swipe Through Feed Galleries", isOn: $settings.feedGalleryCarousel)
                    .apolloSearchRow("Swipe Through Feed Galleries")
            if settings.feedGalleryCarousel {
                Toggle("Swipe Past Gallery to Navigate", isOn: $settings.feedGalleryEdgeSwipeNav)
                    .apolloSearchRow("Swipe Past Gallery to Navigate")
            }
            Toggle("Swipe Up for Comments", isOn: $settings.swipeUpForComments)
                    .apolloSearchRow("Swipe Up for Comments")
            Toggle("Live Text Analyzer", isOn: $settings.liveTextAnalyzer)
                .apolloSearchRow("Live Text Analyzer")
            // Upstream #1142 rows, after Swipe Up for Comments.
            Toggle("Play Videos in Gallery View", isOn: galleryAutoplayBinding(\.playVideos))
                    .apolloSearchRow("Play Videos in Gallery View")
            Toggle("Play GIFs in Gallery View", isOn: galleryAutoplayBinding(\.playGIFs))
                    .apolloSearchRow("Play GIFs in Gallery View", lastBeforeFooter: true)
        } header: {
            Text("Browsing")
                .apolloSectionHeader()
        } footer: {
            Text("Swipe Through Feed Galleries: page through a gallery post's images without leaving the feed.\n\nSwipe Past Gallery to Navigate: at the first or last image, keep swiping to use your normal post swipes (vote, save, back or forward) instead of bouncing. From any image, a swipe that starts at the screen edge goes back or forward. Off by default.\n\nSwipe Up for Comments: in the fullscreen media viewer, swipe up or tap the comments button to open comments over the media. Off by default.\n\nPlay Videos / GIFs in Gallery View: video and GIF tiles play silently while they're on screen; tap one for the full-size viewer with sound. Paused in Low Power Mode.")
                    .apolloSectionFooter()
        }
    }

    /// NSFW Media: a 3-way override of the account's Reddit blur preference.
    private var nsfwSection: some View {
        Section {
            ApolloSettingsPicker("Blur NSFW Media", selection: $settings.nsfwBlurOverride,
                                 options: NSFWBlurOverride.allCases.map { $0 },
                                 display: { $0.displayName })
                    .apolloSearchRow("Blur NSFW Media", lastBeforeFooter: true)
        } header: {
            Text("NSFW Media")
                .apolloSectionHeader()
        } footer: {
            Text("\"Reddit Setting\" follows your account's \"Blur mature (18+) images and media\" preference; Always and Never override it on this device only.")
                    .apolloSectionFooter()
        }
    }

    /// Playback row order: Apollo's Autoplay GIFs/Videos, Unmute Videos When Opened,
    /// Show Controls and Video Deblurinator, then Reborn's Preferred GIF Fallback
    /// Format, Unmute Videos in Feed, Unmute Videos in Comments, Hold for Video Speed,
    /// Hold Speed (shown only while the switch above it is on), then Phoebus's Default
    /// Playback Speed, Loop Videos, Loop Videos with Audio and Seek Interval.
    private var playbackSection: some View {
        Section {
            ApolloSettingsPicker("Autoplay GIFs/Videos", selection: $settings.autoplayMode,
                                 options: AutoplayMode.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Autoplay GIFs/Videos")
            // Stock row: the fullscreen viewer's sound.
            ApolloSettingsPicker("Unmute Videos When Opened", selection: $settings.unmuteVideosWhenOpened,
                                 options: [UnmuteWhenOpenedSetting.remember, .always, .never],
                                 display: { $0.displayName })
                .apolloSearchRow("Unmute Videos When Opened")
            Toggle("Show Controls When Opened", isOn: $settings.showMediaViewerControlsWhenOpened)
                .apolloSearchRow("Show Controls When Opened")
            Toggle("Video Deblurinator", isOn: $settings.videoDeblurinatorEnabled)
                .apolloSearchRow("Video Deblurinator")
            ApolloSettingsPicker("Show GIF Progress", selection: Binding(
                                     get: { appearance.gifProgressLocation },
                                     set: { $appearance.gifProgressLocation.wrappedValue = $0 }),
                                 options: GIFProgressLocation.allCases.map { $0 },
                                 display: { $0.title })
                .apolloSearchRow("Show GIF Progress")
            ApolloSettingsPicker("Preferred GIF Fallback Format", selection: $settings.preferredGIFFallbackFormat,
                                 options: PreferredGIFFallbackFormat.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Preferred GIF Fallback Format")
            ApolloSettingsPicker("Unmute Videos in Feed", selection: $settings.unmuteFeedVideosMode,
                                 options: VideoUnmuteMode.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Unmute Videos in Feed")
            ApolloSettingsPicker("Unmute Videos in Comments", selection: $settings.unmuteCommentsVideosMode,
                                 options: VideoUnmuteMode.allCases.map { $0 },
                                 display: { $0.commentsDisplayName })
                .apolloSearchRow("Unmute Videos in Comments")
            Toggle("Hold for Video Speed", isOn: $holdSpeed.isEnabled)
                .apolloSearchRow("Hold for Video Speed")
            if holdSpeed.isEnabled {
                ApolloSettingsPicker("Hold Speed", selection: $holdSpeed.holdSpeed,
                                 options: Array(VideoHoldSpeedSettings.availableSpeeds),
                                 display: { $0 == $0.rounded() ? "\(Int($0))x" : "\($0)x" })
                    .apolloSearchRow("Hold Speed")
            }
            ApolloSettingsPicker("Default Playback Speed", selection: $playback.defaultSpeed,
                                 options: VideoPlaybackSettings.availableSpeeds,
                                 display: { VideoPlaybackSettings.speedTitle($0) })
                .apolloSearchRow("Default Playback Speed")
            Toggle("Loop Videos", isOn: $playback.loopVideos)
                .accessibilityIdentifier("media.loopVideos")
                .apolloSearchRow("Loop Videos")
            // Only meaningful under Phoebus's Loop Videos.
            Toggle("Loop Videos with Audio", isOn: $settings.loopVideosWithAudio)
                .disabled(!playback.loopVideos)
                .apolloSearchRow("Loop Videos with Audio")
            ApolloSettingsPicker("Seek Interval", selection: $playback.seekInterval,
                                 options: VideoPlaybackSettings.seekIntervals,
                                 display: { VideoPlaybackSettings.seekTitle($0) })
                .apolloSearchRow("Seek Interval", lastBeforeFooter: true)
        } header: {
            Text("Playback")
                .apolloSectionHeader()
        } footer: {
            Text("Unmute Videos in Feed: Never keeps feed videos silent, Always plays every one with sound, and Remember follows the last video you muted or unmuted yourself. Only one feed video plays sound at a time. Hold for Video Speed: press and hold the right side of a fullscreen video to play it at the chosen speed.\n\nDefault Playback Speed: every video starts at this speed; releasing Hold for Video Speed returns to it. Loop Videos: turn off to stop every video at its end, including silent ones; while on, videos with sound loop only with Loop Videos with Audio. Seek Interval: how far the fullscreen viewer's skip buttons jump.")
                .apolloSectionFooter()
        }
    }

    /// Where saved media goes and the format GIFs are saved as.
    private var savingSection: some View {
        Section {
            Toggle("Save to “Phoebus” Album", isOn: $settings.saveToApolloAlbum)
                .apolloSearchRow("Save to Phoebus Album")
            ApolloSettingsPicker("Download GIFs as...", selection: $settings.gifSaveFormat,
                                 options: GIFSaveFormat.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Download GIFs as")
        } header: {
            Text("Saving")
                .apolloSectionHeader()
        }
    }

    private var pictureInPictureSection: some View {
        Section {
            SettingsDrillDownRow(destination: .pictureInPicture)
        } header: {
            Text("Miniplayer")
                .apolloSectionHeader()
        }
    }

    /// Network: the footer names the fallback proxies (r.jina.ai, allorigins.win,
    /// codetabs.com); the feature exists for Imgur being blocked in the UK.
    private var networkSection: some View {
        Section {
            Toggle("Proxy Imgur via DuckDuckGo", isOn: $settings.proxyImgurViaDuckDuckGo)
                    .apolloSearchRow("Proxy Imgur via DuckDuckGo")
            if settings.proxyImgurViaDuckDuckGo {
                Toggle("Album Fallback Proxies", isOn: $settings.imgurAlbumFallbackProxies)
                    .apolloSearchRow("Album Fallback Proxies", lastBeforeFooter: true)
            }
        } header: {
            Text("Network")
                .apolloSectionHeader()
        } footer: {
            Text("Proxy Imgur via DuckDuckGo loads Imgur images through DuckDuckGo's image cache, so they still show where Imgur is blocked (like the UK).\n\nDuckDuckGo can't fetch an album's list of images, so Album Fallback Proxies gets it through public text proxies (r.jina.ai, allorigins.win, codetabs.com) instead. Only the album's Imgur address is sent to them. Turn it off and albums won't load while Imgur is blocked.\n\nVideos and uploads can't be proxied.")
                    .apolloSectionFooter()
        }
    }
}
