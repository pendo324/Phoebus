import Foundation

/// Decides whether the app should currently be in its DARK or LIGHT
/// theme, per the real "Automatic Switch Threshold" section.
///
/// `ThemeAutoSwitchSettings` models every row on that screen: system-
/// appearance following, the three switch modes, the brightness
/// threshold, and both schedule times. This resolver is what actually
/// consumes those persisted values.
public enum ThemeAutoSwitchResolver {
    /// What the theme should be right now, or nil to leave it alone.
    ///
    /// Nil rather than a default so `.manual` genuinely means manual:
    /// returning a value there would fight the user's own choice on
    /// every evaluation.
    public static func shouldUseDarkTheme(
        settings: ThemeAutoSwitchSettings,
        systemIsDark: Bool,
        screenBrightness: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool? {
        // The system toggle outranks the switch mode: Apollo presents it above
        // that section as a master control.
        if settings.useSystemLightDarkMode { return systemIsDark }

        switch settings.switchMode {
        case .manual:
            return nil
        case .brightness:
            // "Switch automatically based on screen brightness", a
            // DIM screen implies a dark environment, so dark theme
            // applies at or below the threshold.
            return screenBrightness <= settings.brightnessThreshold
        case .schedule:
            let minutes = calendar.component(.hour, from: now) * 60
                + calendar.component(.minute, from: now)
            // "Use Location Sunset & Sunrise": dark from sunset to
            // sunrise at the stored coordinates; falls back to the fixed
            // times until a location has been found.
            if settings.useLocationSunsetSunrise,
               let coordinates = SunsetCoordinatesStore.load(),
               let times = SolarTimes.sunriseSunset(on: now, at: coordinates, calendar: calendar) {
                return isDarkPeriod(
                    minutes: minutes,
                    darkStart: SolarTimes.minutes(of: times.sunset, calendar: calendar),
                    lightStart: SolarTimes.minutes(of: times.sunrise, calendar: calendar))
            }
            return isDarkPeriod(
                minutes: minutes,
                darkStart: settings.darkModeStartMinutes,
                lightStart: settings.lightModeStartMinutes)
        }
    }

    /// Whether `minutes` falls in the dark window.
    ///
    /// Handles the ordinary case where dark starts in the evening and
    /// light the next morning, i.e. the window WRAPS midnight. A naive
    /// `minutes >= darkStart && minutes < lightStart` is false all
    /// night for the default 20:00/07:00 pair, which is precisely the
    /// configuration most people use.
    public static func isDarkPeriod(minutes: Int, darkStart: Int, lightStart: Int) -> Bool {
        if darkStart == lightStart { return false }
        if darkStart < lightStart {
            // Same-day window, e.g. dark 07:00 -> light 20:00.
            return minutes >= darkStart && minutes < lightStart
        }
        // Wrapping window, e.g. dark 20:00 -> light 07:00 next day.
        return minutes >= darkStart || minutes < lightStart
    }

    /// The theme to switch to, given the current one.
    ///
    /// Matches on the theme's NAME so a switch keeps the user's chosen
    /// theme family (Apollo's own themes come in light/dark pairs
    /// sharing a name) rather than dropping them onto a stock default.
    /// Returns nil when already correct or when no counterpart exists.
    public static func counterpart(for theme: Theme, wantsDark: Bool, in themes: [Theme]) -> Theme? {
        guard theme.isDark != wantsDark else { return nil }
        if let paired = themes.first(where: { $0.name == theme.name && $0.isDark == wantsDark }) {
            return paired
        }
        // A gallery theme is only persisted in the mode the user
        // picked, so its counterpart is not in the available list at
        // all, it is derived on demand rather than looked up, since
        // the counterpart variant may never have been written to disk.
        return galleryCounterpart(for: theme, wantsDark: wantsDark)
    }

    /// Rebuilds the other mode of a gallery theme from its own slug.
    static func galleryCounterpart(for theme: Theme, wantsDark: Bool) -> Theme? {
        let prefix = "gallery_"
        guard theme.id.hasPrefix(prefix) else { return nil }
        var slug = String(theme.id.dropFirst(prefix.count))
        for suffix in ["_dark", "_light"] where slug.hasSuffix(suffix) {
            slug = String(slug.dropLast(suffix.count))
        }
        guard let gallery = ThemeGallery.all.first(where: { $0.slug == slug }) else { return nil }
        return gallery.asTheme(mode: wantsDark ? .dark : .light)
    }
}
