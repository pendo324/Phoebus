import Foundation

/// URL parsing for Steam store links (`store.steampowered.com/app/<id>`
/// or `/sub/<id>`), reimplementing Apollo-Reborn's "Deep linking
/// support for Steam" — tapping a Steam store link opens the native
/// Steam app directly to that page instead of Safari, matching how
/// `YouTubeURLParser.nativeAppURL` routes YouTube links. Kept in
/// PhoebusCore (like `YouTubeURLParser`) so it's testable without
/// network access.
public enum SteamURLParser {
    public enum ItemKind: Sendable, Equatable {
        case app
        case sub
    }

    /// Extracts an (kind, id) pair from a Steam store URL, or nil if
    /// the URL isn't a recognized Steam app/sub page.
    public static func extractItem(from url: URL) -> (kind: ItemKind, id: String)? {
        guard let host = url.host?.lowercased(), host.contains("steampowered.com") else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }
        let kindString = components[0].lowercased()
        let id = components[1]
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        switch kindString {
        case "app": return (.app, id)
        case "sub": return (.sub, id)
        default: return nil
        }
    }

    /// Builds the `steam://` URL that opens the native Steam app
    /// directly to the store page for an app/sub ID (Steam's own
    /// registered custom scheme — `steam://store/<appid>` /
    /// `steam://store/sub/<subid>` are supported by the client).
    public static func nativeAppURL(kind: ItemKind, id: String) -> URL? {
        switch kind {
        case .app: return URL(string: "steam://store/\(id)")
        case .sub: return URL(string: "steam://store/sub/\(id)")
        }
    }
}
