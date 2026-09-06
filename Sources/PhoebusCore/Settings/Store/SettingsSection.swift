import Foundation

/// Full inventory of Apollo's settings sections.
///
/// Includes the full section list to match Apollo's real UX/navigation
/// shape, marking sections not yet in scope as disabled (visible,
/// tappable-to-explain, non-functional) rather than removing them.
///
/// `.appearance` maps to the real density/layout settings screen
/// (voting button position, thumbnail position/size, subreddit icons),
/// which is a genuinely distinct screen from Theme (color themes +
/// day/night scheduling); both are surfaced from this one section.
///
/// `CaseIterable`'s `allCases` order (used directly by `SettingsScreen`'s
/// `ForEach`) matches real Apollo's own row order.
public enum SettingsSection: String, CaseIterable, Sendable, Identifiable {
    // Order matches the real Settings screen: General, Appearance,
    // Notifications, App Icon, Face ID & Passcode, Filters & Blocks,
    // Gestures. Theme/Accounts/Low Data Mode/Portrait Lock/Marking Read
    // are not in that main group; kept but moved below it.
    case general
    case appearance
    case notifications
    case appIcon
    case security
    case filters
    case gestures
    case theme
    // Apollo-Reborn's "Community Icon Pack" is folded into `appIcon`:
    // both are alternate-icon pickers over the same mechanism.
    case accounts
    case lowDataMode
    case portraitLock
    case markReadHiding
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .theme: return "Theme"
        case .lowDataMode: return "Low Data Mode"
        case .general: return "General"
        case .appearance: return "Appearance"
        case .gestures: return "Gestures"
        case .filters: return "Filters & Blocks"
        case .notifications: return "Notifications"
        case .security: return "Passcode"
        case .portraitLock: return "Portrait Lock"
        case .markReadHiding: return "Marking Read / Hiding"
        case .appIcon: return "App Icon"
        case .about: return "About"
        }
    }

    /// Reborn's root-screen icon table, verbatim.
    public var systemImage: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .theme: return "moon.fill"
        case .lowDataMode: return "gauge.with.dots.needle.bottom.50percent"
        case .gestures: return "hand.tap.fill"
        case .filters: return "nosign"
        case .notifications: return "bell.fill"
        case .security: return "lock.fill"
        case .portraitLock: return "lock.rotation"
        case .markReadHiding: return "eye.slash"
        case .appIcon: return "app.badge"
        case .about: return "info.circle.fill"
        }
    }

    /// Real rows render as iOS-style Settings rows: a white glyph on a
    /// rounded, per-row colored tile. Colors match the real app's tile
    /// colors with a semantically equivalent SF Symbol standing in for
    /// its copyrighted icon art.
    public var iconTintRGB: (red: Double, green: Double, blue: Double) {
        switch self {
        case .general: return (0.56, 0.56, 0.57)
        case .appearance: return (0.25, 0.56, 0.97)
        case .theme: return (0.35, 0.34, 0.84)
        case .appIcon: return (0.70, 0.14, 0.47)
        case .security: return (0.92, 0.29, 0.38)
        case .filters: return (0.40, 0.81, 0.40)
        case .gestures: return (0.44, 0.48, 0.97)
        case .accounts: return (0.25, 0.56, 0.97)
        case .lowDataMode: return (1.00, 0.58, 0.00)
        case .notifications: return (0.92, 0.32, 0.30)
        case .portraitLock: return (0.35, 0.34, 0.84)
        case .markReadHiding: return (0.56, 0.56, 0.57)
        case .about: return (0.39, 0.39, 0.40)
        }
    }

    /// Sections fully implemented in this rewrite. Everything else is
    /// shown (to match Apollo's navigation shape) but disabled.
    public var isImplemented: Bool {
        switch self {
        case .gestures, .about, .filters, .markReadHiding, .appIcon, .appearance, .notifications,
             .security, .portraitLock, .theme, .accounts:
            return true
        case .lowDataMode:
            return false
        case .general:
            return true
        }
    }

    /// Explains why a disabled section isn't active yet, shown as a
    /// disabled-row subtitle.
    public var disabledReason: String? {
        switch self {
        case .accounts:
            return nil
        case .lowDataMode:
            return "Not yet implemented"
        case .theme:
            return nil
        case .general:
            return nil
        case .appearance:
            return nil
        case .filters:
            return nil
        case .notifications:
            return nil
        case .security:
            return nil
        case .portraitLock:
            return nil
        case .markReadHiding:
            return nil
        case .appIcon:
            return nil
        case .gestures, .about:
            return nil
        }
    }
}
