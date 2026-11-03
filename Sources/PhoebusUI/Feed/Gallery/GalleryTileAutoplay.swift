import SwiftUI
import PhoebusCore

/// Gallery View grid autoplay (Reborn "Play Videos / GIFs in Gallery View",
/// #1142, and sports-clip tiles, `Apollo-Reborn#1389`):
/// - only on-screen tiles play, muted and looping, over their poster;
/// - at most `GalleryAutoplaySettings.maxPlayingTiles` (12) at once, tiles at
///   least half on screen claiming the slots before edge slivers (see
///   `GalleryTilePlayback`); the rest keep their still;
/// - a GIF plays Reddit's mp4 rendition, never a CPU-decoded .gif (Reborn
///   allows 3 animated-GIF tiles for mp4-less GIFs; this grid leaves those
///   as stills);
/// - a sports-clip or Streamable tile has no Reddit stream, so once it holds a
///   slot it asks its host once (`GalleryHostedVideoResolver`), and only when
///   Autoplay Videos allows (Never, or Wi-Fi Only on cellular, keeps the poster);
/// - HLS capped at 1.5 Mbps;
/// - nothing plays behind the NSFW/spoiler cover, in Low Power Mode, or
///   with the toggle off; toggles apply live;
/// - a stream that fails leaves the poster and frees its slot.
@MainActor
final class GalleryTilePlayback: ObservableObject {
    @Published private(set) var playing = Set<String>()
    private var wanting = Set<String>()
    private var failed = Set<String>()
    private var frames: [String: CGRect] = [:]
    private var viewportHeight: Double = 0
    private var suspendedForMemory = false
    private var pending: Task<Void, Never>?

    func setViewport(height: Double) {
        guard height != viewportHeight else { return }
        viewportHeight = height
        scheduleReplan()
    }

    /// Tile frames in the grid's own space; the slots are handed out once they
    /// stop changing, so a scroll does not reshuffle playback tick by tick.
    func setFrames(_ newFrames: [String: CGRect]) {
        guard newFrames != frames else { return }
        frames = newFrames
        scheduleReplan()
    }

    /// A tile that has left the screen frees its slot at once; one that wants
    /// to play waits for the next settle.
    func want(_ id: String, _ wants: Bool) {
        if wants {
            guard wanting.insert(id).inserted else { return }
            scheduleReplan()
        } else if wanting.remove(id) != nil {
            if playing.remove(id) != nil { scheduleReplan() }
        }
    }

    /// A stream or host lookup that failed: the poster stays, the slot is freed.
    func fail(_ id: String) {
        failed.insert(id)
        if playing.remove(id) != nil { scheduleReplan() }
    }

    func suspendForMemory() {
        suspendedForMemory = true
        playing = []
    }

    private func scheduleReplan() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.replan()
        }
    }

    private func replan() {
        guard !suspendedForMemory else { return }
        let candidates = frames
            .filter { wanting.contains($0.key) && !failed.contains($0.key) }
            .sorted { ($0.value.minY, $0.value.minX, $0.key) < ($1.value.minY, $1.value.minX, $1.key) }
            .map { GalleryPlaybackPlanner.Candidate(id: $0.key, minY: Double($0.value.minY), maxY: Double($0.value.maxY)) }
        let next = Set(GalleryPlaybackPlanner.playing(candidates, viewportMinY: 0, viewportMaxY: viewportHeight))
        if next != playing { playing = next }
    }
}

/// Each tile's frame in the grid's coordinate space, for `GalleryTilePlayback`.
struct GalleryTileFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func galleryTileFrame(id: String, in space: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: GalleryTileFramesKey.self, value: [id: proxy.frame(in: .named(space))])
        })
    }
}

#if canImport(UIKit)
import UIKit
import AVFoundation

struct GalleryTileAutoplayOverlay: View {
    let tile: GalleryTile
    /// False while the NSFW/spoiler cover is up.
    let isVisibleToReader: Bool
    @ObservedObject var playback: GalleryTilePlayback

