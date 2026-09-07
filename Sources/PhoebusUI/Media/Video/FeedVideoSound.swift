import AVFoundation
import PhoebusCore

/// "Unmute Videos in Feed": only one feed video has sound at a time
/// (Reborn #1250). The first to appear keeps the sound while it plays on
/// screen; the others wait muted, and one takes over only once the owner
/// stops, is muted, or leaves the screen. Nothing hands off while the
/// fullscreen viewer is up: it silences the feed on purpose (#1252).
@MainActor
enum FeedVideoSound {
    private final class Weak { weak var player: AVPlayer?; init(_ p: AVPlayer) { player = p } }

    private static weak var owner: AVPlayer?
    /// On screen, wanting sound, in the order they appeared.
    private static var waiting: [Weak] = []
    private static var timer: Timer?
    /// Fullscreen viewers currently up.
    static var viewersShowing = 0

    /// A feed video appearing in a mode that unmutes it: whether it may
    /// have the sound now. If not, it waits.
    static func requestSound(_ player: AVPlayer) -> Bool {
        if let owner, owner !== player, isAudible(owner) {
            enqueue(player)
            return false
        }
        owner = player
        return true
    }

    /// The user unmuted this feed video by hand: it takes the sound, and
    /// the previous owner goes quiet.
    static func take(_ player: AVPlayer) {
        if let owner, owner !== player { owner.isMuted = true }
        owner = player
        waiting.removeAll { $0.player === player }
    }

    /// The video's row left the screen.
    static func left(_ player: AVPlayer) {
        waiting.removeAll { $0.player == nil || $0.player === player }
        if owner === player { owner = nil; handOff() }
    }

    private static func isAudible(_ player: AVPlayer) -> Bool {
        !player.isMuted && player.timeControlStatus != .paused
    }

    private static func enqueue(_ player: AVPlayer) {
        if !waiting.contains(where: { $0.player === player }) { waiting.append(Weak(player)) }
        guard timer == nil else { return }
        // Reborn hands off after the scroll pass; a light poll does the
        // same without per-frame work.
        let t = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { handOff() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    static func handOff() {
        waiting.removeAll { $0.player == nil }
        if waiting.isEmpty { timer?.invalidate(); timer = nil; return }
        guard viewersShowing == 0 else { return }
        if let owner, isAudible(owner) { return }
        guard let next = waiting.first(where: { $0.player?.timeControlStatus != .paused })?.player else { return }
        waiting.removeAll { $0.player === next }
        // The view showing `next` claims the session as it hears the unmute.
        next.isMuted = false
        owner = next
    }
}
