import SwiftUI
import PhoebusCore

/// A YouTube video's page in the fullscreen media viewer: the same web view
/// the post showed, moved here so playback carries on, under the viewer's
/// usual chrome and the app's floating control panel over it, with the
/// gestures of any fullscreen video (hold for speed, scrub). The picture is
/// aspect-fit to the whole screen at all times; the chrome never resizes it.
struct YouTubeFullscreenPage: View {
    let videoID: String
    var isCurrentPage: Bool = true
    /// Hides the floating panel along with the viewer's own chrome.
    var controlsVisible: Bool = true
    var onSurfaceTapped: (() -> Void)?
    var onVerticalSwipe: ((CGFloat, CGFloat) -> Void)?
    /// Hands the viewer the player, so its "..." menu can set the speed.
    var onBridgeReady: ((YouTubePlayerBridge) -> Void)?
    @Setting(GeneralSettings.self) private var generalSettings
    @Setting(VideoHoldSpeedStore.storage) private var holdSpeedSettings
    @StateObject private var holdForSpeed = VideoHoldForSpeed()
    @StateObject private var bridge: YouTubePlayerBridge
    @State private var holderID = "youtube." + UUID().uuidString
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(videoID: String, isCurrentPage: Bool = true, controlsVisible: Bool = true,
         onSurfaceTapped: (() -> Void)? = nil, onVerticalSwipe: ((CGFloat, CGFloat) -> Void)? = nil,
         onBridgeReady: ((YouTubePlayerBridge) -> Void)? = nil) {
        self.videoID = videoID
        self.isCurrentPage = isCurrentPage
        self.controlsVisible = controlsVisible
        self.onSurfaceTapped = onSurfaceTapped
        self.onVerticalSwipe = onVerticalSwipe
        self.onBridgeReady = onBridgeReady
        _bridge = StateObject(wrappedValue: YouTubePlayerRegistry.shared.bridge(for: videoID))
    }

    var body: some View {
        ZStack {
            YouTubeWebSurface(bridge: bridge, role: .fullscreen)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VideoGestureScrubLayer(transport: bridge, leavesRightThird: holdSpeedSettings.isEnabled)
            surfaceTapLayer
        }
        .overlay { logoLayer }
        .overlay(alignment: .bottom) {
            if controlsVisible {
                VideoControlPanel(
                    transport: bridge,
                    isLandscape: horizontalSizeClass == .regular || verticalSizeClass == .compact,
                    showsAirPlay: false
                ) {
                    bridge.toggleMute(.fullscreen, holderID: holderID)
                }
                .padding(.horizontal, 16)
                // Panel bottom 86.7pt above the screen's, as on any video.
                .padding(.bottom, 52.4)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            onBridgeReady?(bridge)
            guard isCurrentPage else { return }
            // Stock "Unmute Videos When Opened" owns the viewer's sound.
            bridge.applyInitialSound(.fullscreen, holderID: holderID)
            if VideoAutoplayPolicy.shouldAutoplay(mode: generalSettings.autoplayMode) { bridge.play() }
        }
        .onChange(of: isCurrentPage) { _, current in
            if current {
                if VideoAutoplayPolicy.shouldAutoplay(mode: generalSettings.autoplayMode) { bridge.play() }
            } else {
                bridge.pause()
            }
        }
        .onDisappear {
            holdForSpeed.end(bridge)
            bridge.releaseSound(holderID: holderID)
        }
    }

    /// The logo at the bottom-left of the aspect-fit picture, raised clear of
    /// the floating panel when that overlaps it.
    private var logoLayer: some View {
        GeometryReader { geo in
            let picture = Self.pictureSize(in: geo.size)
            let pictureBottom = (geo.size.height + picture.height) / 2
            let panelTop = controlsVisible ? Self.panelClearance : 0
            let bottomInset = max(8, panelTop + 8 - (geo.size.height - pictureBottom))
            YouTubeLogoButton(bridge: bridge, height: 20)
                .position(
                    x: (geo.size.width - picture.width) / 2 + 8 + YouTubeLogoBadge.size(height: 20).width / 2
                        + YouTubeLogoBadge.tapPadding,
                    y: pictureBottom - bottomInset - YouTubeLogoBadge.size(height: 20).height / 2
                        - YouTubeLogoBadge.tapPadding)
        }
    }

    /// Distance from the screen's bottom to the top of the floating panel.
    private static let panelClearance: CGFloat = 52.4 + 103

    private static func pictureSize(in size: CGSize) -> CGSize {
        let width = min(size.width, size.height * YouTubePlayerBridge.aspectRatio)
        return CGSize(width: width, height: width / YouTubePlayerBridge.aspectRatio)
    }

    /// Owns every touch on the picture, so a tap toggles the viewer's chrome,
    /// a vertical swipe leaves or opens the comments, and a hold on the right
    /// third speeds it up, as over any video.
    private var surfaceTapLayer: some View {
        GeometryReader { geo in
            tapLayer(width: geo.size.width)
                .overlay {
                    if holdForSpeed.isHolding {
                        VideoHoldSpeedBadge(speed: holdSpeedSettings.holdSpeed)
                            .position(x: geo.size.width * 5 / 6, y: geo.size.height / 2)
                    }
                }
        }
    }

    private func tapLayer(width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                // A hold that sped the video up isn't also a tap.
                guard !holdForSpeed.isHolding else { return }
                onSurfaceTapped?()
            }
            .simultaneousGesture(holdForSpeed.gesture(width: width, isEnabled: holdSpeedSettings.isEnabled,
                                                      transport: bridge, speed: holdSpeedSettings.holdSpeed))
            .highPriorityGesture(
                onVerticalSwipe == nil ? nil :
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            onVerticalSwipe?(value.translation.height, value.translation.width)
                        }
            )
            .accessibilityElement()
            .accessibilityLabel("YouTube video")
            .accessibilityHint("Shows or hides the controls")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("youtube.fullscreenSurface")
    }
}
