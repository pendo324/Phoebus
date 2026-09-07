import Foundation

/// Reborn "Feed Video Scrubber" (FeedVideoScrubber): grab the bottom
/// progress strip of an inline video and slide to scrub it without opening
/// the fullscreen player. Covers feed rows and the post's video header;
/// default off.
public struct FeedVideoScrubberSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool

    public static let `default` = FeedVideoScrubberSettings(isEnabled: false)

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

public enum FeedVideoScrubberStore {
    private static let key = "Phoebus.feedVideoScrubberSettings"

    public static let storage = SettingsStore<FeedVideoScrubberSettings>(key: key) { FeedVideoScrubberSettings.default }

    public static func load() -> FeedVideoScrubberSettings { storage.load() }

    public static func save(_ settings: FeedVideoScrubberSettings) { storage.save(settings) }
}

extension FeedVideoScrubberSettings: StoredSettingsModel {
    public static var store: SettingsStore<FeedVideoScrubberSettings> { FeedVideoScrubberStore.storage }
}
