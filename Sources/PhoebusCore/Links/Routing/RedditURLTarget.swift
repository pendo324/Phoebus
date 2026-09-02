import Foundation

/// Parses reddit.com URLs into a navigable target, used both by the
/// Open-In share extension deep link and to route incoming
/// phoebus:// URLs from any other source (widget taps, etc).
public enum RedditURLTarget: Hashable, Sendable {
    case post(subreddit: String, id: String)
    /// A comment permalink, `/r/<sub>/comments/<post>/<slug>/<comment>`:
    /// the thread opened on that comment. This is what backend
    /// notification taps for replies and mentions carry.
    case comment(subreddit: String, postID: String, commentID: String)
    case subreddit(String)
    case user(String)
    /// Reimplements Apollo's "Open Multireddit" Siri shortcut — opens
    /// `/user/<owner>/m/<name>` or `/me/m/<name>`, matching Reddit's
    /// real multireddit URL structure.
    case multireddit(String)
    case unknown(URL)

    public static func parse(_ url: URL) -> RedditURLTarget {
        // Rewrite wrapper URLs before matching: `reddit.com/media?url=<encoded>`
        // wraps an image URL, and imgur has hyphenated-title links. See
        // `ShareLinkNormalizer`.
        if let rewritten = ShareLinkNormalizer.normalized(url) {
            return parse(rewritten)
        }
        let components = url.pathComponents.filter { $0 != "/" }

        // /r/<subreddit>/comments/<id>/...
        if let rIndex = components.firstIndex(of: "r"),
           components.count > rIndex + 3,
           components[rIndex + 2] == "comments" {
            if components.count > rIndex + 5, !components[rIndex + 5].isEmpty {
                return .comment(subreddit: components[rIndex + 1], postID: components[rIndex + 3],
                                commentID: components[rIndex + 5])
            }
            return .post(subreddit: components[rIndex + 1], id: components[rIndex + 3])
        }

        // /comments/<id>[/<slug>/<comment>], the subreddit-less form
        // Reddit's share button produces.
        if components.first == "comments", components.count > 1 {
            if components.count > 3, !components[3].isEmpty {
                return .comment(subreddit: "", postID: components[1], commentID: components[3])
            }
            return .post(subreddit: "", id: components[1])
        }

        // /user/<owner>/m/<name> or /me/m/<name>
        if let mIndex = components.firstIndex(of: "m"), mIndex > 0, components.count > mIndex + 1 {
            return .multireddit(components[mIndex + 1])
        }

        // /r/<subreddit>
        if let rIndex = components.firstIndex(of: "r"), components.count > rIndex + 1 {
            return .subreddit(components[rIndex + 1])
        }

        // /u/<username> or /user/<username>
        if let uIndex = components.firstIndex(where: { $0 == "u" || $0 == "user" }),
           components.count > uIndex + 1 {
            return .user(components[uIndex + 1])
        }

        return .unknown(url)
    }

    /// Parses an incoming `phoebus://` deep link.
    ///
    /// Two forms are accepted:
    ///
    ///   1. `phoebus://open?url=<percent-encoded reddit url>` -
    ///      what `PhoebusOpenIn`'s ActionViewController produces.
    ///   2. `phoebus://reddit.com/<path>` - scheme and host
    ///      swapped in place, path and query preserved.
    ///
    /// The second form is the one a hand-built Shortcut can produce with a
    /// single regex replace, and what Apollo-Reborn's Shortcut recipe and
    /// userscript emit: only the scheme + host are rewritten, so comment
    /// permalinks, profiles, and `/s/` share links all open correctly.
    public static func parseAppScheme(_ url: URL) -> RedditURLTarget? {
        guard url.scheme == "phoebus" else { return nil }

        // Form 1: an explicitly encoded URL.
        if url.host == "open" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let redditURLString = components.queryItems?
                      .first(where: { $0.name == "url" })?.value,
                  let redditURL = URL(string: redditURLString) else {
                return nil
            }
            return parse(redditURL)
        }

        // Form 2: the host IS the reddit host. Rebuild an https URL
        // from the same components so the path, query and fragment
        // survive untouched.
        guard let host = url.host?.lowercased(),
              host == "reddit.com" || host.hasSuffix(".reddit.com") || host == "redd.it",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        guard let redditURL = components.url else { return nil }
        return parse(redditURL)
    }
}

/// Reborn's quick actions: home-screen shortcut items and
/// `apollo://reborn/<action>` URLs that open Search, the Home
/// front-page feed, Inbox, Profile or Settings. Only these five
/// are claimed ("claiming a URL we can't perform swallows it").
public enum QuickAction: String, CaseIterable, Sendable {
    case home, search, inbox, profile, settings

    /// `UIApplicationShortcutItem.type` prefix.
    public static let typePrefix = "com.pendo324.Phoebus.quickaction."

    public var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .inbox: return "Inbox"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .inbox: return "envelope"
        case .profile: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }

    /// `phoebus://reborn/<action>` (Reborn's `apollo://reborn/...`).
    public static func parse(_ url: URL) -> QuickAction? {
        guard url.scheme?.lowercased() == "phoebus",
              url.host?.lowercased() == "reborn" else { return nil }
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Reborn's chat push links (`apollo://reborn/chat`,
        // `.../chat/requests`, `.../chat/room/<id>`) land on the Inbox
        // tab, where this app's Chat list lives.
        if path == "chat" || path.hasPrefix("chat/") { return .inbox }
        return QuickAction(rawValue: path)
    }

    public static func parse(shortcutType type: String) -> QuickAction? {
        guard type.hasPrefix(typePrefix) else { return nil }
        return QuickAction(rawValue: String(type.dropFirst(typePrefix.count)))
    }
}

/// Hands a quick action from the app delegate / URL handler to the tab
/// view, which may not exist yet on a cold launch.
@MainActor
public final class QuickActionRouter {
    public static let shared = QuickActionRouter()
    public var pending: QuickAction? {
        didSet { if pending != nil { NotificationCenter.default.post(name: .apolloQuickAction, object: nil) } }
    }
    private init() {}
}

