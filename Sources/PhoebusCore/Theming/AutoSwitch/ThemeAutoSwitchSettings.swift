import Foundation

/// Apollo's Themes screen settings: the "Use System Light/Dark Mode" and "Enable Quick
/// Switch" toggles (`ThemeToggleGestureEnabled`; footer "If enabled, at any time
/// long-press the top navigation bar to quickly toggle themes."), and the
/// "Automatic Switch Threshold" section (brightness-based, sunset/sunrise or
/// manual-only modes, with a slider and time pickers).
public struct ThemeAutoSwitchSettings: Codable, Sendable, Equatable {
    /// `UseSystemLightDarkMode`: when true, the light/dark theme follows the
    /// system appearance instead of manual/scheduled switching.
    public var useSystemLightDarkMode: Bool
    /// `ThemeToggleGestureEnabled` — long-press the nav bar to
    /// quick-toggle the active theme.
    public var quickSwitchEnabled: Bool
    /// The "Automatic Switch Threshold" section mode; the three options are verbatim.
    public var switchMode: ThemeSwitchMode
    /// Brightness threshold (0...1) used by the brightness-based mode.
    public var brightnessThreshold: Double
    /// Times behind the "Dark Mode Starts" / "Light Mode Starts" rows.
    public var darkModeStartMinutes: Int
    public var lightModeStartMinutes: Int
    /// The "Use Location Sunset & Sunrise" row.
    public var useLocationSunsetSunrise: Bool

    /// Apollo's defaults: follow the system, Quick Switch on, 25% brightness,
    /// sunset/sunrise by location.
    public static let `default` = ThemeAutoSwitchSettings()

    public init(
        useSystemLightDarkMode: Bool = true,
        quickSwitchEnabled: Bool = true,
        switchMode: ThemeSwitchMode = .manual,
        brightnessThreshold: Double = 0.25,
        darkModeStartMinutes: Int = 20 * 60,
        lightModeStartMinutes: Int = 7 * 60,
        useLocationSunsetSunrise: Bool = true
    ) {
        self.useSystemLightDarkMode = useSystemLightDarkMode
        self.quickSwitchEnabled = quickSwitchEnabled
        self.switchMode = switchMode
        self.brightnessThreshold = brightnessThreshold
        self.darkModeStartMinutes = darkModeStartMinutes
        self.lightModeStartMinutes = lightModeStartMinutes
        self.useLocationSunsetSunrise = useLocationSunsetSunrise
    }
}

/// The three options of Apollo's "Automatic Switch Threshold" section, verbatim.
public enum ThemeSwitchMode: String, Codable, CaseIterable, Sendable {
    // On-screen order: Manually, Scheduled, Automatically.
    case manual
    case schedule
    case brightness

    /// Row title: short Manually/Scheduled/Automatically labels, not the
    /// longer subtitle strings.
    public var title: String {
        switch self {
        case .manual: return "Manually"
        case .schedule: return "Scheduled"
        case .brightness: return "Automatically"
        }
    }

    /// Row subtitle, verbatim.
    public var subtitle: String {
        switch self {
        case .manual: return "Only switch when you want"
        case .schedule: return "Switch at sunset/sunrise or at specific times"
        case .brightness: return "Switch automatically based on screen brightness"
        }
    }
}

public enum ThemeAutoSwitchSettingsStore {
    public static let defaultsKey = "com.pendo324.Phoebus.themeAutoSwitchSettings"
    private static let key = defaultsKey

    public static let storage = SettingsStore<ThemeAutoSwitchSettings>(key: key) { ThemeAutoSwitchSettings.default }

    public static func load() -> ThemeAutoSwitchSettings { storage.load() }

    public static func save(_ settings: ThemeAutoSwitchSettings) { storage.save(settings) }
}

extension ThemeAutoSwitchSettings: StoredSettingsModel {
    public static var store: SettingsStore<ThemeAutoSwitchSettings> { ThemeAutoSwitchSettingsStore.storage }
}
