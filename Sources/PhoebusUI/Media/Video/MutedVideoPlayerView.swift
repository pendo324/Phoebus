import SwiftUI
import AVKit
import PhoebusCore

/// Applies the video's natural aspect ratio, unless the container is
/// doing the sizing (the fullscreen viewer).
struct VideoAspectRatio: ViewModifier {
    let ratio: CGFloat
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.aspectRatio(ratio, contentMode: .fit)
        } else {
            content
        }
    }
}

/// A `VideoPlayer` wrapper that applies the setting owning this video's
/// sound (`VideoUnmuteContext`, `VideoUnmutePolicy`) to its `AVPlayer`.
///
/// Feed rows follow "Unmute Videos in Feed" with their own Remember
/// memory; the post's video at the top of comments follows "Unmute
/// Videos in Comments"; the fullscreen viewer follows stock "Unmute
/// Videos When Opened"; videos embedded in comments start muted.
struct MutedVideoPlayerView: View {
    @Setting(GeneralSettings.self) private var generalSettings
    @Setting(AppearanceSettings.self) private var appearanceSettings
    let url: URL
    typealias UnmuteContext = VideoUnmuteContext
    var unmuteContext: UnmuteContext = .feed
    /// Only the fullscreen media pager gets the hold-for-speed gesture
    /// ("Video Hold Speed"): an inline feed video has no spare
    /// right-third of screen to dedicate to it.
    var enablesHoldForSpeed: Bool = false
    /// "Feed Video Scrubber": an invisible touch strip over the bottom
    /// of the video that scrubs on drag without opening fullscreen.
    /// Gated on `FeedVideoScrubberSettings.isEnabled` (default off).
    var enablesFeedScrubber: Bool = false
    /// "Enable In-App PiP": this inline player hands off to the
    /// floating card when scrolled away while playing. Only the
    /// post-detail video opts in.
    var enablesFloatingPiP: Bool = false
    /// Draws Apollo's control panel (AirPlay / back-15 / play-pause /
    /// forward-15 / mute) beneath the video. Opt-in: the panel belongs
    /// to the fullscreen media viewer; an inline feed row shows only
    /// the thin scrub strip and corner mute button.
    var showsControlPanel: Bool = false
    /// Modifiers applied to the video surface only, not the control
    /// panel below it.
    var decorateVideo: ((AnyView) -> AnyView)?
    @State private var player: AVPlayer
    /// This view's id, for the player cache's "who shows this URL" and
    /// the audio session's holders.
    @State private var holderID = "video." + UUID().uuidString
    /// Between onAppear and onDisappear.
    @State private var isShowing = false
    @State private var playbackSpeed: Float = 1
    /// Reddit's own `width`/`height` for this video, when the caller
    /// has them. Reading the asset waits on the HLS manifest, so the
    /// first layout pass would otherwise use a 16:9 placeholder and jump.
    var initialAspectRatio: CGFloat?
    /// Opens the fullscreen viewer. Owning the tap target here makes
    /// the touch layering explicit: this is the first overlay on the
    /// video surface, so every control added after it keeps its own touches.
    var onRequestFullscreen: (() -> Void)?
    /// Fills the container instead of self-sizing to the video's own
    /// aspect ratio: the fullscreen viewer sizes the video itself and
    /// owns the control panel.
    var fillsContainer: Bool = false
    /// Floats the control panel over the video instead of stacking it
    /// beneath, hiding it when the viewer's chrome is hidden.
    var floatsControlPanel: Bool = false
    /// True when a fullscreen viewer owns this player's chrome, so
    /// this player draws neither its own transport bar/mute nor the
    /// inline speed/PiP buttons.
    var hostedByFullscreenViewer: Bool = false
    /// Whether this player's page is the one on screen. A pager keeps
    /// neighbouring pages alive, so playback must be explicitly
    /// paused for every page that isn't current. `nil` means "no
    /// pager owns me".
    var isCurrentPage: Bool?

