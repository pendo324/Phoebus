import Foundation

/// What went wrong when Reddit refused an in-app web sign-in, and how to
/// say so (Reborn #1236). Pure, so the smoke suite can pin it;
/// `CustomOAuthSession` presents it.
public enum OAuthConsentFailure: Equatable, Sendable {
    /// Accept was tapped and `/svc/shreddit/oauth-grant` answered an
    /// error: Reddit's new consent page doesn't check the key until then.
    case grantRejected
    /// The authorize page itself answered an error (Old Reddit checks up
    /// front and names the bad field).
    case authorizeRejected

    public struct Alert: Equatable, Sendable {
        public let title: String
        public let message: String
    }

    static func isRedditHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "reddit.com" || host.hasSuffix(".reddit.com")
    }

    /// nil for anything that should load as usual, including errors on
    /// login and challenge pages.
    public static func classify(url: URL, status: Int) -> OAuthConsentFailure? {
        guard status >= 400, isRedditHost(url.host) else { return nil }
        if url.path == "/svc/shreddit/oauth-grant" { return .grantRejected }
        if url.path.hasPrefix("/api/v1/authorize") { return .authorizeRejected }
        return nil
    }

    /// Reborn's copy, with its settings path (the same here: Settings →
    /// Apollo Reborn → Accounts & API Keys).
    public static func alert(status: Int, offerOldReddit: Bool, hasCustomKey: Bool) -> Alert {
        let settingsFix = hasCustomKey
            ? "check the Reddit API Key and Redirect URI in Settings \u{2192} Apollo Reborn \u{2192} Accounts & API Keys"
            : "add your Reddit API Key in Settings \u{2192} Apollo Reborn \u{2192} Accounts & API Keys (none is set there)"
        if status == 400 {
            return Alert(title: "Reddit Didn't Accept This API Key",
                         message: "The Reddit API Key and Redirect URI used for this sign-in don't match a Reddit app, so Reddit won't connect your account. Both have to match the app exactly (for Dystopia, the Redirect URI is dystopia://response).\n\nTo fix it, \(settingsFix), or sign in without an API key instead.")
        }
        // Can be an outage, but Old Reddit also answers some malformed
        // client ids with a 500 page instead of its 400 one.
        let retry = offerOldReddit
            ? "Wait a few minutes and try again, or switch to Old Reddit and accept there."
            : "Wait a few minutes and try again."
        return Alert(title: "Reddit Couldn't Finish Signing In",
                     message: "Reddit returned an error (HTTP \(status)). \(retry)\n\nIf it keeps happening, \(settingsFix).")
    }

    /// The authorize request on Old Reddit, which checks the key up front.
    public static func oldRedditURL(_ authorizeURL: URL) -> URL {
        guard var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false),
              isRedditHost(components.host) else { return authorizeURL }
        components.host = "old.reddit.com"
        return components.url ?? authorizeURL
    }
}
