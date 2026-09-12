import Foundation

/// Apollo-Reborn "Play Videos in Gallery View" / "Play GIFs in Gallery
/// View" (#1142; keys `GalleryAutoplayVideos` / `GalleryAutoplayGIFs`,
/// both on by default, Media > Browsing): video and GIF tiles in the
/// Gallery View grid play muted and looping while on screen, paused in
/// Low Power Mode.
public struct GalleryAutoplaySettings: Codable, Equatable, Sendable {
    public var playVideos: Bool
    public var playGIFs: Bool

    public static let `default` = GalleryAutoplaySettings(playVideos: true, playGIFs: true)

    public init(playVideos: Bool = true, playGIFs: Bool = true) {
        self.playVideos = playVideos
        self.playGIFs = playGIFs
    }

    /// Reborn's caps: at most 12 tiles playing at once, of which at
    /// most 3 animate a real .gif on the CPU.
    public static let maxPlayingTiles = 12
    public static let maxAnimatedGIFTiles = 3
    /// HLS for a ~200pt tile is capped at 1.5 Mbps.
    public static let tilePeakBitRate: Double = 1_500_000
}

public enum GalleryAutoplayStore {
    private static let key = "Phoebus.galleryAutoplaySettings"

    public static let storage = SettingsStore<GalleryAutoplaySettings>(
        key: key, didChange: .apolloGalleryAutoplayChanged) { GalleryAutoplaySettings.default }

    public static func load() -> GalleryAutoplaySettings { storage.load() }

    public static func save(_ settings: GalleryAutoplaySettings) { storage.save(settings) }
}


extension GalleryAutoplaySettings: StoredSettingsModel {
    public static var store: SettingsStore<GalleryAutoplaySettings> { GalleryAutoplayStore.storage }
}
