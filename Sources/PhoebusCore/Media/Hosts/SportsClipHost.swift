import Foundation

/// Recognizes Reborn's "sports clip" host links: six sports-clip CDN hosts
/// Reborn resolves to a playable inline video, widening its
/// Streamable-recognition regex.
///
/// Only host recognition and page-URL passthrough happen here;
/// `SportsClipView` resolves the playable URL via a generic OpenGraph
/// `og:video` scrape of the share page. That works for the
/// streamin/bangr/dropr/streamain family; streamff's og:video and the two
/// dubz CDN shapes fall back to the plain link card.
public enum SportsClipHost {
    /// Reborn's host list.
    private static let hosts: Set<String> = [
        "streamin.link", "streamin.me", "streamin.one", "streamin.fun", "streamin.top",
        "streamff.pro", "streamff.com", "streamff.link",
        "streamain.com", "streama.in",
        "bangr.im",
        "dubz.link", "dubz.co", "dubz.live",
        "dropr.co",
    ]

    public static func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains(host) || hosts.contains { host.hasSuffix(".\($0)") }
    }
}