    /// One test for every piece of inline chrome.
    private var drawsOwnChrome: Bool {
        !floatsControlPanel && !hostedByFullscreenViewer
    }
    /// Drives the floating panel's visibility, so one tap hides the
    /// panel and the viewer's own chrome together.
    var controlsVisible: Bool = true
    /// Called when the video surface is tapped in the fullscreen
    /// viewer, where a tap toggles the chrome rather than opening
    /// anything. The player owns every touch on the video surface, so
    /// the pager's own tap gesture never fires over a video.
    var onSurfaceTapped: (() -> Void)?
    /// A completed vertical swipe on the video surface, used by the
    /// fullscreen viewer for swipe-down-to-exit. Handled on this
    /// view's own tap overlay since neither a `DragGesture` on the
    /// pager root nor a `UIPanGestureRecognizer` fires over a video.
    var onVerticalSwipe: ((CGFloat, CGFloat) -> Void)?
    /// Hands the `AVPlayer` to the caller once it exists, so
    /// `MediaPagerScreen`'s own "..." menu can reach it.
    var onPlayerReady: ((AVPlayer, URL) -> Void)?
    /// Pinch-to-zoom on the picture, in the fullscreen viewer (`zoomable()`).
    private var isZoomable = false
    @State private var zoom = VideoZoom()
    @State private var naturalAspectRatio: CGFloat
    /// The post screen's own media opts in through the environment, so
    /// every host it plays (Reddit video, Streamable and friends, a GIF
    /// as MP4) can hand over to the floating card.
    @Environment(\.floatingPiPSourceEnabled) private var floatingPiPSourceEnabled
    @Environment(\.floatingPiPScreenID) private var floatingPiPScreenID
    @Environment(\.floatingPiPIsGIF) private var floatingPiPIsGIF
    @Environment(\.floatingPiPHome) private var floatingPiPHome
    @State private var inlineSystemPiP = InlineSystemPiP()

    /// Hands over to the floating card when scrolled away.
    private var isFloatingPiPSource: Bool {
        enablesFloatingPiP || (floatingPiPSourceEnabled && !hostedByFullscreenViewer && !fillsContainer)
    }

    /// A feed video, which shares "Unmute Videos in Feed"'s one sound
    /// with the others on screen (`FeedVideoSound`).
    private var sharesFeedSound: Bool {
        unmuteContext == .feed && !hostedByFullscreenViewer && !fillsContainer
    }

    /// A feed row's video: where a back-popped card hands its picture.
    /// The environment reaches a viewer presented from the row too, so
    /// the viewer's own players are excluded.
    private var isFloatingPiPHome: Bool {
        floatingPiPHome && !hostedByFullscreenViewer && !fillsContainer && !isFloatingPiPSource
    }
    /// Backs "Loop Videos With Audio". Apollo loops silent
    /// GIF-equivalent videos unconditionally; this observer is what
    /// makes looping happen via `AVPlayerItemDidPlayToEndTime`.
    @State private var loopObserver: NSObjectProtocol?

    init<Decorated: View>(
        url: URL,
        unmuteContext: UnmuteContext = .feed,
        enablesHoldForSpeed: Bool = false,
        enablesFeedScrubber: Bool = false,
        enablesFloatingPiP: Bool = false,
        showsControlPanel: Bool = false,
        initialAspectRatio: CGFloat? = nil,
        onRequestFullscreen: (() -> Void)? = nil,
        fillsContainer: Bool = false,
        floatsControlPanel: Bool = false,
        hostedByFullscreenViewer: Bool = false,
        isCurrentPage: Bool? = nil,
        controlsVisible: Bool = true,
        onSurfaceTapped: (() -> Void)? = nil,
        onVerticalSwipe: ((CGFloat, CGFloat) -> Void)? = nil,
        onPlayerReady: ((AVPlayer, URL) -> Void)? = nil,
        @ViewBuilder decorateVideo: @escaping (AnyView) -> Decorated
    ) {
        self.init(url: url,
                  unmuteContext: unmuteContext,
                  enablesHoldForSpeed: enablesHoldForSpeed,
                  enablesFeedScrubber: enablesFeedScrubber,
                  showsControlPanel: showsControlPanel,
                  initialAspectRatio: initialAspectRatio,
                  onRequestFullscreen: onRequestFullscreen,
                  fillsContainer: fillsContainer,
                  floatsControlPanel: floatsControlPanel,
                  hostedByFullscreenViewer: hostedByFullscreenViewer,
                  isCurrentPage: isCurrentPage,
                  controlsVisible: controlsVisible,
                  onSurfaceTapped: onSurfaceTapped,
                  onVerticalSwipe: onVerticalSwipe,
                  onPlayerReady: onPlayerReady)
        self.enablesFloatingPiP = enablesFloatingPiP
        self.decorateVideo = { AnyView(decorateVideo($0)) }
    }

