import SwiftUI
import AVFoundation

/// One player's scrubbing, shared by everything that can scrub it (the
/// hold-and-drag gesture, the feed strip, the control panel and gallery
/// sliders) and everything that shows its time.
///
/// While a scrub runs, `previewSeconds` is where the finger is, so
/// every progress display follows the finger at once instead of waiting
/// for seeks to land. Seeks chase the finger: at most one is in flight,
/// and when it lands the newest position is sought next, so a fast drag
/// never queues up a backlog of stale seeks (Apple's QA1820 pattern).
@MainActor
final class VideoScrubSession: ObservableObject {
    @Published private(set) var previewSeconds: Double?

    private weak var player: AVPlayer?
    private var pendingTarget: CMTime?
    private var isSeeking = false

    private static var key: UInt8 = 0

    static func shared(for player: AVPlayer) -> VideoScrubSession {
        if let existing = objc_getAssociatedObject(player, &key) as? VideoScrubSession { return existing }
        let session = VideoScrubSession(player: player)
        objc_setAssociatedObject(player, &key, session, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return session
    }

    private init(player: AVPlayer) {
        self.player = player
    }

    /// Moves the scrub to `seconds`.
    func scrub(to seconds: Double) {
        previewSeconds = max(0, seconds)
        pendingTarget = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        if !isSeeking { seekToPending() }
    }

    /// Ends the scrub on an exact frame. The preview holds until that
    /// seek lands, so the progress doesn't flick back to the last
    /// chased position first.
    func end(at seconds: Double? = nil, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let player else { previewSeconds = nil; return }
        let target = seconds ?? previewSeconds
        pendingTarget = nil
        guard let target else { previewSeconds = nil; completion?(); return }
        previewSeconds = target
        isSeeking = true
        player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeeking = false
                if self.pendingTarget == nil { self.previewSeconds = nil }
                completion?()
            }
        }
    }

    private func seekToPending() {
        guard let player, let target = pendingTarget else { return }
        pendingTarget = nil
        isSeeking = true
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeeking = false
                self.seekToPending()
            }
        }
    }
}

/// The player's time, every frame while it plays (or is scrubbed), for
/// progress bars and time labels. A periodic time observer only fires a few
/// times a second, which makes progress move in visible steps.
struct VideoLiveTime<Content: View>: View {
    let player: AVPlayer
    @ObservedObject private var scrub: VideoScrubSession
    @State private var isPlaying = false
    private let content: (Double) -> Content

    init(player: AVPlayer, @ViewBuilder content: @escaping (Double) -> Content) {
        self.player = player
        self.scrub = VideoScrubSession.shared(for: player)
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPlaying)) { _ in
            content(scrub.previewSeconds ?? Self.seconds(player.currentTime()))
        }
        .onReceive(player.publisher(for: \.rate).receive(on: RunLoop.main)) { isPlaying = $0 != 0 }
    }

    static func seconds(_ time: CMTime) -> Double {
        let value = time.seconds
        return value.isFinite && value >= 0 ? value : 0
    }
}
