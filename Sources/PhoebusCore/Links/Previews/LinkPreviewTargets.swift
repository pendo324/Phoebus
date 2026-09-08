import Foundation

/// What a Reddit link points at, for its card.
public enum RedditLinkTarget: Equatable, Sendable {
    case user(String)
    case subreddit(String)
    case post(id: String)
    /// Any other Reddit page (multireddits, wikis, search, messages):
    /// Reddit's own pages give no usable metadata.
    case other

    public static func parse(_ url: URL) -> RedditLinkTarget? {
        guard LinkPreviewHosts.isReddit(url) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let host = LinkPreviewHosts.host(url)
        if host == "redd.it" || host.hasSuffix(".redd.it") {
            if host == "redd.it", parts.count == 1 { return .post(id: parts[0]) }
            return nil
        }
        if let i = parts.firstIndex(of: "comments"), i + 1 < parts.count {
            return .post(id: parts[i + 1])
        }
        guard let first = parts.first?.lowercased() else { return .other }
        if (first == "u" || first == "user"), parts.count == 2 || (parts.count == 3 && parts[2].lowercased() == "overview") {
            return .user(parts[1])
        }
        if first == "r", parts.count >= 2, !parts[1].contains("+"),
           parts.count == 2 || (parts.count == 3 && ["hot", "new", "top", "rising", "controversial"].contains(parts[2].lowercased())) {
            return .subreddit(parts[1])
        }
        return .other
    }
}

/// Apollo's link-button icon for a link, by what it points at.
public enum LinkButtonIcon: String, Sendable {
    case safari = "link-button-safari"
    case twitter = "link-button-twitter"
    case wikipedia = "link-button-wikipedia"
    case xkcd = "link-button-xkcd"
    case reddit = "link-button-reddit"
    case subreddit = "link-button-subreddit"
    case profile = "link-button-profile"
    case multireddit = "link-button-multireddit"
    case subredditWiki = "link-button-subreddit-wiki"
    case search = "link-button-search"
    case message = "link-button-message"

    public static func forURL(_ url: URL) -> LinkButtonIcon {
        if TweetURL.isTwitterHost(url) { return .twitter }
        if WikipediaClient.article(from: url) != nil { return .wikipedia }
        if LinkPreviewHosts.hostIs(url, "xkcd.com") { return .xkcd }
        guard LinkPreviewHosts.isReddit(url) else { return .safari }
        let parts = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        if parts.first == "message" { return .message }
        if parts.contains("comments") { return .reddit }
        if parts.first == "r", parts.count >= 2 {
            if parts[1].contains("+") { return .multireddit }
            if parts.count >= 3, parts[2] == "wiki" { return .subredditWiki }
            if parts.count >= 3, parts[2] == "search" { return .search }
            return .subreddit
        }
        if parts.first == "u" || parts.first == "user" {
            if parts.count >= 3, parts[2] == "m" { return .multireddit }
            return .profile
        }
        if parts.first == "search" { return .search }
        return .reddit
    }
}

/// The links in a comment or self post that get a card underneath it:
/// markdown links, bare web addresses, and Reddit's r/ and u/ mentions,
/// each once, leaving out anything drawn as inline media.
public enum LinkCardDetector {
    private static let markdownLink = try! NSRegularExpression(pattern: #"\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)"#)
    private static let bareURL = try! NSRegularExpression(pattern: #"https?://[^\s\)\]<>"]+"#)
    private static let mention = try! NSRegularExpression(pattern: #"(?<![\w/\]\.])/?([ru])/([A-Za-z0-9_][A-Za-z0-9_-]{1,30})\b"#)

    public static func links(in body: String) -> [URL] {
        var seen = Set<String>()
        return urls(in: body).filter { url in
            guard InlineMediaDetector.classify(url) == nil else { return false }
            return seen.insert(url.absoluteString.lowercased()).inserted
        }
    }

    /// Every link in the body in reading order, media included, with
    /// repeats: the order the body's media and cards are drawn in.
    public static func urls(in body: String) -> [URL] {
        let ns = body as NSString
        var found: [(Int, URL)] = []
        var covered: [NSRange] = []
        for match in markdownLink.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            covered.append(match.range)
            if let url = resolve(ns.substring(with: match.range(at: 1))) {
                found.append((match.range.location, url))
            }
        }
        func isCovered(_ range: NSRange) -> Bool {
            covered.contains { NSIntersectionRange($0, range).length > 0 }
        }
        for match in bareURL.matches(in: body, range: NSRange(location: 0, length: ns.length)) where !isCovered(match.range) {
            var raw = ns.substring(with: match.range)
            while let last = raw.last, ".,;:!?'".contains(last) { raw.removeLast() }
            if let url = URL(string: raw) { found.append((match.range.location, url)) }
            covered.append(match.range)
        }
        for match in mention.matches(in: body, range: NSRange(location: 0, length: ns.length)) where !isCovered(match.range) {
            let prefix = ns.substring(with: match.range(at: 1)) == "r" ? "r" : "user"
            let name = ns.substring(with: match.range(at: 2))
            if let url = URL(string: "https://www.reddit.com/\(prefix)/\(name)") {
                found.append((match.range.location, url))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// A markdown target as an absolute URL: web addresses as they are,
    /// Reddit-relative paths on reddit.com.
    static func resolve(_ target: String) -> URL? {
        let lower = target.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: target) }
        if target.hasPrefix("/r/") || target.hasPrefix("/u/") || target.hasPrefix("/user/") {
            return URL(string: "https://www.reddit.com" + target)
        }
        if lower.hasPrefix("r/") || lower.hasPrefix("u/") {
            return URL(string: "https://www.reddit.com/" + target)
        }
        return nil
    }
}
