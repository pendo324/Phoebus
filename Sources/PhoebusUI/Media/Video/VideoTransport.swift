import AVFoundation
import Combine

/// What the control panel, scrub bar and time labels need from a video, so
/// the same controls drive an `AVPlayer` (`AVPlayerTransport`) or YouTube's
/// web player (`YouTubePlayerBridge`).
@MainActor
protocol VideoTransport: AnyObject {
    /// Shows Pause: the intended rate is non-zero, even while buffering.
    var isPlaying: Bool { get }
    var isMuted: Bool { get }
    var currentSeconds: Double { get }
    /// 0 while unknown, and for a stream with no end.
    var durationSeconds: Double { get }
    /// The rate asked for (1 is normal speed); 0 for a stopped `AVPlayer`.
    var playbackRate: Double { get }
    var isPlayingPublisher: AnyPublisher<Bool, Never> { get }
    var isMutedPublisher: AnyPublisher<Bool, Never> { get }
    func play()
    func pause()
    func setMuted(_ muted: Bool)
    func setPlaybackRate(_ rate: Double)
    /// `scrubbing` is true while a finger still drags the bar, when a web
    /// player is better off not fetching every position.
    func seek(to seconds: Double, scrubbing: Bool, completion: (@MainActor @Sendable () -> Void)?)
}

/// An `AVPlayer` as a transport: one per player, kept alive by the player
/// (which this holds weakly), so everything that scrubs or shows the player's
/// time shares the same `VideoScrubSession`.
@MainActor
final class AVPlayerTransport: VideoTransport {
    private weak var player: AVPlayer?

    private static var key: UInt8 = 0

    static func shared(for player: AVPlayer) -> AVPlayerTransport {
        if let existing = objc_getAssociatedObject(player, &key) as? AVPlayerTransport { return existing }
        let transport = AVPlayerTransport(player: player)
        objc_setAssociatedObject(player, &key, transport, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return transport
    }

    private init(player: AVPlayer) {
        self.player = player
    }

    var isPlaying: Bool { player.map { $0.rate != 0 } ?? false }
    var isMuted: Bool { player?.isMuted ?? true }

    var currentSeconds: Double {
        let seconds = player?.currentTime().seconds ?? 0
        return seconds.isFinite && seconds >= 0 ? seconds : 0
    }

    var durationSeconds: Double {
        let seconds = player?.currentItem?.duration.seconds ?? 0
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    var playbackRate: Double { Double(player?.rate ?? 0) }

    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        guard let player else { return Empty().eraseToAnyPublisher() }
        return player.publisher(for: \.rate).map { $0 != 0 }.receive(on: RunLoop.main).eraseToAnyPublisher()
    }

    var isMutedPublisher: AnyPublisher<Bool, Never> {
        guard let player else { return Empty().eraseToAnyPublisher() }
        return player.publisher(for: \.isMuted).receive(on: RunLoop.main).eraseToAnyPublisher()
    }

    func play() { player?.play() }
    func pause() { player?.pause() }
    func setMuted(_ muted: Bool) { player?.isMuted = muted }
    func setPlaybackRate(_ rate: Double) { player?.rate = Float(rate) }

    /// Always on the exact frame, as scrubbing has always been.
    func seek(to seconds: Double, scrubbing: Bool, completion: (@MainActor @Sendable () -> Void)?) {
        guard let player else { completion?(); return }
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in completion?() }
        }
    }
}
