import Foundation

/// Builds a shareable Reddit-compatible URL for a permalink path.
///
/// Apollo-Reborn has a 4-way "Share Link Host" picker (Reddit / old.reddit /
/// vxReddit / fxReddit); base Apollo has a narrower "Share Old.reddit Links"
/// toggle. `GeneralSettings.shareLinkHost` (`ShareLinkHost`) models the
/// picker; the `useOldReddit: Bool` parameter is kept for existing call
/// sites and maps onto the host enum.
public enum ShareLinkBuilder {
    /// Preferred entry point: builds a share URL for the given host. `.reddit`
    /// keeps the original reddit.com host; the other three swap in their
    /// domain while preserving the path.
    public static func url(forPermalinkPath path: String, host: ShareLinkHost) -> URL {
        let domain = host.domain ?? "reddit.com"
        let urlString = "https://\(domain)\(path)"
        return URL(string: urlString) ?? URL(string: "https://\(domain)")!
    }

    /// Boolean overload for older call sites: `true` maps to `.oldReddit`,
    /// `false` to `.reddit` (vxReddit/fxReddit are only reachable via the
    /// `host:` overload and `GeneralSettings.shareLinkHost`).
    public static func url(forPermalinkPath path: String, useOldReddit: Bool) -> URL {
        url(forPermalinkPath: path, host: useOldReddit ? .oldReddit : .reddit)
    }

    /// Builds the share-sheet text for a post per
    /// `GeneralSettings.sharePostIncludesTitle` ("Share Includes Title",
    /// Apollo's `SharePostIncludesTitle`): when enabled the title is prepended
    /// so the item reads as "<title> <url>"; when disabled only the URL string
    /// is returned so callers can pass a single share item.
    public static func shareText(title: String, url: URL, includeTitle: Bool) -> String {
        includeTitle ? "\(title) \(url.absoluteString)" : url.absoluteString
    }
}

extension RedditPost {
    /// The post's permalink on the user's chosen share host.
    public func shareURL(host: ShareLinkHost = GeneralSettingsStore.load().effectiveShareLinkHost) -> URL {
        ShareLinkBuilder.url(forPermalinkPath: permalink, host: host)
    }

    /// What Share hands the share sheet: the URL, prefixed with the title
    /// when "Share Includes Title" is on.
    public func shareText(settings: GeneralSettings = GeneralSettingsStore.load()) -> String {
        ShareLinkBuilder.shareText(title: title, url: shareURL(host: settings.effectiveShareLinkHost),
                                   includeTitle: settings.sharePostIncludesTitle)
    }

    /// The canonical reddit.com permalink, independent of the share host.
    public var redditURL: URL? { URL(string: "https://www.reddit.com\(permalink)") }
}

extension RedditComment {
    /// Reddit's short comment permalink, `/comments/<post>/_/<comment>`.
    public var permalinkPath: String { "/comments/\(linkID.dropFirst(3))/_/\(id)" }

    /// The comment's permalink on the user's chosen share host.
    public func shareURL(host: ShareLinkHost = GeneralSettingsStore.load().effectiveShareLinkHost) -> URL {
        ShareLinkBuilder.url(forPermalinkPath: permalinkPath, host: host)
    }
}
