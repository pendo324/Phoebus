import Foundation
import AVKit

/// One `AVPlayer` per video URL, for as long as it is on screen.
///
/// Building an `AVPlayer` (and, with the Deblurinator on, an `AVURLAsset` +
/// `AVMutableVideoComposition`) inside a view's `init` would re-create one on
/// every re-render while paging a Gallery Post View, exhausting iOS's small
/// pool of hardware video decoders. Reborn's players belong to reused
/// collection-view cells; this cache is the SwiftUI equivalent, identity by URL
/// rather than by view instance.
///
/// Players are held weakly (ARC frees the decoder with the last view);
/// which views are currently SHOWING a URL is tracked separately, by a
/// per-view id, so a view going away can tell whether another one still
/// shows its player. Main-actor-isolated because `AVPlayer` is not
/// thread-safe.
@MainActor
public final class VideoPlayerCache {
    public static let shared = VideoPlayerCache()

    /// Weak. The view using a player owns it through its own `@State`;
    /// this table only lets a re-render find the same object instead
    /// of building another. Holding weakly lets ARC decide: the
    /// moment the last view holding a player is dropped, the decoder
    /// goes with it. A `TabView` keeps pages mounted so `onDisappear`
    /// never fires there, ruling out hand-rolled reference counting.
    private final class Entry {
        weak var player: AVPlayer?
        init(player: AVPlayer) { self.player = player }
    }

    private var entries: [String: Entry] = [:]
    /// Views showing each URL, between their `onAppear` and `onDisappear`.
    private var holders: [String: Set<String>] = [:]

    private init() {}

    /// The player for `url`, created once and shared until released.
    /// `makePlayer` only runs on a miss, keeping the expensive
    /// `AVURLAsset` + composition setup off every re-render.
    public func player(for url: URL, makePlayer: () -> AVPlayer) -> AVPlayer {
        let key = url.absoluteString
        if let existing = entries[key]?.player {
            return existing
        }
        let player = makePlayer()
        entries = entries.filter { $0.value.player != nil }
        entries[key] = Entry(player: player)
        return player
    }

    /// `holder` (a view's own id) started showing `url`.
    public func show(url: URL, holder: String) {
        holders[url.absoluteString, default: []].insert(holder)
    }

    /// `holder` stopped showing `url`. The player itself is freed by ARC.
    public func release(url: URL, holder: String) {
        let key = url.absoluteString
        holders[key]?.remove(holder)
        if holders[key]?.isEmpty == true { holders[key] = nil }
    }

    /// Whether some other view still shows `url`'s player. A view going away must
    /// not pause a player another view is using: SwiftUI re-creates a page's view
    /// while paging, and the outgoing instance's `onDisappear` runs after the
    /// incoming one's `onAppear`.
    public func isStillHeld(url: URL) -> Bool {
        holders[url.absoluteString]?.isEmpty == false
    }

    /// How many views show `url` right now.
    public func holderCount(url: URL) -> Int {
        holders[url.absoluteString]?.count ?? 0
    }

    /// Pauses (and mutes) every player outside `keep`. ARC frees the object once
    /// the last view lets go; this only stops mounted but off-screen players from
    /// decoding, keeping one page's window warm as Reborn does.
    public func pauseAllExcept(_ keep: Set<String>) {
        for (key, entry) in entries where !keep.contains(key) {
            entry.player?.pause()
            // Mute too, not just pause: a paused player resumed by
            // anything else (a loop observer, a racing sync pass)
            // comes back at whatever volume it had, so keeping
            // neighbours warm but muted is what makes only the
            // current page audible.
            entry.player?.isMuted = true
        }
    }

    /// Mutes every audible player that isn't one of `viewerPlayers` and
    /// returns them, so the viewer can give the sound back when it closes.
    /// A video left audible inline would keep playing with sound under a
    /// different fullscreen video (Reborn #1252). The same video shares its
    /// player with the viewer and is left alone.
    public func silenceAudible(except viewerPlayers: [AVPlayer]) -> [AVPlayer] {
        var silenced: [AVPlayer] = []
        for (_, entry) in entries {
            guard let player = entry.player, !player.isMuted,
                  !viewerPlayers.contains(where: { $0 === player }) else { continue }
            player.isMuted = true
            silenced.append(player)
        }
        return silenced
    }

    /// The viewer closed: sound back for the players it silenced that
    /// are still on screen and still muted (a user who unmuted or muted
    /// again in between keeps their choice by construction: only a muted
    /// one is touched, and only if something still shows it).
    public func restoreSound(_ players: [AVPlayer]) {
        for player in players where player.isMuted {
            guard entries.values.contains(where: { $0.player === player }) else { continue }
            player.isMuted = false
        }
    }

    /// Every live player that is playing.
    public func playingPlayers() -> [AVPlayer] {
        entries.values.compactMap { $0.player }.filter { $0.rate != 0 }
    }

    /// Stops and silences every player on the way out of the viewer, as Reborn does.
    public func pauseAll() {
        for (_, entry) in entries {
            entry.player?.pause()
            entry.player?.isMuted = true
        }
    }

    /// How many players are still alive. Test-facing: entries whose
    /// player ARC has already freed do not count.
    public var count: Int { entries.values.count { $0.player != nil } }

    /// Test-facing: drops everything, so one test cannot see another's
    /// entries.
    public func removeAll() {
        let all = entries
        entries.removeAll()
        holders.removeAll()
        for (_, entry) in all {
            entry.player?.pause()
            entry.player?.replaceCurrentItem(with: nil)
        }
    }
}
