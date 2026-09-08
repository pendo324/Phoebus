import Foundation

/// Everything a link card shows, whatever site it came from. One fetch
/// (`LinkPreviewFetcher`) fills it; one card (`LinkPreviewCard`) draws it,
/// picking the layout from `kind` and the Rich Link Previews mode.
public struct LinkPreview: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// Site name, title, description and an image.
        case standard
        /// A Reddit profile: avatar, display name, u/handle, about text.
        case redditUser
        /// A subreddit: icon, title, "r/name · N members", description.
        case redditSubreddit
        /// A Bluesky or X post: author, handle, post text, first image.
        case socialPost
    }

    public var kind: Kind
    public var siteName: String?
    public var title: String?
    public var description: String?
    public var imageURL: URL?
    /// The image's pixel size when the source reports it; the full card
    /// sizes its image box from it.
    public var imageWidth: Double?
    public var imageHeight: Double?
    public var avatarURL: URL?
    public var authorName: String?
    /// "@handle", "u/name" or "r/name", as shown.
    public var authorHandle: String?
    public var postText: String?
    /// A subreddit's formatted member count.
    public var members: String?

    public init(kind: Kind = .standard, siteName: String? = nil, title: String? = nil,
                description: String? = nil, imageURL: URL? = nil,
                imageWidth: Double? = nil, imageHeight: Double? = nil,
                avatarURL: URL? = nil, authorName: String? = nil, authorHandle: String? = nil,
                postText: String? = nil, members: String? = nil) {
        self.kind = kind
        self.siteName = siteName
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.avatarURL = avatarURL
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.postText = postText
        self.members = members
    }

    /// Height over width of the image, when known.
    public var imageAspect: Double? {
        guard let imageWidth, let imageHeight, imageWidth > 1, imageHeight > 1 else { return nil }
        return imageHeight / imageWidth
    }

    /// Whether there is anything to draw a card from.
    public var hasContent: Bool {
        switch kind {
        case .standard: return title?.isEmpty == false || imageURL != nil
        case .redditUser, .redditSubreddit: return title?.isEmpty == false || authorHandle?.isEmpty == false
        case .socialPost: return postText?.isEmpty == false || authorName?.isEmpty == false || authorHandle?.isEmpty == false
        }
    }
}

/// Rich Link Previews' per-site data sources and the card layout rules
/// that depend only on the data, kept here so the smoke run can check them.
public enum LinkPreviewRules {
    /// Lines of description under a compact card's title: fewer as the
    /// title grows, so the card keeps its height.
    public static func compactDescriptionLines(titleLength: Int) -> Int {
        if titleLength >= 110 { return 0 }
        if titleLength >= 70 { return 1 }
        return 2
    }

    /// The full card's one description line goes for very long titles.
    public static func fullDescriptionLines(titleLength: Int) -> Int {
        titleLength >= 120 ? 0 : 1
    }

    /// Height over width of the full card's image box: YouTube is always
    /// 16:9; poster sites (film/anime databases) show tall art uncropped
    /// up to 1.1; everything else is clamped to 0.45–0.6, 16:9 if unknown.
    public static func fullImageAspect(for url: URL, preview: LinkPreview) -> (ratio: Double, fits: Bool) {
        let fallback = 9.0 / 16.0
        if LinkPreviewHosts.isYouTube(url) { return (fallback, false) }
        guard let natural = preview.imageAspect else { return (fallback, false) }
        if LinkPreviewHosts.isPosterSite(url), natural >= 1.15 {
            return (max(min(natural, 1.1), 0.6), true)
        }
        return (max(min(natural, 0.6), 0.45), false)
    }

    /// A post card's image box: the image's own shape within 0.45–0.75.
    public static func postImageAspect(_ preview: LinkPreview) -> Double {
        guard let natural = preview.imageAspect else { return 9.0 / 16.0 }
        return max(min(natural, 0.75), 0.45)
    }

    /// "736k members", "1.2M members", as Reborn formats a subscriber count.
    public static func formattedMembers(_ count: Int) -> String {
        if count <= 0 { return "0 members" }
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000
            return millions >= 10 ? String(format: "%.0fM members", millions) : String(format: "%.1fM members", millions)
        }
        if count >= 1000 {
            let thousands = Double(count) / 1000
            return thousands >= 100 ? String(format: "%.0fk members", thousands) : String(format: "%.1fk members", thousands)
        }
        return "\(count) members"
    }

    /// A card's numeric-only page title ("285023 289273 400021448", from
    /// script-built pages) replaced by the site's name.
    public static func displayTitle(_ title: String?, url: URL) -> String? {
        guard let title, !title.isEmpty else { return nil }
        guard !title.contains(where: \.isLetter), title.contains(where: \.isNumber),
              let host = url.host else { return title }
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard let name = stripped.split(separator: ".").first, !name.isEmpty else { return title }
        return name.uppercased()
    }
}

/// Host checks shared by the fetcher and the card.
public enum LinkPreviewHosts {
    static func host(_ url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        return host
    }

    static func hostIs(_ url: URL, _ domain: String) -> Bool {
        let host = host(url)
        return host == domain || host.hasSuffix("." + domain)
    }

    public static func isYouTube(_ url: URL) -> Bool {
        hostIs(url, "youtube.com") || hostIs(url, "youtu.be")
    }

    public static func isReddit(_ url: URL) -> Bool {
        hostIs(url, "reddit.com") || hostIs(url, "redd.it")
    }

    static let posterHosts = [
        "anidb.net", "anilist.co", "anime-planet.com", "boxofficemojo.com", "fandango.com",
        "imdb.com", "justwatch.com", "kitsu.app", "letterboxd.com", "livechart.me",
        "metacritic.com", "movieinsider.com", "myanimelist.net", "rottentomatoes.com",
        "shikimori.one", "the-numbers.com", "themoviedb.org", "trakt.tv",
    ]

    public static func isPosterSite(_ url: URL) -> Bool {
        posterHosts.contains { hostIs(url, $0) }
    }

    /// The host as a card's address shows it: no "www.".
    public static func displayHost(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
