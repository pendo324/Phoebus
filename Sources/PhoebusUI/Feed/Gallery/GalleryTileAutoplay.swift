import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
import AVFoundation

/// Gallery View grid autoplay (Reborn "Play Videos / GIFs in Gallery View",
/// #1142):
/// - only on-screen tiles play, muted and looping, over their poster;
/// - at most `GalleryAutoplaySettings.maxPlayingTiles` (12) at once; the
///   rest keep their still;
/// - a GIF plays Reddit's mp4 rendition, never a CPU-decoded .gif (Reborn
///   allows 3 animated-GIF tiles for mp4-less GIFs; this grid leaves those
///   as stills);
/// - HLS capped at 1.5 Mbps;
/// - nothing plays behind the NSFW/spoiler cover, in Low Power Mode, or
///   with the toggle off; toggles apply live;
/// - a stream that fails leaves the poster and frees its slot.
@MainActor
final class GalleryTileAutoplayBudget {
    static let shared = GalleryTileAutoplayBudget()
    private var playing = Set<String>()

    func claim(_ id: String) -> Bool {
        if playing.contains(id) { return true }
        guard playing.count < GalleryAutoplaySettings.maxPlayingTiles else { return false }
        playing.insert(id)
        return true
    }

    func release(_ id: String) { playing.remove(id) }
}

struct GalleryTileAutoplayOverlay: View {
    let tile: GalleryTile
    /// False while the NSFW/spoiler cover is up.
    let isVisibleToReader: Bool

    @Setting(GalleryAutoplayStore.storage) private var settings
    @State private var onScreen = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var hasSlot = false

    private var streamURL: URL? {
        switch tile.kind {
        case .video: return settings.playVideos ? tile.videoURL : nil
        case .gif: return settings.playGIFs ? tile.gifMP4URL : nil
        case .photo: return nil
        }
    }

    private var shouldPlay: Bool {
        onScreen && isVisibleToReader && !lowPower && streamURL != nil
    }

    var body: some View {
        Group {
            if shouldPlay, hasSlot, let url = streamURL {
                MutedLoopingTilePlayer(url: url) { [id = tile.id] in
                    // Failed stream: poster stays, slot is freed.
                    GalleryTileAutoplayBudget.shared.release(id)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onAppear { onScreen = true; update() }
        .onDisappear { onScreen = false; update() }
        .onChange(of: isVisibleToReader) { _, _ in update() }
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
            GalleryTileAutoplayBudget.shared.release(tile.id); hasSlot = false
        }
    }

    private func update() {
        if shouldPlay {
            hasSlot = GalleryTileAutoplayBudget.shared.claim(tile.id)
        } else if hasSlot {
            GalleryTileAutoplayBudget.shared.release(tile.id)
            hasSlot = false
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