    @Setting(GalleryAutoplayStore.storage) private var settings
    @State private var onScreen = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var hostedURL: URL?
    @State private var lookingUp = false

    /// Reddit's own stream, when the post has one.
    private var redditStreamURL: URL? {
        switch tile.kind {
        case .video: return settings.playVideos ? tile.videoURL : nil
        case .gif: return settings.playGIFs ? tile.gifMP4URL : nil
        case .photo: return nil
        }
    }

    /// A sports-clip or Streamable tile with nothing from Reddit to play.
    private var asksItsHost: Bool {
        tile.kind == .video && tile.videoURL == nil && tile.hostedVideo != nil && settings.playVideos
            && VideoAutoplayPolicy.shouldAutoplay(mode: GeneralSettingsStore.load().autoplayMode)
    }

    private var streamURL: URL? { redditStreamURL ?? (asksItsHost ? hostedURL : nil) }

    private var wantsToPlay: Bool {
        onScreen && isVisibleToReader && !lowPower && (redditStreamURL != nil || asksItsHost)
    }

    private var hasSlot: Bool { playback.playing.contains(tile.id) }

    var body: some View {
        Group {
            if wantsToPlay, hasSlot, let url = streamURL {
                MutedLoopingTilePlayer(url: url) { [id = tile.id, playback] in
                    playback.fail(id)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onAppear { onScreen = true; update() }
        .onDisappear { onScreen = false; update() }
        .onChange(of: isVisibleToReader) { _, _ in update() }
        .onChange(of: hasSlot) { _, _ in lookUpHostIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .apolloGalleryAutoplayChanged)) { _ in
            update()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled; update()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            onScreen = false; update()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            playback.suspendForMemory()
        }
    }

    private func update() {
        playback.want(tile.id, wantsToPlay)
        lookUpHostIfNeeded()
    }

    /// The host is asked only for a tile that holds a slot (on screen, at rest,
    /// under the cap); the wait counts against the cap like a download does.
    private func lookUpHostIfNeeded() {
        guard asksItsHost, wantsToPlay, hasSlot, hostedURL == nil, !lookingUp,
              let host = tile.hostedVideo else { return }
        if let cached = GalleryHostedVideoResolver.shared.cachedURL(for: host) {
            hostedURL = cached
            return
        }
        lookingUp = true
        Task {
            let url = await GalleryHostedVideoResolver.shared.resolve(host, forGrid: true)
            lookingUp = false
            if let url { hostedURL = url } else { playback.fail(tile.id) }
        }
    }
}

/// An `AVPlayerLayer`-backed muted loop. The layer draws nothing until
/// its first frame, so the poster underneath shows through meanwhile.
private struct MutedLoopingTilePlayer: UIViewRepresentable {
    let url: URL
    let onFailure: @MainActor @Sendable () -> Void

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.start(url: url, onFailure: onFailure)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.stop()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var looper: AVPlayerLooper?
        private var statusObservation: NSKeyValueObservation?

        func start(url: URL, onFailure: @escaping @MainActor @Sendable () -> Void) {
            let item = AVPlayerItem(url: url)
            item.preferredPeakBitRate = GalleryAutoplaySettings.tilePeakBitRate
            item.preferredMaximumResolution = CGSize(width: 480, height: 480)
            let player = AVQueuePlayer()
            player.isMuted = true
            // Never takes the audio session from whatever else plays.
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: item)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            statusObservation = player.observe(\.currentItem?.status) { player, _ in
                if player.currentItem?.status == .failed {
                    Task { @MainActor in onFailure() }
                }
            }
            player.play()
        }

        func stop() {
            statusObservation = nil
            playerLayer.player?.pause()
            looper?.disableLooping()
            looper = nil
            playerLayer.player = nil
        }
    }
}
#endif
