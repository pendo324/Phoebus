import Foundation

/// Apollo's App Icon picker's standard icons. Phoebus ships none of
/// Apollo's artwork, so only the primary icon is left: "Default", which is
/// Phoebus's own icon. Every other icon is a Liquid Glass pack icon
/// (`LiquidGlassIconOption`).
public struct AppIconOption: Sendable, Equatable, Identifiable {
    /// The short identifier, used to build the `CFBundleAlternateIcons` key
    /// (`AppIcon-<id>`) and asset filename.
    public var id: String
    public var displayName: String
    /// The designer Apollo credits under the name, where it does.
    public var artist: String?

    public init(id: String, displayName: String, artist: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.artist = artist
    }

    /// `nil` alternateIconName means the primary icon.
    public var alternateIconName: String? {
        id == "original" ? nil : "AppIcon-\(id)"
    }

    /// The icon's PNG base name at the bundle root (`@2x`/`@3x` appended). The
    /// primary icon is the Phoebus pack icon's default look.
    public var iconFileName: String {
        id == "original" ? "LGIcon-phoebus60x60" : "AppIcon-\(id)60x60"
    }

    /// "Default": the settings root row reads "App Icon · Default".
    public static let original = AppIconOption(id: "original", displayName: "Default")

    /// The standard catalog: the primary icon only.
    public static let all: [AppIconOption] = [.original]
}

public enum AppIconStore {
    private static let key = "com.pendo324.Phoebus.selectedAppIcon"

    public static let storage = CustomSettingsSource<AppIconOption>(
        key: key,
        load: { defaults in defaults.string(forKey: key).flatMap { raw in AppIconOption.all.first { $0.id == raw } } ?? .original },
        save: { option, defaults in defaults.set(option.id, forKey: key) })

    public static func load() -> AppIconOption { storage.load() }

    public static func save(_ option: AppIconOption) { storage.save(option) }
}
