import SwiftUI
import AVFoundation

/// One video's scrubbing, shared by everything that can scrub it (the
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

    private weak var transport: (any VideoTransport)?
    private var pendingTarget: Double?
    private var isSeeking = false

    private static var key: UInt8 = 0

    static func shared(for player: AVPlayer) -> VideoScrubSession {
        shared(for: AVPlayerTransport.shared(for: player))
    }

    static func shared(for transport: any VideoTransport) -> VideoScrubSession {
        if let existing = objc_getAssociatedObject(transport, &key) as? VideoScrubSession { return existing }
        let session = VideoScrubSession(transport: transport)
        objc_setAssociatedObject(transport, &key, session, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return session
    }

    private init(transport: any VideoTransport) {
        self.transport = transport
    }

    /// Moves the scrub to `seconds`.
    func scrub(to seconds: Double) {
        previewSeconds = max(0, seconds)
        pendingTarget = max(0, seconds)
        if !isSeeking { seekToPending() }
    }

    /// Ends the scrub on an exact frame. The preview holds until that
    /// seek lands, so the progress doesn't flick back to the last
    /// chased position first.
    func end(at seconds: Double? = nil, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let transport else { previewSeconds = nil; return }
        let target = seconds ?? previewSeconds
        pendingTarget = nil
        guard let target else { previewSeconds = nil; completion?(); return }
        previewSeconds = target
        isSeeking = true
        transport.seek(to: max(0, target), scrubbing: false) { [weak self] in
            guard let self else { return }
            self.isSeeking = false
            if self.pendingTarget == nil { self.previewSeconds = nil }
            completion?()
        }
    }

    private func seekToPending() {
        guard let transport, let target = pendingTarget else { return }
        pendingTarget = nil
        isSeeking = true
        transport.seek(to: target, scrubbing: true) { [weak self] in
            guard let self else { return }
            self.isSeeking = false
            self.seekToPending()
        }
    }
}

/// The video's time, every frame while it plays (or is scrubbed), for
/// progress bars and time labels. A periodic time observer only fires a few
/// times a second, which makes progress move in visible steps.
struct VideoLiveTime<Content: View>: View {
    let transport: any VideoTransport
    @ObservedObject private var scrub: VideoScrubSession
    @State private var isPlaying = false
    private let content: (Double) -> Content

    init(player: AVPlayer, @ViewBuilder content: @escaping (Double) -> Content) {
        self.transport = AVPlayerTransport.shared(for: player)
        self.scrub = VideoScrubSession.shared(for: player)
        self.content = content
    }

    init(transport: any VideoTransport, @ViewBuilder content: @escaping (Double) -> Content) {
        self.transport = transport
        self.scrub = VideoScrubSession.shared(for: transport)
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPlaying)) { _ in
            content(scrub.previewSeconds ?? transport.currentSeconds)
        }
        .onReceive(transport.isPlayingPublisher) { isPlaying = $0 }
    }
}
