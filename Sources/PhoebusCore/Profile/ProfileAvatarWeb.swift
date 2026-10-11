import Foundation

/// The signed-in reddit.com page Edit Profile's Avatar row opens
/// (`ProfileAvatarWebScreen`). The URL policy lives here so it can be asserted.
public enum ProfileAvatarWeb {
    /// Where the avatar is changed: a photo or Reddit's avatar builder.
    public static let pageURL = ProfileEditLinks.webSettings

    public static func isWebScheme(_ url: URL?) -> Bool {
        let scheme = url?.scheme?.lowercased() ?? ""
        return scheme == "https" || scheme == "http"
    }

    public static func isRedditURL(_ url: URL?) -> Bool {
        guard let url, isWebScheme(url) else { return false }
        let host = url.host?.lowercased() ?? ""
        return host == "reddit.com" || host.hasSuffix(".reddit.com")
    }

    private static func path(_ url: URL, isOrUnder root: String) -> Bool {
        let path = url.path.lowercased()
        return path == root || path.hasPrefix(root + "/")
    }

    /// Where Reddit sends a settings load whose session it doesn't accept.
    public static func isLoginURL(_ url: URL?) -> Bool {
        guard let url, isRedditURL(url) else { return false }
        return path(url, isOrUnder: "/login") || path(url, isOrUnder: "/account/login")
    }

    /// Signing out on the web would end the session the app itself signs in
    /// with (for an API-Key-Free account, its only one).
    public static func isLogoutURL(_ url: URL?) -> Bool {
        guard let url, isRedditURL(url) else { return false }
        return path(url, isOrUnder: "/logout")
    }

    /// A refused session can come back as an HTTP refusal instead of a login
    /// redirect: a bad or revoked `reddit_session` gets a 403 block page.
    public static func isSessionRefusal(statusCode: Int, url: URL?) -> Bool {
        isRedditURL(url) && (statusCode == 401 || statusCode == 403)
    }

    /// The page to load again after a sign-in or a crash: the one on screen
    /// if it is a Reddit page worth returning to, else the avatar page.
    public static func reloadURL(current: URL?) -> URL {
        if let current, isRedditURL(current), !isLoginURL(current), !isLogoutURL(current) { return current }
        return pageURL
    }

    public enum TargetFrame: Equatable {
        case main
        case sub
        /// A link opening a new window.
        case newWindow
    }

    public enum NavigationDecision: Equatable {
        case allow
        case cancel
        /// Reddit sent the page to its login: the stored session is no good.
        case sessionRejected
        /// A tapped link to another site, mailto: or app link: Safari or the
        /// system, so other sites never load into the cookie-seeded view.
        case openInSystem
    }

    /// The policy for one navigation. `tapped` is a link activation.
    public static func decision(for url: URL?, tapped: Bool, frame: TargetFrame) -> NavigationDecision {
        guard let url else { return .allow }
        let tapped = tapped || frame == .newWindow
        guard isWebScheme(url) else {
            // The page's own frames (about:blank, srcdoc, data/blob previews).
            if ["about", "data", "blob"].contains(url.scheme?.lowercased() ?? "") { return .allow }
            // A script's attempt (Reddit nudging toward its own app) is dropped.
            return tapped ? .openInSystem : .cancel
        }
        // Reddit's own embeds, captcha and the uploads the page makes.
        if frame == .sub { return .allow }
        if isLoginURL(url) { return .sessionRejected }
        if isLogoutURL(url) { return .cancel }
        if isRedditURL(url) { return .allow }
        return tapped ? .openInSystem : .cancel
    }
}
