import Foundation

/// Reborn "Floating Post Tabs": keeps up to 5 posts open as small floating
/// draggable bubbles (like chat heads) you tap to jump back into.
///
/// Sub-toggles: "Magnetic Stacking" (piles bubbles dropped near each other)
/// and "Hold to Preview" (long-press shows the post inline, releasing opens
/// it).
public struct FloatingPostTabsSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var magneticStacking: Bool
    public var holdToPreview: Bool

    public static let `default` = FloatingPostTabsSettings(enabled: false, magneticStacking: true, holdToPreview: true)

    public init(enabled: Bool, magneticStacking: Bool, holdToPreview: Bool) {
        self.enabled = enabled
        self.magneticStacking = magneticStacking
        self.holdToPreview = holdToPreview
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        magneticStacking = (try? container.decodeIfPresent(Bool.self, forKey: .magneticStacking)) ?? true
        holdToPreview = (try? container.decodeIfPresent(Bool.self, forKey: .holdToPreview)) ?? true
    }
}

public enum FloatingPostTabsSettingsStore {
    private static let key = "com.pendo324.Phoebus.floatingPostTabsSettings"

    public static let storage = SettingsStore<FloatingPostTabsSettings>(key: key) { FloatingPostTabsSettings.default }

    public static func load() -> FloatingPostTabsSettings { storage.load() }

    public static func save(_ settings: FloatingPostTabsSettings) { storage.save(settings) }
}

extension FloatingPostTabsSettings: StoredSettingsModel {
    public static var store: SettingsStore<FloatingPostTabsSettings> { FloatingPostTabsSettingsStore.storage }
}
