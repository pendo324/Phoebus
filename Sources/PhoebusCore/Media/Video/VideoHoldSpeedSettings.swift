import Foundation

/// Apollo's "Hold for Video Speed" setting (Reborn issue #78):
/// press-and-hold the right third of a fullscreen video to play it at
/// a chosen speed while held; release restores the previous rate.
///
/// Defaults: master toggle on, hold speed 2x, options
/// 0.25x/0.5x/0.75x/1.25x/1.5x/2x, so the gesture can speed video up or
/// slow it down.
public struct VideoHoldSpeedSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var holdSpeed: Float

    public static let availableSpeeds: [Float] = [0.25, 0.5, 0.75, 1.25, 1.5, 2]

    public static let `default` = VideoHoldSpeedSettings(isEnabled: true, holdSpeed: 2)

    public init(isEnabled: Bool = true, holdSpeed: Float = 2) {
        self.isEnabled = isEnabled
        self.holdSpeed = holdSpeed
    }
}

public enum VideoHoldSpeedStore {
    private static let key = "Phoebus.videoHoldSpeedSettings"

    public static let storage = SettingsStore<VideoHoldSpeedSettings>(key: key) { VideoHoldSpeedSettings.default }

    public static func load() -> VideoHoldSpeedSettings { storage.load() }

    public static func save(_ settings: VideoHoldSpeedSettings) { storage.save(settings) }
}

extension VideoHoldSpeedSettings: StoredSettingsModel {
    public static var store: SettingsStore<VideoHoldSpeedSettings> { VideoHoldSpeedStore.storage }
}