    init(url: URL, unmuteContext: UnmuteContext = .feed, enablesHoldForSpeed: Bool = false, enablesFeedScrubber: Bool = false, showsControlPanel: Bool = false, initialAspectRatio: CGFloat? = nil, onRequestFullscreen: (() -> Void)? = nil, fillsContainer: Bool = false, floatsControlPanel: Bool = false, hostedByFullscreenViewer: Bool = false, isCurrentPage: Bool? = nil, controlsVisible: Bool = true, onSurfaceTapped: (() -> Void)? = nil, onVerticalSwipe: ((CGFloat, CGFloat) -> Void)? = nil, onPlayerReady: ((AVPlayer, URL) -> Void)? = nil) {
        self.url = url
        self.unmuteContext = unmuteContext
        self.enablesHoldForSpeed = enablesHoldForSpeed
        self.enablesFeedScrubber = enablesFeedScrubber
        self.showsControlPanel = showsControlPanel
        self.initialAspectRatio = initialAspectRatio
        self.onRequestFullscreen = onRequestFullscreen
        self.fillsContainer = fillsContainer
        self.floatsControlPanel = floatsControlPanel
        self.hostedByFullscreenViewer = hostedByFullscreenViewer
        self.isCurrentPage = isCurrentPage
        self.controlsVisible = controlsVisible
        self.onSurfaceTapped = onSurfaceTapped
        self.onVerticalSwipe = onVerticalSwipe
        self.onPlayerReady = onPlayerReady
        // Start at Reddit's own ratio when the caller has it, so the
        // video never lays out at a placeholder size and then jumps.
        _naturalAspectRatio = State(initialValue: initialAspectRatio ?? 16.0 / 9.0)
        // One player per URL, not per `init`: SwiftUI calls `init` on
        // every re-render, so building the `AVPlayer` here directly
        // would allocate a new decoder on every render.
        // `VideoPlayerCache` keys identity on the URL instead.
        _player = State(initialValue: VideoPlayerCache.shared.player(for: url) {
            AVPlayer(url: url)
        })
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Mirrors `player.isMuted` for the inline badge. A `@State` copy
    /// since `AVPlayer.isMuted` isn't observable by SwiftUI.
    @State private var isMutedForBadge = true
    @Setting(FeedVideoScrubberStore.storage) private var scrubberSettings
    @Setting(VideoHoldSpeedStore.storage) private var holdSpeedSettings
    @StateObject private var holdForSpeed = VideoHoldForSpeed()
    private var isHoldingForSpeed: Bool { holdForSpeed.isHolding }

    /// Includes 0.75x and 1.25x (Reborn #445), keeping the menu in ascending
    /// order. Sourced from `VideoPlaybackSpeeds` (PhoebusCore) so ordering and
    /// titles are assertable.
    static let playbackSpeeds: [Float] = VideoPlaybackSpeeds.all

    /// The video surface, with the caller's decorations applied to it alone.
    @ViewBuilder
    private var decoratedPlayerBody: some View {
        if let decorateVideo {
            decorateVideo(AnyView(playerBody))
        } else {
            playerBody
        }
    }

    var body: some View {
        if showsControlPanel && floatsControlPanel {
            // Floating: an overlay pinned to the bottom, so the video
            // keeps the whole container.
            decoratedPlayerBody
                .overlay(alignment: .bottom) {
                    if controlsVisible {
                        VideoControlPanel(
                            player: player,
                            isLandscape: horizontalSizeClass == .regular
                                || verticalSizeClass == .compact,
                            onToggleMute: toggleMute
                        )
                        .padding(.horizontal, 16)
                        // Panel bottom 86.7pt above the screen's.
                        .padding(.bottom, 52.4)
                        .transition(.opacity)
                    }
                }
        } else if showsControlPanel {
            VStack(spacing: 12) {
                decoratedPlayerBody
                VideoControlPanel(
                    player: player,
                    isLandscape: horizontalSizeClass == .regular
                        || verticalSizeClass == .compact,
                    onToggleMute: toggleMute
                )
            }
        } else {
            decoratedPlayerBody
        }
    }

    @ViewBuilder
    private var playerBody: some View {
        // A bare layer, not SwiftUI's `VideoPlayer`: `VideoPlayer` is
        // an `AVPlayerViewController` and draws AVKit's own controls,
        // which overlap Apollo's control panel and mute button.
        AVPlayerLayerView(
            player: player,
            onTapAtPoint: (onRequestFullscreen == nil && onSurfaceTapped == nil) ? nil : { point, size in
                routeSurfaceTap(at: point, in: size)
            },
            onLayer: (isFloatingPiPSource || isFloatingPiPHome) ? { layer in
                // "Enable PiP When Leaving App" for this inline video.
                inlineSystemPiP.attach(layer: layer, player: player, isGIF: floatingPiPIsGIF,
                                       isFeedRow: isFloatingPiPHome)
            } : nil,
            zoom: isZoomable ? zoom : nil)
            .overlay {
                if enablesHoldForSpeed, holdSpeedSettings.isEnabled, !hasSurfaceTapLayer {
                    // Right third of the video, leaving the
                    // left+center two-thirds for the long-press menu.
                    // A passive `DragGesture(minimumDistance: 0)`
                    // avoids competing with that menu's long-press.
                    GeometryReader { geo in
                        Color.clear
                            .frame(width: geo.size.width / 3, height: geo.size.height)
                            .contentShape(Rectangle())
                            .position(x: geo.size.width - geo.size.width / 6, y: geo.size.height / 2)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in startHoldForSpeed() }
                                    .onEnded { _ in endHoldForSpeed() }
                            )
                            .overlay(alignment: .center) {
                                if isHoldingForSpeed, !hasSurfaceTapLayer {
                                    Text(Self.speedTitle(holdSpeedSettings.holdSpeed))
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(.black.opacity(0.6)))
                                        .accessibilityIdentifier("video.holdForSpeedIndicator")
                                }
                            }
                    }
                }
            }
            .overlay {
                // Scoped like `enablesHoldForSpeed` (fullscreen pager
                // only): covers the left two-thirds when hold-for-speed
                // is also active, leaving its right third alone. Apollo's own
                // hold-and-drag scrub, distinct from the "Feed Video Scrubber"
                // strip and the gallery viewer's own copy of this gesture.
                if enablesHoldForSpeed {
                    VideoGestureScrubLayer(transport: AVPlayerTransport.shared(for: player),
                                           leavesRightThird: holdSpeedSettings.isEnabled)
                }
            }
            .overlay {
                if isZoomable { VideoPinchCatcher(zoom: zoom) }
            }
            .overlay(alignment: .bottom) {
                // Feed Video Scrubber stands alone, as Reborn's; stock
                // Show GIF Progress is about GIFs, not this strip.
                if enablesFeedScrubber, scrubberSettings.isEnabled {
                    VideoScrubStrip(transport: AVPlayerTransport.shared(for: player),
                                    loadDuration: { await loadScrubDuration() })
                } else if showsGIFProgress {
                    gifProgressLine
                }
            }
            // Inline mute toggle, flush in the bottom-right corner,
            // hidden while the control panel is shown (which carries
            // its own mute button).
            .overlay(alignment: .bottomTrailing) {
                if !showsControlPanel, drawsOwnChrome {
                    // Not interactive when the tap layer below owns
                    // the whole surface.
                    VideoMuteBadge(isMuted: isMutedForBadge, isInteractive: onRequestFullscreen == nil) {
                        toggleMute()
                    }
                }
            }
            // Sizing from the asset's natural aspect ratio (falling
            // back to 16:9 until the track loads) keeps the player
            // full-width for landscape and portrait video.
            .frame(maxWidth: .infinity, maxHeight: fillsContainer ? .infinity : nil)
            // Only self-size when not filling: the fullscreen viewer
            // sizes the video itself.
            .modifier(VideoAspectRatio(ratio: naturalAspectRatio, isEnabled: !fillsContainer))
            .modifier(FloatingPiPSourceIf(isEnabled: isFloatingPiPSource, player: player,
                                           owner: url.absoluteString, aspectRatio: naturalAspectRatio,
                                           isGIF: floatingPiPIsGIF, screenID: floatingPiPScreenID))
            .modifier(FloatingPiPHomeIf(isEnabled: isFloatingPiPHome, owner: url.absoluteString))
            // Two tap paths: this SwiftUI overlay and a `UITapGestureRecognizer` on
            // the view drawing the video; either alone misses some touches.
            // `routeSurfaceTap` de-duplicates: whichever fires first acts.
            .overlay { videoSurfaceTapLayer }
            .overlay(alignment: .topTrailing) {
                // Hidden with the rest of the chrome in the fullscreen
                // viewer: the speed control lives in the "..." menu instead.
                if controlsVisible, drawsOwnChrome {
                    VideoInlineSpeedMenu(speed: playbackSpeed) { speed in
                        playbackSpeed = speed
                        if player.timeControlStatus == .playing {
                            player.rate = speed
                        }
                    }
                }
            }
            // The badge follows the player's own state: another video can
            // take the sound (#1250) or a fullscreen viewer silence it
            // (#1252) without going through this view.
            .onReceive(player.publisher(for: \.isMuted).receive(on: RunLoop.main)) { _ in
                // The player's state now, not the value delivered: a new player's
                // initial `false` arrives a turn late, after `onAppear` has muted it, and
                // would claim Playback for a muted video (stopping other audio, then
                // resuming it when the real `true` arrived).
                let muted = player.isMuted
                isMutedForBadge = muted
                // The audio claim follows the player's sound, whoever
                // changed it: muted by another video or the viewer, this
                // view lets go so other apps' audio can resume.
                guard isShowing else { return }
                if muted { VideoAudioSession.release(holderID) } else { VideoAudioSession.claim(holderID) }
            }
            // "Unmute Videos in Comments" decides the header video's
            // sound once the viewer it opened closes. The viewer shares
            // this player, so it arrives in the state the viewer left.
            .onReceive(NotificationCenter.default.publisher(for: .apolloFullscreenViewerClosed)) { _ in
                guard unmuteContext == .commentsHeader, !hostedByFullscreenViewer,
                      !FloatingPiPController.shared.owns(player) else { return }
                let muted = VideoUnmutePolicy.headerMutedAfterFullscreen(
                    mode: generalSettings.unmuteCommentsVideosMode, fullscreenMuted: player.isMuted)
                guard muted != player.isMuted else { return }
                if VideoAudioSession.shouldClaim(isMuted: muted) { VideoAudioSession.claim(holderID) }
                player.isMuted = muted
            }
            .onAppear {
                // The URL goes with it: the gallery viewer evicts by
                // cache key, and a resolver view's key is only known
                // once its lookup lands.
                onPlayerReady?(player, url)
                isShowing = true
                VideoPlayerCache.shared.show(url: url, holder: holderID)
                applyInitialMuteState()
                isMutedForBadge = player.isMuted
                configureLooping()
                // Only when Reddit did not supply the dimensions.
                if initialAspectRatio == nil {
                    Task { await loadNaturalAspectRatio() }
                }
                // Only the page the user is actually on: a pager keeps
                // its neighbours alive, and several `AVPlayer`s
                // decoding at once is a crash risk.
                if isCurrentPage != false,
                   VideoAutoplayPolicy.shouldAutoplay(
                    mode: generalSettings.autoplayMode) {
                    player.play()
                }
            }
            // Paging changes which page is current without any view
            // appearing or disappearing, so `onAppear` alone can't keep this right.
            .onChange(of: isCurrentPage) { current in
                guard let current else { return }
                if current {
                    if VideoAutoplayPolicy.shouldAutoplay(
                        mode: generalSettings.autoplayMode) {
                        player.play()
                    }
                }
                // No `else { player.pause() }` here: the player is
                // shared per URL, but `isCurrentPage` is per view
                // instance, and SwiftUI keeps a stale instance of the
                // same page alive briefly after a swipe. Pausing the
                // pages the user has left is the viewer's job instead:
                // `evictDistantPlayers` calls `VideoPlayerCache.pauseAllExcept`.
            }
            // Pausing here, not in `onDisappear`: `isCurrentPage` flips on the live
            // view for the page the user just left. A page already current on appear
            // gets no `onChange`, and a page that appeared as a neighbour has already
            // skipped its `onAppear` autoplay; `.task(id:)` catches both.
            .task(id: isCurrentPage) {
                guard isCurrentPage == true else { return }
                if VideoAutoplayPolicy.shouldAutoplay(
                    mode: generalSettings.autoplayMode) {
                    player.play()
                }
            }
            .onDisappear {
                // Release first, then decide: the player is shared per
                // URL, and SwiftUI re-creates a page's view while
                // paging, so the outgoing instance's `onDisappear`
                // runs after the incoming one's `onAppear`. Pausing
                // unconditionally would stop the video that just started.
                isShowing = false
                VideoPlayerCache.shared.release(url: url, holder: holderID)
                // The floating PiP card owns a player that scrolled away while playing.
                let ownedByPiP = FloatingPiPController.shared.owns(player)
                if !VideoPlayerCache.shared.isStillHeld(url: url), !ownedByPiP {
                    player.pause()
                }
                stopLooping()
                inlineSystemPiP.detach()
                if sharesFeedSound { FeedVideoSound.left(player) }
                // Always this view's own claim: another view still showing
                // the player holds its own, and the PiP card claims for
                // itself when it takes an audible player.
                VideoAudioSession.release(holderID)
            }
    }

    /// Pinch-to-zoom on the picture, as an image zooms in the same viewer.
    func zoomable() -> Self {
        var copy = self
        copy.isZoomable = true
        return copy
    }

    private var hasSurfaceTapLayer: Bool {
        onRequestFullscreen != nil || onSurfaceTapped != nil || onVerticalSwipe != nil
    }

    private func startHoldForSpeed() {
        holdForSpeed.start(AVPlayerTransport.shared(for: player), speed: holdSpeedSettings.holdSpeed)
    }

    private func endHoldForSpeed() {
        holdForSpeed.end(AVPlayerTransport.shared(for: player))
    }

    /// Hold for Video Speed, on the surface layer that owns the video's
    /// touches (see `VideoHoldForSpeed`).
    private func holdForSpeedGesture(width: CGFloat) -> some Gesture {
        holdForSpeed.gesture(width: width, isEnabled: enablesHoldForSpeed && holdSpeedSettings.isEnabled,
                             transport: AVPlayerTransport.shared(for: player), speed: holdSpeedSettings.holdSpeed)
    }

    /// Routes one tap on the video surface, in UIKit coordinates.
    ///
    /// The mute badge's own rect toggles mute; the scrub strip's
    /// bottom band is left alone since it's a drag target; everything
    /// else opens fullscreen.
    @ViewBuilder
    private var videoSurfaceTapLayer: some View {
        if hasSurfaceTapLayer {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // A hold that sped the video up isn't also a tap.
                        guard !isHoldingForSpeed else { return }
                        routeSurfaceTap(at: location, in: geo.size)
                    }
                    .simultaneousGesture(holdForSpeedGesture(width: geo.size.width))
                    .overlay {
                        if isHoldingForSpeed {
                            VideoHoldSpeedBadge(speed: holdSpeedSettings.holdSpeed)
                                .position(x: geo.size.width * 5 / 6, y: geo.size.height / 2)
                        }
                    }
                    // The drag lives here, above the player's own
                    // UIView: a `DragGesture` on the pager root never
                    // fires over a fullscreen video (the player's
                    // interactive view swallows it), and neither does
                    // a `UIPanGestureRecognizer` alongside the
                    // player's tap recognizer. High priority, not
                    // simultaneous: the enclosing `TabView`'s paging
                    // scroll view claims drags by default.
                    .highPriorityGesture(
                        onVerticalSwipe == nil ? nil :
                            DragGesture(minimumDistance: 30)
                                .onEnded { value in
                                    onVerticalSwipe?(value.translation.height,
                                                     value.translation.width)
                                }
                    )
                    .accessibilityIdentifier("video.surfaceTapLayer")
            }
        }
    }

    /// Runs the routing for whichever tap path fired first, ignoring
    /// the other for a moment after (both firing would toggle mute twice).
    private func routeSurfaceTap(at point: CGPoint, in size: CGSize) {
        let now = Date()
        if let last = Self.lastSurfaceTap.value, now.timeIntervalSince(last) < 0.3 { return }
        Self.lastSurfaceTap.value = now
        handleSurfaceTap(at: point, in: size)
    }

    /// A box rather than `@State`: the UIKit path calls in from
    /// outside SwiftUI's update cycle.
    private static let lastSurfaceTap = TapInstantBox()

    final class TapInstantBox: @unchecked Sendable {
        var value: Date?
    }

    private func handleSurfaceTap(at point: CGPoint, in size: CGSize) {
        // Fullscreen: any tap toggles the chrome; there's no mute
        // badge or scrub strip here to route around.
        if let onSurfaceTapped {
            onSurfaceTapped()
            return
        }
        guard let onRequestFullscreen else { return }
        let target = VideoSurfaceTap.target(
            at: point, in: size, hasMuteBadge: !showsControlPanel,
            hasScrubStrip: enablesFeedScrubber && scrubberSettings.isEnabled)
        switch target {
        case .muteBadge: toggleMute()
        case .logo, .scrubStrip: break
        case .fullscreen: onRequestFullscreen()
        }
    }

    /// The user's own mute toggle (badge or control panel). Claims the audio
    /// session before unmuting, matching `applyInitialMuteState`'s ordering.
    /// "Remember" records only this, not the app's own muting (another feed
    /// video taking the sound, the viewer silencing the feed).
    private func toggleMute() {
        let muting = !player.isMuted
        if VideoAudioSession.shouldClaim(isMuted: muting) {
            VideoAudioSession.claim(holderID)
        }
        if unmuteContext == .feed, !hostedByFullscreenViewer {
            RememberedVideoMuteStore.isMuted = muting
        }
        if unmuteContext == .fullscreen { FullscreenUnmuteMemory.isUnmuted = !muting }
        player.isMuted = muting
        isMutedForBadge = muting
        if muting { VideoAudioSession.release(holderID) }
        if !muting, sharesFeedSound { FeedVideoSound.take(player) }
    }

    /// Stock "Show GIF Progress": a GIF shown inline (not in the viewer,
    /// which has its own transport) draws a thin progress line along its
    /// bottom edge, where the setting is Everywhere or Thumbnails.
    private var showsGIFProgress: Bool {
        floatingPiPIsGIF && !hostedByFullscreenViewer && !showsControlPanel
            && appearanceSettings.gifProgressLocation != .mediaViewer
    }

    private var gifProgressLine: some View {
        GeometryReader { geo in
            VideoLiveTime(player: player) { seconds in
                let duration = Self.durationSeconds(player)
                let progress = duration > 0 ? CGFloat(seconds / duration) : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(white: 0.35))
                    Rectangle().fill(Color(white: 0.75))
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
                .frame(height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func durationSeconds(_ player: AVPlayer) -> Double {
        let value = player.currentItem?.duration.seconds ?? 0
        return value.isFinite && value > 0 ? value : 0
    }

    static func speedTitle(_ speed: Float) -> String {
        VideoPlaybackSpeeds.title(speed)
    }

    /// Reads the asset's real presentation size so portrait videos
    /// aren't letterboxed inside a hardcoded landscape box.
    private func loadNaturalAspectRatio() async {
        guard let track = try? await player.currentItem?.asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return }
        let displaySize = size.applying(transform)
        let width = abs(displaySize.width)
        let height = abs(displaySize.height)
        guard width > 0, height > 0 else { return }
        naturalAspectRatio = width / height
    }

    /// The asset's duration for the scrub strip while the item hasn't
    /// loaded one yet (a post-detail video not yet played).
    private func loadScrubDuration() async -> Double {
        guard let asset = player.currentItem?.asset,
              let duration = try? await asset.load(.duration),
              duration.isNumeric else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }

    private func applyInitialMuteState() {
        CrashRecorder.record(.startedVideo)
        // A viewer-hosted player takes the gallery's shared mute
        // state, already applied when the player was registered.
        // Re-deriving it from the inline setting here would undo an
        // unmute the user made on a previous page.
        if hostedByFullscreenViewer {
            isMutedForBadge = player.isMuted
            if VideoAudioSession.shouldClaim(isMuted: player.isMuted) {
                VideoAudioSession.claim(holderID)
            }
            return
        }
        var muted = VideoUnmutePolicy.startsMuted(
            unmuteContext, settings: generalSettings,
            feedRememberedMuted: RememberedVideoMuteStore.isMuted,
            fullscreenUnmutedThisSession: FullscreenUnmuteMemory.isUnmuted,
            alreadyAudible: !player.isMuted && player.rate != 0)
        // One feed video with sound at a time (#1250).
        if !muted, sharesFeedSound, !FeedVideoSound.requestSound(player) { muted = true }
        // Must claim the audio session before unmuting: Apollo defaults
        // to the Ambient category, which silences AVPlayer audio even when unmuted.
        if VideoAudioSession.shouldClaim(isMuted: muted) {
            VideoAudioSession.claim(holderID)
        }
        player.isMuted = muted
    }

    /// "Loop Videos With Audio": Apollo's default is silent
    /// GIF-equivalent videos loop, videos with audio play once, and
    /// this setting extends looping to audible videos too.
    /// `player.isMuted` is read fresh at the moment playback ends
    /// since the user's own toggle can change it mid-playback.
    private func configureLooping() {
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [self] _ in
            MainActor.assumeIsolated {
                // A video without sound always loops; one with an audio
                // track loops only under Loop Videos with Audio.
                // Streams whose tracks aren't known fall back to the mute state.
                let tracks = player.currentItem?.tracks.compactMap(\.assetTrack) ?? []
                let hasAudio = tracks.isEmpty ? !player.isMuted : tracks.contains { $0.mediaType == .audio }
                guard !hasAudio || generalSettings.loopVideosWithAudio else { return }
                // While the floating card presents this player, its Loop
                // Videos setting decides.
                guard !FloatingPiPController.shared.suppressesInlineLoop(for: player) else { return }
                player.seek(to: .zero)
                player.play()
            }
        }
    }

    private func stopLooping() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
    }

}

