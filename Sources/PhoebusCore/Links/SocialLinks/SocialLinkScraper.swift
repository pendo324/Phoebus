import Foundation

/// One social link on a user's profile (Apollo-Reborn's social links).
public struct SocialLink: Equatable, Sendable, Identifiable {
    public let urlString: String
    public let type: String
    public let title: String

    public var id: String { urlString }

    public init(urlString: String, type: String, title: String) {
        self.urlString = urlString
        self.type = type
        self.title = title
    }
}

/// Reimplements Apollo-Reborn's social-link parsing: Reddit's
/// server-rendered profile page wraps each social link in a
/// `<faceplate-tracker source="profile" action="click" noun="social_link"
/// data-faceplate-tracking-context="{...}">` tag, whose JSON context carries a
/// clean `url`/`name` pair. No public Reddit API field exposes these, so the
/// profile page HTML is the only source.
///
/// Only the direct (non-JS-rendered) HTML path is implemented, with no
/// WKWebView fallback; the tracker tags are present in the HTML a plain
/// URLSession GET receives.
public enum SocialLinkScraper {
    /// `noun="social_link"` marks a real link tracker (as opposed to
    /// `noun="add_social_link"`, the owner's own "Add Social Link" button).
    private static let socialLinkNoun = "social_link"

    /// Parses `<faceplate-tracker>` tags out of a profile page's raw HTML and
    /// returns the social links found, in page order, deduplicated by URL,
    /// capped at 12.
    public static func parse(html: String) -> [SocialLink] {
        var results: [SocialLink] = []
        var seen = Set<String>()

        for tag in extractTags(html: html, named: "faceplate-tracker") {
            guard attribute(named: "noun", in: tag) == socialLinkNoun else { continue }
            guard let context = attribute(named: "data-faceplate-tracking-context", in: tag) else { continue }
            guard let decoded = decodeEntities(context).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
                  let socialLink = json["social_link"] as? [String: Any],
                  let urlString = socialLink["url"] as? String, !urlString.isEmpty else { continue }
            guard !seen.contains(urlString) else { continue }
            seen.insert(urlString)

            let host = hostOrMailto(for: urlString)
            let type = typeForHost(host)
            let rawTitle = (socialLink["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if isRedditChromeLink(urlString, title: rawTitle) { continue }
            let title = rawTitle.isEmpty ? displayName(forType: type) : rawTitle

            results.append(SocialLink(urlString: urlString, type: type, title: title))
            if results.count >= 12 { break }
        }
        return results
    }

    /// Reddit's own legal/footer links, never a redditor's social link
    /// (Reborn #1231). reddit.com and redd.it stay allowed: people link
    /// their own subreddit or profile.
    public static func isRedditChromeLink(_ urlString: String, title: String) -> Bool {
        let host = URL(string: urlString)?.host?.lowercased() ?? ""
        for domain in ["redditinc.com", "reddithelp.com", "redditblog.com"]
        where host == domain || host.hasSuffix("." + domain) {
            return true
        }
        return title.range(of: "all rights reserved", options: .caseInsensitive) != nil
    }

    /// Whether the page looks like a real, loaded profile.
    public static func looksLikeRealProfile(html: String) -> Bool {
        html.contains("data-testid=\"profile-main\"")
    }

    /// Whether the page is a nonexistent/deleted-user shell. Reddit returns
    /// HTTP 200 with this chrome rather than a 404.
    public static func looksLikeUserGone(html: String) -> Bool {
        html.range(of: "nobody on Reddit goes by that name", options: .caseInsensitive) != nil
    }

    // MARK: - Tag/attribute extraction (plain string/regex scanning; only
    // self-closing custom-element tags need to be found)

    static func extractTags(html: String, named tagName: String) -> [String] {
        var tags: [String] = []
        let needle = "<\(tagName)"
        var searchStart = html.startIndex
        while let openRange = html.range(of: needle, range: searchStart..<html.endIndex) {
            guard let closeRange = html.range(of: ">", range: openRange.upperBound..<html.endIndex) else { break }
            tags.append(String(html[openRange.lowerBound..<closeRange.upperBound]))
            searchStart = closeRange.upperBound
        }
        return tags
    }

    /// `attr="value"` from inside a single tag string. Space-prefixed needle so
    /// e.g. `noun` never matches inside another attribute's name.
    static func attribute(named name: String, in tag: String) -> String? {
        let needle = " \(name)=\""
        guard let startRange = tag.range(of: needle) else { return nil }
        let from = startRange.upperBound
        guard let endRange = tag.range(of: "\"", range: from..<tag.endIndex) else { return nil }
        return decodeEntities(String(tag[from..<endRange.lowerBound]))
    }

    /// Minimal entity decode for the handful Reddit emits in attribute content.
    /// `&amp;` must decode LAST so `&amp;lt;` doesn't double-decode into `<`.
    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = string
        let first: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&#x27;", "'"), ("&#x2F;", "/"), ("&nbsp;", " "),
            ("&apos;", "'")
        ]
        for (entity, replacement) in first {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        return result
    }

    static func hostOrMailto(for urlString: String) -> String {
        if urlString.hasPrefix("mailto:") { return "mailto:" }
        return URL(string: urlString)?.host?.lowercased() ?? ""
    }

    /// Host to link type map.
    static func typeForHost(_ host: String) -> String {
        let map: [(String, String)] = [
            ("buymeacoffee.com", "buymeacoffee"), ("buymeacoff.ee", "buymeacoffee"),
            ("ko-fi.com", "kofi"), ("patreon.com", "patreon"),
            ("paypal.me", "paypal"), ("paypal.com", "paypal"),
            ("cash.app", "cashapp"), ("venmo.com", "venmo"),
            ("instagram.com", "instagram"), ("twitter.com", "twitter"),
            ("x.com", "twitter"), ("t.co", "twitter"),
            ("tiktok.com", "tiktok"), ("youtube.com", "youtube"), ("youtu.be", "youtube"),
            ("twitch.tv", "twitch"), ("discord.gg", "discord"), ("discord.com", "discord"),
            ("spotify.com", "spotify"), ("soundcloud.com", "soundcloud"),
            ("facebook.com", "facebook"), ("fb.com", "facebook"),
            ("github.com", "github"), ("onlyfans.com", "onlyfans"),
            ("linktr.ee", "linktree"), ("snapchat.com", "snapchat"),
            ("linkedin.com", "linkedin"), ("pinterest.com", "pinterest"),
            ("tumblr.com", "tumblr"), ("threads.net", "threads"),
            ("bsky.app", "bluesky"), ("mastodon", "mastodon"),
            ("steamcommunity.com", "steam"), ("twitch.com", "twitch"),
            ("mailto:", "email")
        ]
        for (needle, type) in map where host.contains(needle) {
            return type
        }
        return "custom"
    }

    /// Link type to display name map.
    static func displayName(forType type: String) -> String {
        let names: [String: String] = [
            "buymeacoffee": "Buy Me a Coffee", "kofi": "Ko-fi", "patreon": "Patreon",
            "paypal": "PayPal", "cashapp": "Cash App", "venmo": "Venmo",
            "instagram": "Instagram", "twitter": "X", "tiktok": "TikTok",
            "youtube": "YouTube", "twitch": "Twitch", "discord": "Discord",
            "spotify": "Spotify", "soundcloud": "SoundCloud", "facebook": "Facebook",
            "github": "GitHub", "onlyfans": "OnlyFans", "linktree": "Linktree",
            "snapchat": "Snapchat", "linkedin": "LinkedIn", "pinterest": "Pinterest",
            "tumblr": "Tumblr", "threads": "Threads", "bluesky": "Bluesky",
            "mastodon": "Mastodon", "steam": "Steam", "email": "Email"
        ]
        return names[type] ?? "Link"
    }

    /// System-symbol icon name per type (schematic SF Symbols, not brand
    /// artwork).
    public static func systemImageName(forType type: String) -> String {
        switch type {
        case "buymeacoffee", "kofi": return "cup.and.saucer.fill"
        case "patreon": return "heart.fill"
        case "paypal", "cashapp", "venmo": return "dollarsign.circle.fill"
        case "instagram": return "camera.fill"
        case "twitter": return "at"
        case "tiktok": return "music.note"
        case "youtube": return "play.rectangle.fill"
        case "twitch": return "gamecontroller.fill"
        case "discord": return "bubble.left.and.bubble.right.fill"
        case "spotify", "soundcloud": return "music.note.list"
        case "facebook": return "person.2.fill"
        case "github": return "chevron.left.forwardslash.chevron.right"
        case "onlyfans": return "lock.fill"
        case "linktree": return "link"
        case "snapchat": return "camera.viewfinder"
        case "linkedin": return "briefcase.fill"
        case "pinterest": return "pin.fill"
        case "tumblr": return "text.bubble.fill"
        case "threads": return "at.circle.fill"
        case "bluesky": return "cloud.fill"
        case "mastodon": return "network"
        case "steam": return "gamecontroller"
        case "email": return "envelope.fill"
        default: return "link.circle.fill"
        }
    }
}
