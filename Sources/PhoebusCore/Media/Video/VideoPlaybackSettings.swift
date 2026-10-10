import Foundation

/// Video playback options: a default speed every player starts at, a master
/// Loop Videos switch, and the fullscreen skip buttons' interval. Phoebus-only
/// (neither Apollo nor Reborn has them), inspired by Continuum's video settings.
public struct VideoPlaybackSettings: Codable, Equatable, Sendable {
    /// The rate a video starts at, and the one hold-for-speed returns to.
    public var defaultSpeed: Float
    /// Off: no video loops, silent or not. On: Apollo's rule applies (silent
    /// clips loop, audible ones under "Loop Videos with Audio").
    public var loopVideos: Bool
    /// Seconds the fullscreen viewer's back/forward buttons jump.
    public var seekInterval: Int

    public static let availableSpeeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    /// Each has a matching `gobackward.N`/`goforward.N` SF Symbol.
    public static let seekIntervals = [5, 10, 15, 30]

    /// 15 s is Apollo's skip amount.
    public static let `default` = VideoPlaybackSettings(defaultSpeed: 1, loopVideos: true, seekInterval: 15)

    public init(defaultSpeed: Float = 1, loopVideos: Bool = true, seekInterval: Int = 15) {
        self.defaultSpeed = defaultSpeed
        self.loopVideos = loopVideos
        self.seekInterval = seekInterval
    }

    private enum CodingKeys: String, CodingKey { case defaultSpeed, loopVideos, seekInterval }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        defaultSpeed = try container.decode(.defaultSpeed, default: d, \.defaultSpeed)
        loopVideos = try container.decode(.loopVideos, default: d, \.loopVideos)
        seekInterval = try container.decode(.seekInterval, default: d, \.seekInterval)
    }

    /// The stored speed, or 1x when it isn't one of the offered speeds (a
    /// hand-edited or corrupt value must never start a video at 0 or 10x).
    public var effectiveSpeed: Float {
        Self.availableSpeeds.contains(defaultSpeed) ? defaultSpeed : 1
    }

    /// The stored interval, or Apollo's 15 s when it isn't an offered one.
    public var effectiveSeekInterval: Int {
        Self.seekIntervals.contains(seekInterval) ? seekInterval : Self.default.seekInterval
    }

    public static func speedTitle(_ speed: Float) -> String {
        "\(String(format: "%g", Double(speed)))\u{00D7}"
    }

    public static func seekTitle(_ seconds: Int) -> String {
        "\(seconds) Seconds"
    }

    /// The skip buttons' SF Symbol, e.g. `goforward.10`.
    public static func seekSymbol(_ seconds: Int, forward: Bool) -> String {
        (forward ? "goforward." : "gobackward.") + String(seconds)
    }

    public static func seekLabel(_ seconds: Int, forward: Bool) -> String {
        (forward ? "Forward " : "Back ") + seekTitle(seconds)
    }
}

public enum VideoPlaybackPolicy {
    /// Whether a video that just ended starts over. Apollo loops silent
    /// (GIF-like) clips always and audible ones only under "Loop Videos with
    /// Audio"; Loop Videos off stops both.
    public static func loops(hasAudio: Bool, loopVideos: Bool, loopVideosWithAudio: Bool) -> Bool {
        guard loopVideos else { return false }
        return !hasAudio || loopVideosWithAudio
    }

    /// The rate hold-for-speed returns to on release: what the video was
    /// playing at, or its default speed when it was paused.
    public static func rateAfterHold(rateBeforeHold: Float, defaultRate: Float) -> Float {
        rateBeforeHold == 0 ? defaultRate : rateBeforeHold
    }
}

public enum VideoPlaybackSettingsStore {
    private static let key = "Phoebus.videoPlaybackSettings"

    public static let storage = SettingsStore<VideoPlaybackSettings>(key: key) { VideoPlaybackSettings.default }

    public static func load() -> VideoPlaybackSettings { storage.load() }

    public static func save(_ settings: VideoPlaybackSettings) { storage.save(settings) }
}

extension VideoPlaybackSettings: StoredSettingsModel {
    public static var store: SettingsStore<VideoPlaybackSettings> { VideoPlaybackSettingsStore.storage }
}
