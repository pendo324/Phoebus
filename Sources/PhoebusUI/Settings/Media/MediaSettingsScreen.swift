import SwiftUI
import PhoebusCore

/// Reborn's Media screen (Apollo Reborn → Features). Sections in order: Browsing,
/// NSFW Media, Playback, Inline Media, Sharing, Uploads, Network, with upstream's
/// titles and footers. Several settings are also reachable from General, as in
/// Apollo.
public struct MediaSettingsScreen: View {
    @Setting(GalleryAutoplaySettings.self) private var galleryAutoplaySettings
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(VideoHoldSpeedStore.storage) private var holdSpeed
    @Setting(InlineMediaSettingsStore.storage) private var inlineMedia
    @Setting(CustomAPISettingsStore.storage) private var customAPI
    /// Reborn refuses an upload host without its API key.
    @State private var keyRequired: (title: String, message: String)?

    private func hasKey(_ key: String?) -> Bool {
        !(key ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    public init() {}

    public var body: some View {
        List {
            browsingSection
            nsfwSection
            playbackSection
            inlineMediaSection
            sharingSection
            uploadsSection
            networkSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Media")
        .alert(keyRequired?.title ?? "", isPresented: Binding(get: { keyRequired != nil }, set: { if !$0 { keyRequired = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(keyRequired?.message ?? "")
        }
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

    /// Playback row order: Preferred GIF Fallback Format, Unmute Videos in Feed,
    /// Unmute Videos in Comments, Hold for Video Speed, Hold Speed (shown only while
    /// the switch above it is on).
    private var playbackSection: some View {
        Section {
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
                    .apolloSearchRow("Hold Speed", lastBeforeFooter: true)
            }
        } header: {
            Text("Playback")
                .apolloSectionHeader()
        } footer: {
            Text("Unmute Videos in Feed: Never keeps feed videos silent, Always plays every one with sound, and Remember follows the last video you muted or unmuted yourself. Only one feed video plays sound at a time. Hold for Video Speed: press and hold the right side of a fullscreen video to play it at the chosen speed.")
                    .apolloSectionFooter()
        }
    }

    /// Disclosure to `InlineMediaSettingsScreen`.

    /// Status subtitle; observed so it is current on return from the screen.
    private var inlineMediaSummary: String {
        let m = inlineMedia
        return m.enabled ? "On · Autoplay \(m.autoplayMode.displayName) · Size \(m.size.rawValue)%" : "Off"
    }

    private var inlineMediaSection: some View {
        Section {
            SettingsLink {
                InlineMediaSettingsScreen()
            } label: {
                // e.g. "On · Autoplay Never · Size 100%".
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inline Media Settings")
                    Text(inlineMediaSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .apolloSearchRow("Inline Media Settings", lastBeforeFooter: true)
        } header: {
            Text("Inline Media")
                .apolloSectionHeader()
        } footer: {
            Text("Show images and play GIFs inline in the feed.")
                    .apolloSectionFooter()
        }
    }

    private var sharingSection: some View {
        Section {
            ApolloSettingsPicker("Share Link Host", selection: $settings.shareLinkHost,
                                 options: ShareLinkHost.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                    .apolloSearchRow("Share Link Host", lastBeforeFooter: true)
        } header: {
            Text("Sharing")
                .apolloSectionHeader()
        } footer: {
            Text("Choose which Reddit host Phoebus uses for shared post and comment links, including Copy Link and links included with shared media. fxReddit uses fxddit.com.")
                    .apolloSectionFooter()
        }
    }

    private var uploadsSection: some View {
        Section {
            ApolloSettingsPicker("Media Upload Host", selection: Binding(
                                     get: { settings.mediaUploadHost },
                                     set: { host in
                                         if host == .imgChest, !hasKey(customAPI.imgChestAPIKey) {
                                             keyRequired = ("Image Chest API Key Required",
                                                            "Add your Image Chest API key under Apollo Reborn → Accounts & API Keys first, then select Image Chest as the upload host.")
                                         } else {
                                             $settings.mediaUploadHost.wrappedValue = host
                                         }
                                     }),
                                 options: MediaUploadHost.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                    .apolloSearchRow("Media Upload Host")
            ApolloSettingsPicker("Comment Link Host", selection: Binding(
                                     get: { settings.commentLinkHost },
                                     set: { host in
                                         if host == .imgur, !hasKey(customAPI.imgurClientID) {
                                             keyRequired = ("Imgur API Key Required",
                                                            "Add your Imgur API key under Apollo Reborn → Accounts & API Keys first, then select Imgur as the comment link host.")
                                         } else if host == .imgChest, !hasKey(customAPI.imgChestAPIKey) {
                                             keyRequired = ("Image Chest API Key Required",
                                                            "Add your Image Chest API key under Apollo Reborn → Accounts & API Keys first, then select Image Chest as the comment link host.")
                                         } else {
                                             $settings.commentLinkHost.wrappedValue = host
                                         }
                                     }),
                                 options: CommentLinkHost.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                    .apolloSearchRow("Comment Link Host")
            if settings.commentLinkHost != .off {
                Toggle("Prefer Native Images", isOn: $settings.commentLinkPreferNative)
                    .apolloSearchRow("Prefer Native Images", lastBeforeFooter: true)
            }
        } header: {
            Text("Uploads")
                .apolloSectionHeader()
        } footer: {
            Text("Media Upload Host chooses where images you attach to posts and comments are uploaded.\n\nComment Link Host uploads comment images to Imgur or Image Chest and inserts a plain link, so they work in subreddits that don't allow image comments. Prefer Native Images uses Reddit's own image upload wherever the subreddit allows it, and the link host only where it doesn't.\n\nManage past uploads under Settings → General → Media → Manage Uploads.")
                    .apolloSectionFooter()
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
