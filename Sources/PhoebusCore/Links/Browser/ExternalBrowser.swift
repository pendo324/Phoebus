import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Reborn's "Open Links In" external-browser choice. Each supported
/// browser has a URL-scheme template used to hand an `https://` link off
/// instead of opening Safari or `SFSafariViewController`. The schemes are
/// declared in `LSApplicationQueriesSchemes`.
public enum ExternalBrowser: String, Codable, Sendable, CaseIterable, Identifiable {
    // Apollo's picker order.
    case inApp
    case safari
    case chrome
    case firefox
    case firefoxFocus
    case edge
    case dolphin
    case brave
    case duckDuckGo
    case iCabMobile

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inApp: return "In-App Safari"
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .firefoxFocus: return "Firefox Focus"
        case .edge: return "Edge"
        case .dolphin: return "Dolphin"
        case .brave: return "Brave"
        case .duckDuckGo: return "DuckDuckGo"
        case .iCabMobile: return "iCab Mobile"
        }
    }

    /// The URL scheme this browser registers, used to detect whether it is
    /// installed via `canOpenURL`.
    public var querySchemeName: String? {
        switch self {
        case .inApp, .safari: return nil
        case .chrome: return "googlechromes"
        case .dolphin: return "dolphin"
        case .duckDuckGo: return "ddgQuickLink"
        case .firefox: return "firefox"
        case .firefoxFocus: return "firefox-focus"
        case .edge: return "microsoft-edge-https"
        case .brave: return "brave"
        case .iCabMobile: return "x-icabmobile"
        }
    }

    /// Whether this browser can be offered: the two Safari modes always,
    /// others only when installed.
    @MainActor
    public var isAvailable: Bool {
        guard let scheme = querySchemeName else { return true }
        #if canImport(UIKit)
        return URL(string: "\(scheme)://").map { UIApplication.shared.canOpenURL($0) } ?? false
        #else
        return true
        #endif
    }

    /// Translates an `http(s)://` URL into this browser's custom scheme.
    /// Returns `nil` for `.inApp`/`.safari` (handled separately) or a
    /// non-web URL.
    public func translate(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
        switch self {
        case .inApp, .safari:
            return nil
        case .chrome:
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = scheme == "https" ? "googlechromes" : "googlechrome"
            return components?.url
        case .firefox:
            return URL(string: "firefox://open-url?url=\(encoded)")
        case .firefoxFocus:
            return URL(string: "firefox-focus://open-url?url=\(encoded)")
        case .edge:
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = scheme == "https" ? "microsoft-edge-https" : "microsoft-edge-http"
            return components?.url
        case .brave:
            return URL(string: "brave://open-url?url=\(encoded)")
        case .dolphin:
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "dolphin"
            return components?.url
        case .duckDuckGo:
            return URL(string: "ddgQuickLink://\(url.absoluteString)")
        case .iCabMobile:
            return URL(string: "x-icabmobile://x-callback-url/open?url=\(encoded)")
        }
    }
}

public struct ExternalBrowserSettings: Codable, Sendable, Equatable {
    public var preferredBrowser: ExternalBrowser

    public static let `default` = ExternalBrowserSettings(preferredBrowser: .inApp)

    public init(preferredBrowser: ExternalBrowser) {
        self.preferredBrowser = preferredBrowser
    }
}

public enum ExternalBrowserSettingsStore {
    private static let key = "com.pendo324.Phoebus.externalBrowserSettings"

    public static let storage = SettingsStore<ExternalBrowserSettings>(key: key) { ExternalBrowserSettings.default }

    public static func load() -> ExternalBrowserSettings { storage.load() }

    public static func save(_ settings: ExternalBrowserSettings) { storage.save(settings) }
}

extension ExternalBrowserSettings: StoredSettingsModel {
    public static var store: SettingsStore<ExternalBrowserSettings> { ExternalBrowserSettingsStore.storage }
}
