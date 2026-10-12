import Foundation

/// Reborn "True Black Keyboard" (#1316, real key `TrueBlackKeyboardMode`,
/// default Off): which appearances paint the system keyboard's background
/// pure black for OLED screens. Raw values are Reborn's stored integers.
public enum TrueBlackKeyboardMode: Int, Codable, Sendable, CaseIterable, Identifiable {
    case off = 0
    case darkOnly = 1
    case lightOnly = 2
    case always = 3

    public var id: Int { rawValue }
    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .darkOnly: return "Dark Mode Only"
        case .lightOnly: return "Light Mode Only"
        case .always: return "Always"
        }
    }

    /// Whether the keyboard goes true black under the app's current appearance.
    ///
    /// A light app needs the dark key set to stay readable on black, which
    /// UIKit only offers from iOS 15 (`darkKeysAvailable`); without it a light
    /// app keeps the stock keyboard.
    public func paintsBlack(isDark: Bool, darkKeysAvailable: Bool) -> Bool {
        if !isDark && !darkKeysAvailable { return false }
        switch self {
        case .off: return false
        case .darkOnly: return isDark
        case .lightOnly: return !isDark
        case .always: return true
        }
    }

    /// Whether the keyboard should be built with the dark key set: a black
    /// keyboard under a light-mode app.
    public func usesDarkKeys(isDark: Bool, darkKeysAvailable: Bool) -> Bool {
        !isDark && paintsBlack(isDark: isDark, darkKeysAvailable: darkKeysAvailable)
    }
}
