import Foundation

/// The Safari identities used where a site serves different markup to
/// apps than to browsers. `RedditAPIClient.webBrowserUserAgent` stays
/// separate: it is the one the web-session transport uses.
public enum BrowserUserAgent {
    /// iPhone Safari: article pages (OpenGraph) and the Chat token mint.
    public static let mobileSafari =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    /// Mac Safari: pages whose mobile version is JS-only (profile social
    /// links, comment vote insights).
    public static let desktopSafari =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
