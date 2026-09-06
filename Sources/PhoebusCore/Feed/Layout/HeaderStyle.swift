import Foundation

/// Reborn's "Header Style" setting (iOS 26+): the nav bar/toolbar background
/// treatment over scrolled content. Automatic (OS default), Soft (gradient
/// blur), Hard (opaque cutoff with a dividing line), Blur (progressive
/// blur) or Hidden. Applied app-wide through SwiftUI's scroll edge effect
/// modifiers.
public enum HeaderStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case soft
    case hard
    case blur
    /// Reborn's Hidden style (#1074): removes the header edge effect entirely.
    ///
    /// Declared last because `CaseIterable` drives the picker, which lists
    /// Soft, Hard, [Blur if available], Hidden. `automatic` ("don't override
    /// the OS") stays first.
    case hidden

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .soft: return "Soft"
        case .hard: return "Hard"
        case .blur: return "Blur"
        case .hidden: return "Hidden"
        }
    }
}

public enum HeaderStyleStore {
    public static let defaultsKey = "com.pendo324.Phoebus.headerStyle"
    private static let key = defaultsKey

    public static func load() -> HeaderStyle {
        guard let raw = UserDefaults.standard.string(forKey: key), let style = HeaderStyle(rawValue: raw) else {
            return .automatic
        }
        return style
    }

    public static func save(_ style: HeaderStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: key)
    }
}
