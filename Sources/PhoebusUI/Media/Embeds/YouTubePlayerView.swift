import SwiftUI
import PhoebusCore

/// Plays a YouTube video inline with the app's own controls: the YouTube
/// IFrame Player API in a web view with YouTube's controls off, driven by the
/// same control panel as every other video (`YouTubePlayerBridge`). Like
/// Apollo it needs no API key. A video that can't play inline (embedding
/// disabled, removed) becomes a tap-to-open poster instead of YouTube's error
/// page.
public struct YouTubePlayerView: View {
    let videoID: String
    let startSeconds: Int
    /// The post and its context, for the fullscreen viewer's chrome.
    var votePost: RedditPost?
    var repository: RedditRepository?
    var onJumpToComments: (() -> Void)?
    @State private var unplayableInline = false
    @Environment(\.openURL) private var openURL
    @Setting(GeneralSettingsStore.storage) private var settings

    public init(videoID: String, startSeconds: Int = 0, votePost: RedditPost? = nil,
                repository: RedditRepository? = nil, onJumpToComments: (() -> Void)? = nil) {
        self.videoID = videoID
        self.startSeconds = startSeconds
        self.votePost = votePost
        self.repository = repository
        self.onJumpToComments = onJumpToComments
    }

    public var body: some View {
        Group {
            // Apollo's OpenVideosInYouTubeApp setting: hands off to the native
            // YouTube app (via Universal Links) instead of playing inline.
            if settings.openVideosInYouTubeApp {
                openInYouTubeAppPrompt(caption: nil)
            } else if unplayableInline {
                openInYouTubeAppPrompt(caption: "Can't play here. Watch on YouTube")
            } else {
                YouTubeInlinePlayer(videoID: videoID, startSeconds: startSeconds, votePost: votePost,
                                    repository: repository, onJumpToComments: onJumpToComments) {
                    unplayableInline = true
                }
            }
        }
    }

    /// The video's poster frame with a play button, shown when "Open Videos in
    /// YouTube App" is on. A poster rather than text, because the setting means
    /// "open in the app when I tap it": nothing launches until the user taps.
    private func openInYouTubeAppPrompt(caption: String?) -> some View {
        Button {
            if let url = YouTubeURLParser.nativeAppURL(forVideoID: videoID) {
                openURL(url)
            }
        } label: {
            YouTubePoster(videoID: videoID, caption: caption)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play on YouTube")
        .accessibilityIdentifier("youtube.openInApp")
    }

    /// Extracts an 11-character YouTube video ID from any common YouTube URL
    /// shape. Delegates to PhoebusCore's `YouTubeURLParser` so it is testable on
    /// Linux.
    public nonisolated static func extractVideoID(from url: URL) -> String? {
        YouTubeURLParser.extractVideoID(from: url)
    }
}

/// The video's poster frame with a play glyph, and optionally a line of text
/// along the bottom.
private struct YouTubePoster: View {
    let videoID: String
    let caption: String?

