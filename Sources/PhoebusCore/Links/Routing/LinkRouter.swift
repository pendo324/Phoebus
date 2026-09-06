import Foundation

/// Central routing for a tapped link. Three settings decide where it opens:
///
///  - `openRedditLinksInApollo` ("Open Reddit Links in Apollo"): a
///    reddit.com URL for content Apollo can display opens natively
///    (subreddit/post/profile screen) instead of a web view.
///  - `openTwitterLinksIn` ("Open Tweets in…"): in-app browser vs the
///    X/Twitter app.
///  - `ExternalBrowserSettings.preferredBrowser` ("Open Links In").
///
/// `LinkRouter.route` returns a decision rather than navigating, so it is a
/// pure function testable in the smoke tests; each call site handles the
/// native case with its own navigation.
public enum LinkDestination: Equatable {
    /// Open natively in Apollo (subreddit / post / user).
    case native(RedditURLTarget)
    /// Hand to the X/Twitter app.
    /// The tweet/profile URL, plus the client the user picked, since a
    /// route that only said "the X app" couldn't honour Twitterrific
    /// or Tweetbot.
    case twitterApp(URL, client: TwitterLinkDestination)
    /// Hand to the user's preferred external browser, or Safari.
    case externalBrowser(URL)
    /// Open in the in-app browser.
    case inApp(URL)
}

public enum LinkRouter {
    /// Decides where `url` should open: Reddit-native routing wins first, then
    /// Twitter, then the general browser preference.
    ///
    /// Resolves a possibly scheme-relative Reddit link to an absolute URL:
    /// Reddit serves a crosspost parent's `url` as a bare path like
    /// `/r/pics/comments/abc/title/`, which fails `isRedditURL` (no host) and
    /// crashes `SFSafariViewController(url:)` (no scheme).
    public static func absoluteRedditURL(_ url: URL) -> URL {
        guard url.scheme == nil, url.host == nil else { return url }
        let path = url.absoluteString
        guard path.hasPrefix("/") else { return url }
        return URL(string: "https://www.reddit.com" + path) ?? url
    }

    public static func route(
        _ rawURL: URL,
        general: GeneralSettings = GeneralSettingsStore.load(),
        browser: ExternalBrowserSettings = ExternalBrowserSettingsStore.load()
    ) -> LinkDestination {
        let url = absoluteRedditURL(rawURL)
        // 1. Reddit links Apollo can render itself.
        if general.openRedditLinksInApollo, isRedditURL(url) {
            let target = RedditURLTarget.parse(url)
            // `.unknown` means the parser could not map the URL onto a
            // screen (a wiki page, a settings deep link, an image
            // host); those must still open in a browser rather than
            // navigating nowhere.
            if case .unknown = target {
                // fall through to browser handling below
            } else {
                return .native(target)
            }
        }

        // 2. Tweets, when the user prefers a dedicated X client.
        let twitterClients: [TwitterLinkDestination] = [.twitterApp, .twitterrific, .tweetbot, .aviary, .spring]
        if twitterClients.contains(general.openTwitterLinksIn), isTwitterURL(url) {
            return .twitterApp(url, client: general.openTwitterLinksIn)
        }
        // "In-App Safari" and "Default Browser" for tweets override the
        // general browser choice (stock's `inAppSafari` / `externalBrowser`).
        if isTwitterURL(url) {
            if general.openTwitterLinksIn == .inApp { return .inApp(url) }
            if general.openTwitterLinksIn == .externalBrowser { return .externalBrowser(url) }
        }

        // 3. The general "Open Links In" browser preference.
        switch browser.preferredBrowser {
        case .inApp:
            return .inApp(url)
        default:
            return .externalBrowser(url)
        }
    }

    /// Reddit web hosts Apollo can route natively. Excludes i.redd.it /
    /// v.redd.it / preview.redd.it: those are media URLs, not screens.
    public static func isRedditURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return bare == "reddit.com"
            || bare == "old.reddit.com"
            || bare == "new.reddit.com"
            || bare == "np.reddit.com"
            || bare == "sh.reddit.com"
            || bare == "m.reddit.com"
            || bare == "redd.it"
    }

    public static func isTwitterURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return bare == "twitter.com" || bare == "x.com" || bare == "mobile.twitter.com"
    }

    /// A tweet id or a profile handle, whichever this URL names; every client
    /// template takes one or the other, never a whole web URL.
    public enum TwitterTarget: Equatable {
        case status(id: String)
        case profile(handle: String)
    }

    /// Parses `/user/status/12345` or `/user`.
    public static func twitterTarget(for url: URL) -> TwitterTarget? {
        guard isTwitterURL(url) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let index = parts.firstIndex(of: "status"), parts.count > index + 1 {
            let id = parts[index + 1].prefix { $0.isNumber }
            return id.isEmpty ? nil : .status(id: String(id))
        }
        guard let handle = parts.first, !handle.isEmpty,
              !["i", "home", "search", "explore"].contains(handle.lowercased()) else { return nil }
        return .profile(handle: handle)
    }

    /// The deep link that opens this tweet/profile in `client`, from the
    /// client's template:
    ///
    ///     twitter://user?screen_name=        twitter://status?id=
    ///     twitterrific:///profile?screen_name=  twitterrific:///tweet?id=
    ///     tweetbot:///user_profile/          tweetbot:///status/
    public static func twitterAppURL(
        for url: URL,
        client: TwitterLinkDestination = .twitterApp
    ) -> URL? {
        guard let target = twitterTarget(for: url) else { return nil }
        switch (client, target) {
        case (.twitterApp, .status(let id)):
            return URL(string: "twitter://status?id=\(id)")
        case (.twitterApp, .profile(let handle)):
            return URL(string: "twitter://user?screen_name=\(handle)")
        case (.twitterrific, .status(let id)):
            return URL(string: "twitterrific:///tweet?id=\(id)")
        case (.twitterrific, .profile(let handle)):
            return URL(string: "twitterrific:///profile?screen_name=\(handle)")
        case (.tweetbot, .status(let id)):
            return URL(string: "tweetbot:///status/\(id)")
        case (.tweetbot, .profile(let handle)):
            return URL(string: "tweetbot:///user_profile/\(handle)")
        // No URL template is known for Aviary or Spring, so they fall back to
        // the web URL rather than a guessed one.
        case (.aviary, _), (.spring, _), (.inApp, _), (.externalBrowser, _):
            return nil
        }
    }
}


public enum RedditLinkNavigator {
    /// Requests native navigation to `target`.
    public static func open(_ target: RedditURLTarget) {
        NotificationCenter.default.post(
            name: .apolloOpenRedditTarget,
            object: nil,
            userInfo: ["target": target]
        )
    }
}