extension Notification.Name {
    /// The fullscreen media viewer went away.
    static let apolloFullscreenViewerClosed = Notification.Name("apolloFullscreenViewerClosed")
}

/// Stock "Unmute Videos When Opened → Remember": an unmute in the
/// fullscreen viewer lasts until the user re-mutes or the app closes.
@MainActor
enum FullscreenUnmuteMemory {
    static var isUnmuted = false
}

/// The feed's own last manual mute/unmute choice, for "Unmute Videos in
/// Feed → Remember".
enum RememberedVideoMuteStore {
    private static let key = "com.pendo324.Phoebus.rememberedVideoMuted"

    static var isMuted: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// A transparent UIKit long-press-drag recognizer for the fullscreen
/// video player's own hold-and-drag scrub, the counterpart of
/// `GalleryImageViewerScreen`'s `GalleryVerticalSwipeCatcher.handleScrub`.
///
/// Same shape as `GalleryVerticalSwipeCatcher` (both use `AncestorGestureHost`):
/// the recognizer lives on an ancestor that hands every touch through
/// untouched (`hitTest` returns nil), the only shape proven to
/// actually receive touches alongside `TabView(.page)`'s own recognizers.
struct VideoScrubGestureCatcher: UIViewRepresentable {
    /// nil when the current page has no known scrubbable duration;
    /// the recognizer then commits nothing.
    var scrubDuration: () -> Double?
    var onScrubBegan: () -> Double
    var onScrubChanged: (CGFloat, Double) -> Void
    var onScrubEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = AncestorGestureHost()
        view.backgroundColor = .clear
        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleScrub(_:)))
        // Armed effectively on touch-down, committed only past the
        // slop in `.changed`, so a quick tap falls through untouched.
        recognizer.minimumPressDuration = 0.05
        recognizer.delegate = context.coordinator
        // The pager still needs the touch when this one declines or
        // ends without committing.
        recognizer.cancelsTouchesInView = false
        view.recognizers = [recognizer]
        context.coordinator.recognizer = recognizer
        // Not `recognizer.view`: `AncestorGestureHost.didMoveToWindow()`
        // reparents the recognizer onto the top-of-screen ancestor, so
        // this small placeholder view is the only thing that still
        // knows the "left two-thirds" region, laid out where SwiftUI put it.
        context.coordinator.regionView = view
        context.coordinator.apply(scrubDuration: scrubDuration,
                                  onScrubBegan: onScrubBegan,
                                  onScrubChanged: onScrubChanged,
                                  onScrubEnded: onScrubEnded)
        return view
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        (view as? AncestorGestureHost)?.detach()
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.apply(scrubDuration: scrubDuration,
                                  onScrubBegan: onScrubBegan,
                                  onScrubChanged: onScrubChanged,
                                  onScrubEnded: onScrubEnded)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var recognizer: UILongPressGestureRecognizer?
        /// See `makeUIView`: the placeholder view, kept separately
        /// from `recognizer.view` since the ancestor host reparents
        /// the recognizer away from it.
        weak var regionView: UIView?
        private var scrubDuration: (() -> Double?)?
        private var onScrubBegan: (() -> Double)?
        private var onScrubChanged: ((CGFloat, Double) -> Void)?
        private var onScrubEnded: (() -> Void)?
        private var scrubStartX: CGFloat = 0
        private var scrubActive = false

        func apply(scrubDuration: @escaping () -> Double?,
                   onScrubBegan: @escaping () -> Double,
                   onScrubChanged: @escaping (CGFloat, Double) -> Void,
                   onScrubEnded: @escaping () -> Void) {
            self.scrubDuration = scrubDuration
            self.onScrubBegan = onScrubBegan
            self.onScrubChanged = onScrubChanged
            self.onScrubEnded = onScrubEnded
        }

        @objc func handleScrub(_ sender: UILongPressGestureRecognizer) {
            guard let view = sender.view else { return }
            switch sender.state {
            case .began:
                scrubStartX = sender.location(in: view).x
                scrubActive = false
                // Recognizing "simultaneously" doesn't stop the
                // pager's scroll view from moving under a horizontal
                // drag; disabling every `UIScrollView` descendant the
                // instant the press lands, before the pager's own pan
                // can claim the touch, is what actually stops it.
                Self.setScrollViewsEnabled(false, in: view)
                // Safety net: guarantees paging can never be stuck
                // disabled forever if this recognizer never reaches a terminal state.
                scrubWatchdogGeneration &+= 1
                let generation = scrubWatchdogGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak view] in
                    guard let self, let view, self.scrubWatchdogGeneration == generation else { return }
                    Self.setScrollViewsEnabled(true, in: view)
                }
            case .changed:
                guard let duration = scrubDuration?(), duration > 0 else { return }
                let x = sender.location(in: view).x
                let deltaX = x - scrubStartX
                if !scrubActive {
                    // A second finger is a pinch, not a scrub.
                    guard abs(deltaX) >= 12, sender.numberOfTouches < 2 else { return }
                    scrubActive = true
                    _ = onScrubBegan?()
                }
                let width = max(view.bounds.width, 1)
                onScrubChanged?(deltaX / width, duration)
            case .ended, .cancelled, .failed:
                if scrubActive { onScrubEnded?() }
                scrubActive = false
                scrubWatchdogGeneration &+= 1
                Self.setScrollViewsEnabled(true, in: view)
            default:
                break
            }
        }

        private var scrubWatchdogGeneration = 0

        /// Walks down from `root`, toggling `isScrollEnabled` on every
        /// `UIScrollView` descendant, since this recognizer's view is
        /// also the top-of-hierarchy ancestor host, not a leaf.
        private static func setScrollViewsEnabled(_ enabled: Bool, in root: UIView) {
            for scrollView in UIKitTree.scrollViews(in: root) {
                scrollView.isScrollEnabled = enabled
            }
        }

        /// Simultaneous with everything, including `MediaPagerScreen`'s
        /// `TabView` paging: a mostly-horizontal drag can otherwise
        /// still page the pager mid-scrub.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Committed: the scrub owns this touch outright.
            guard !scrubActive else {
                return false
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool { false }

        /// Region gate: the host view's own frame is still laid out
        /// exactly where SwiftUI's `.frame`/`.position` put it, so
        /// converting to window coordinates reproduces the "left
        /// two-thirds only" scoping without the recognizer needing to
        /// live inside that frame.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            guard let host = regionView,
                  let window = host.window
            else { return true }
            // A zoomed picture's drag pans it.
            if ZoomingScrollView.isZoomedOnScreen { return false }
            let region = host.convert(host.bounds, to: window)
            return region.contains(touch.location(in: window))
        }
    }
}

/// Applies `floatingPiPSource` only when the call site opts in.
private struct FloatingPiPSourceIf: ViewModifier {
    let isEnabled: Bool
    let player: AVPlayer
    let owner: String
    let aspectRatio: CGFloat
    var isGIF = false
    var screenID: UUID?

    func body(content: Content) -> some View {
        if isEnabled {
            content.floatingPiPSource(player: player, owner: owner, aspectRatio: aspectRatio,
                                      isGIF: isGIF, screenID: screenID)
        } else {
            content
        }
    }
}

/// Applies `FloatingPiPHome` only on feed rows.
private struct FloatingPiPHomeIf: ViewModifier {
    let isEnabled: Bool
    let owner: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(FloatingPiPHome(owner: owner))
        } else {
            content
        }
    }
}