    var body: some View {
        ZStack {
            YouTubeThumbnail(videoID: videoID)
            // Play glyph over a scrim, so it stays legible on a
            // bright thumbnail.
            Image(systemName: "play.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 6)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipped()
        .overlay(alignment: .bottom) {
            if let caption {
                Text(caption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .padding(.bottom, 10)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct YouTubeThumbnail: View {
    let videoID: String

    var body: some View {
        if let thumbnail = YouTubeURLParser.thumbnailURL(forVideoID: videoID) {
            CachedAsyncImage(url: thumbnail, contentMode: .fill)
        } else {
            Color.black.opacity(0.08)
        }
    }
}

/// A YouTube video on the post screen: the poster with a play button when
/// autoplay is off, otherwise the player, dressed as an inline v.redd.it
/// video: mute badge, Feed Video Scrubber and speed menu over the picture,
/// no control panel. A tap on the picture opens the fullscreen viewer, which
/// shows the same web view; scrolled out of view while playing, it moves into the floating
/// PiP card (Reborn's "Enable In-App PiP").
struct YouTubeInlinePlayer: View {
    let videoID: String
    let votePost: RedditPost?
    let repository: RedditRepository?
    let onJumpToComments: (() -> Void)?
    let onUnplayable: () -> Void
    @Setting(GeneralSettings.self) private var generalSettings
    @StateObject private var bridge: YouTubePlayerBridge
    /// This view's id for the audio session's holders.
    @State private var holderID = "youtube." + UUID().uuidString
    @State private var userStarted = false
    @State private var showingFullscreen = false
    @State private var playbackSpeed: Float = 1
    @Setting(FeedVideoScrubberStore.storage) private var scrubberSettings
    @Environment(\.floatingPiPSourceEnabled) private var floatingPiPSourceEnabled
    @Environment(\.floatingPiPScreenID) private var floatingPiPScreenID
    @Environment(\.openURL) private var openURL

    init(videoID: String, startSeconds: Int, votePost: RedditPost?, repository: RedditRepository?,
         onJumpToComments: (() -> Void)?, onUnplayable: @escaping () -> Void) {
        self.videoID = videoID
        self.votePost = votePost
        self.repository = repository
        self.onJumpToComments = onJumpToComments
        self.onUnplayable = onUnplayable
        _bridge = StateObject(wrappedValue: YouTubePlayerRegistry.shared.bridge(for: videoID, startSeconds: startSeconds))
    }

    private var autoplays: Bool {
        VideoAutoplayPolicy.shouldAutoplay(mode: generalSettings.autoplayMode)
    }

    var body: some View {
        Group {
            if autoplays || userStarted || bridge.hasLoadedPage {
                player
            } else {
                Button {
                    userStarted = true
                    startPlaying()
                } label: {
                    YouTubePoster(videoID: videoID, caption: nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play video")
                .accessibilityIdentifier("youtube.play")
            }
        }
        .apolloMediaFrame()
        .apolloMediaPager(items: [.youtube(id: videoID)], isPresented: $showingFullscreen, votePost: votePost,
                          repository: repository, onJumpToComments: onJumpToComments,
                          // The picture owns the tap.
                          attachesTapGestures: false)
        .onAppear {
            bridge.onUnplayable = onUnplayable
            if bridge.status.isUnplayable { onUnplayable(); return }
            if autoplays { startPlaying() }
        }
        .onDisappear {
            // The fullscreen viewer or the floating card is showing this player.
            guard !bridge.isFullscreenHosted, !FloatingPiPController.shared.owns(bridge) else { return }
            bridge.pause()
            bridge.releaseSound(holderID: holderID)
        }
        // "Unmute Videos in Comments" decides the video's sound once the
        // viewer it opened closes; the viewer shares this player.
        .onReceive(NotificationCenter.default.publisher(for: .apolloFullscreenViewerClosed)) { _ in
            guard bridge.hasLoadedPage, !FloatingPiPController.shared.owns(bridge) else { return }
            let muted = VideoUnmutePolicy.headerMutedAfterFullscreen(
                mode: generalSettings.unmuteCommentsVideosMode, fullscreenMuted: bridge.isMuted)
            guard muted != bridge.isMuted else { return }
            if VideoAudioSession.shouldClaim(isMuted: muted) { VideoAudioSession.claim(holderID) }
            bridge.setMuted(muted)
        }
    }

    private var player: some View {
        // The overlay takes the box's size, so the thumbnail's own aspect ratio
        // can't change the picture's.
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(YouTubePlayerBridge.aspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    // Behind the page, which is transparent until the player paints.
                    YouTubeThumbnail(videoID: videoID)
                    YouTubeWebSurface(bridge: bridge, role: .inline)
                }
            }
            .clipped()
        // Reborn's Feed Video Scrubber, as on every inline video.
        .overlay(alignment: .bottom) {
            if scrubberSettings.isEnabled {
                VideoScrubStrip(transport: bridge)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VideoMuteBadge(isMuted: bridge.isMuted, isInteractive: false) {
                bridge.toggleMute(.commentsHeader, holderID: holderID)
            }
        }
        .overlay(alignment: .bottomLeading) {
            YouTubeLogoOverlay(bridge: bridge, height: Self.logoHeight)
                .padding(.leading, Self.logoLeadingInset)
                .padding(.bottom, logoBottomInset)
        }
        .modifier(YouTubePiPSourceIf(isEnabled: floatingPiPSourceEnabled, bridge: bridge,
                                     owner: "youtube:" + videoID, screenID: floatingPiPScreenID))
        .overlay { surfaceTapLayer }
        .overlay(alignment: .topTrailing) {
            VideoInlineSpeedMenu(speed: playbackSpeed) { speed in
                playbackSpeed = speed
                bridge.setPlaybackRate(Double(speed))
            }
        }
    }

    private static let logoHeight: CGFloat = 16
    private static let logoLeadingInset: CGFloat = 2

    /// Clear of the scrub strip's band when it's on.
    private var logoBottomInset: CGFloat {
        scrubberSettings.isEnabled ? VideoScrubStrip.height : 0
    }

    /// A tap on the mute badge's rect toggles mute, on the logo's rect (while
    /// it shows) opens YouTube, and the scrub strip's band is left to its
    /// drag; everything else opens the fullscreen viewer.
    private var surfaceTapLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { location in
                    switch VideoSurfaceTap.target(at: location, in: geo.size, hasMuteBadge: true,
                                                  hasScrubStrip: scrubberSettings.isEnabled,
                                                  logoRect: bridge.isPlaying ? nil : YouTubeLogoBadge.tapRect(
                                                      height: Self.logoHeight, in: geo.size,
                                                      leadingInset: Self.logoLeadingInset,
                                                      bottomInset: logoBottomInset)) {
                    case .muteBadge: bridge.toggleMute(.commentsHeader, holderID: holderID)
                    case .logo: YouTubeLogoLink.open(bridge, openURL: openURL)
                    case .scrubStrip: break
                    case .fullscreen: showingFullscreen = true
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("YouTube video")
                .accessibilityHint("Opens the video full screen")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("youtube.surface")
        }
    }

    /// Starts the video with the sound "Unmute Videos in Comments" gives it.
    private func startPlaying() {
        if !bridge.status.hasPlayed { bridge.applyInitialSound(.commentsHeader, holderID: holderID) }
        bridge.play()
    }
}

/// Applies the floating card's source only on the post screen's own media.
private struct YouTubePiPSourceIf: ViewModifier {
    let isEnabled: Bool
    let bridge: YouTubePlayerBridge
    let owner: String
    let screenID: UUID?

    func body(content: Content) -> some View {
        if isEnabled {
            content.floatingPiPSource(youtube: bridge, owner: owner, screenID: screenID)
        } else {
            content
        }
    }
}

#if canImport(WebKit)
/// Marker protocol so a web view wrapper can share `makeWebView`/
/// `loadContent` logic across the platform-specific
/// UIViewRepresentable/NSViewRepresentable conformances.
protocol PlatformViewRepresentable {}
#endif
