import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Rich Link Previews' fetch: each link goes to the source that knows it
/// best, the same ones Reborn uses, and comes
/// back as one `LinkPreview`:
///
/// - X/Twitter statuses: `TweetClient`, then the chosen fallback provider
/// - YouTube: oEmbed, with the 1280×720 thumbnail when it exists
/// - Wikipedia articles: the REST summary
/// - Reddit: profile and subreddit `about`, a post's own JSON
/// - GitHub repositories, issues and pull requests: the REST API
/// - Bluesky posts: the public AppView
/// - DOI and Nature article links: Crossref
/// - everything else: the page's OpenGraph tags, then Reddit's own
///   preview of the address (`api/info?url=`) when the page is walled
public enum LinkPreviewFetcher {
    /// The signed-in account's repository, for Reddit lookups; set by the
    /// app's account manager. Without one, Reddit's public JSON is used.
    public nonisolated(unsafe) static var redditProvider: () -> RedditRepository? = { nil }

    public static func preview(for url: URL, twitterFallback: TwitterFallbackProvider = .none,
                               session: URLSession = .shared) async -> LinkPreview? {
        await LinkPreviewCache.shared.preview(for: url) {
            let preview = await fetch(url, twitterFallback: twitterFallback, session: session)
            return preview?.hasContent == true ? preview : nil
        }
    }

    static func fetch(_ url: URL, twitterFallback: TwitterFallbackProvider, session: URLSession) async -> LinkPreview? {
        if let statusID = TweetURL.statusID(from: url) {
            guard let tweet = await TweetClient.shared.tweet(id: statusID, fallback: twitterFallback) else { return nil }
            return tweetPreview(tweet)
        }
        if TweetURL.isTwitterHost(url) {
            // Profiles and other X pages answer scrapers with a login wall.
            return nil
        }
        if LinkPreviewHosts.isYouTube(url) {
            return await youTube(url, session: session)
        }
        if WikipediaClient.article(from: url) != nil {
            guard let summary = try? await WikipediaClient.fetchSummary(for: url, session: session) else {
                return await page(url, session: session)
            }
            return LinkPreview(siteName: "Wikipedia", title: summary.title, description: summary.extract,
                               imageURL: summary.thumbnailURL)
        }
        if let target = RedditLinkTarget.parse(url) {
            return await reddit(target, session: session)
        }
        if LinkPreviewHosts.hostIs(url, "github.com"), let preview = await gitHub(url, session: session) {
            return preview
        }
        if let parts = BlueskyPost.parts(from: url) {
            if let preview = await bluesky(parts, session: session) { return preview }
            return await page(url, session: session)
        }
        if let doi = CrossrefWork.doi(from: url) {
            if let preview = await crossref(doi: doi, url: url, session: session) { return preview }
        }
        return await page(url, session: session)
    }

    static func tweetPreview(_ tweet: TweetInfo) -> LinkPreview {
        LinkPreview(kind: .socialPost, siteName: "X", title: tweet.name,
                    description: tweet.text, imageURL: tweet.mediaThumbnailURL,
                    imageWidth: tweet.mediaWidth, imageHeight: tweet.mediaHeight,
                    avatarURL: tweet.profilePictureURL, authorName: tweet.name.isEmpty ? nil : tweet.name,
                    authorHandle: tweet.username.isEmpty ? nil : "@" + tweet.username,
                    postText: tweet.text)
    }

    // MARK: - Sources

    private static func json(_ url: URL, session: URLSession, headers: [String: String] = [:]) async -> Any? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func page(_ url: URL, session: URLSession) async -> LinkPreview? {
        let metadata = try? await OpenGraphClient.fetchMetadata(for: url, session: session)
        if let metadata, metadata.title != nil || metadata.imageURLString != nil {
            return LinkPreview(siteName: metadata.siteName ?? LinkPreviewHosts.displayHost(url),
                               title: metadata.title, description: metadata.description,
                               imageURL: metadata.imageURLString.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL },
                               imageWidth: metadata.imageWidth, imageHeight: metadata.imageHeight)
        }
        // The page is walled or empty: Reddit's scraper saw it at submit time.
        return await redditInfo(url, session: session)
    }

    private static func youTube(_ url: URL, session: URLSession) async -> LinkPreview? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString),
                                 URLQueryItem(name: "format", value: "json")]
        guard let object = await json(components.url!, session: session),
              var preview = parseYouTubeOEmbed(object) else { return nil }
        if let id = YouTubeURLParser.extractVideoID(from: url),
           let wide = URL(string: "https://i.ytimg.com/vi/\(id)/hq720.jpg") {
            var request = URLRequest(url: wide, timeoutInterval: 5)
            request.httpMethod = "HEAD"
            if let (_, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                preview.imageURL = wide
                preview.imageWidth = 1280
                preview.imageHeight = 720
            }
        }
        return preview
    }

    public static func parseYouTubeOEmbed(_ object: Any) -> LinkPreview? {
        guard let json = object as? [String: Any], let title = json["title"] as? String else { return nil }
        return LinkPreview(siteName: "YouTube", title: title, description: json["author_name"] as? String,
                           imageURL: (json["thumbnail_url"] as? String).flatMap(URL.init(string:)),
                           imageWidth: TweetClient.jsonNumber(json["thumbnail_width"]),
                           imageHeight: TweetClient.jsonNumber(json["thumbnail_height"]))
    }

    private static func redditJSON(path: String, parameters: [String: String] = [:], session: URLSession) async -> Any? {
        if let repository = redditProvider(),
           let data = try? await repository.rawGET(path: path, parameters: parameters.merging(["raw_json": "1"]) { a, _ in a }) {
            return try? JSONSerialization.jsonObject(with: data)
        }
        var components = URLComponents(string: "https://www.reddit.com\(path).json")!
        components.queryItems = (parameters.merging(["raw_json": "1"]) { a, _ in a }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        return await json(url, session: session, headers: ["User-Agent": BrowserUserAgent.mobileSafari])
    }

    private static func reddit(_ target: RedditLinkTarget, session: URLSession) async -> LinkPreview? {
        switch target {
        case .user(let name):
            guard let object = await redditJSON(path: "/user/\(name)/about", session: session) else { return nil }
            return parseRedditUser(object)
        case .subreddit(let name):
            guard let object = await redditJSON(path: "/r/\(name)/about", session: session) else { return nil }
            return parseRedditSubreddit(object)
        case .post(let id):
            guard let object = await redditJSON(path: "/comments/\(id)", session: session) else { return nil }
            return parseRedditPost(object)
        case .other:
            return nil
        }
    }

    private static func unescaped(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        return URL(string: string.replacingOccurrences(of: "&amp;", with: "&"))
    }

    private static func truncated(_ string: String?, _ limit: Int) -> String? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return string.count > limit ? String(string.prefix(limit)) + "…" : string
    }

    /// `/user/<name>/about`: the profile's title, about text and avatar.
    public static func parseRedditUser(_ object: Any) -> LinkPreview? {
        guard let data = (object as? [String: Any])?["data"] as? [String: Any],
              let name = data["name"] as? String else { return nil }
        let profile = data["subreddit"] as? [String: Any]
        let title = (profile?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
        let suspended = data["is_suspended"] as? Bool == true
        let about = suspended ? "This account has been suspended." : truncated(profile?["public_description"] as? String, 160)
        let avatar = unescaped(data["snoovatar_img"] as? String) ?? unescaped(data["icon_img"] as? String)
        return LinkPreview(kind: .redditUser, siteName: "Reddit", title: title, description: about,
                           avatarURL: suspended ? nil : avatar, authorName: title, authorHandle: "u/" + name)
    }

    /// `/r/<name>/about`: the community's title, members, description and icon.
    public static func parseRedditSubreddit(_ object: Any) -> LinkPreview? {
        guard let data = (object as? [String: Any])?["data"] as? [String: Any],
              let name = data["display_name"] as? String else { return nil }
        let title = (data["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "r/" + name
        let icon = unescaped(data["community_icon"] as? String) ?? unescaped(data["icon_img"] as? String)
        let members = (data["subscribers"] as? Int).map(LinkPreviewRules.formattedMembers)
        return LinkPreview(kind: .redditSubreddit, siteName: "Reddit", title: title,
                           description: truncated(data["public_description"] as? String, 160),
                           avatarURL: icon, authorName: title, authorHandle: "r/" + name, members: members)
    }

    /// `/comments/<id>`: the post's title, self text and preview image.
    public static func parseRedditPost(_ object: Any) -> LinkPreview? {
        guard let listing = (object as? [Any])?.first as? [String: Any],
              let post = (((listing["data"] as? [String: Any])?["children"] as? [[String: Any]])?.first)?["data"] as? [String: Any],
              let title = post["title"] as? String else { return nil }
        let (image, width, height) = redditPreviewImage(post)
        return LinkPreview(siteName: "Reddit", title: title, description: truncated(post["selftext"] as? String, 200),
                           imageURL: image, imageWidth: width, imageHeight: height)
    }

    static func redditPreviewImage(_ post: [String: Any]) -> (URL?, Double?, Double?) {
        let source = (((post["preview"] as? [String: Any])?["images"] as? [[String: Any]])?.first)?["source"] as? [String: Any]
        if let url = unescaped(source?["url"] as? String) {
            return (url, TweetClient.jsonNumber(source?["width"]), TweetClient.jsonNumber(source?["height"]))
        }
        if let thumbnail = post["thumbnail"] as? String, thumbnail.hasPrefix("http") {
            return (URL(string: thumbnail), nil, nil)
        }
        return (nil, nil, nil)
    }

    /// `api/info?url=`: the first submission of this exact address that has
    /// a preview image, tried with and without "www.".
    private static func redditInfo(_ url: URL, session: URLSession) async -> LinkPreview? {
        guard !LinkPreviewHosts.isReddit(url) else { return nil }
        var candidates = [url]
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: true), let host = components.host {
            components.host = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : "www." + host
            if let sibling = components.url { candidates.append(sibling) }
        }
        for candidate in candidates {
            guard let object = await redditJSON(path: "/api/info", parameters: ["url": candidate.absoluteString], session: session),
                  let preview = parseRedditInfo(object, url: url) else { continue }
            return preview
        }
        return nil
    }

    public static func parseRedditInfo(_ object: Any, url: URL) -> LinkPreview? {
        let children = ((object as? [String: Any])?["data"] as? [String: Any])?["children"] as? [[String: Any]] ?? []
        for child in children {
            guard let post = child["data"] as? [String: Any] else { continue }
            let (image, width, height) = redditPreviewImage(post)
            guard let image else { continue }
            return LinkPreview(siteName: LinkPreviewHosts.displayHost(url), title: post["title"] as? String,
                               imageURL: image, imageWidth: width, imageHeight: height)
        }
        return nil
    }

    private static func gitHub(_ url: URL, session: URLSession) async -> LinkPreview? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let api: String
        if parts.count >= 4, parts[2] == "issues" || parts[2] == "pull" {
            api = "https://api.github.com/repos/\(parts[0])/\(parts[1])/issues/\(parts[3])"
        } else {
            api = "https://api.github.com/repos/\(parts[0])/\(parts[1])"
        }
        guard let apiURL = URL(string: api),
              let object = await json(apiURL, session: session, headers: ["Accept": "application/vnd.github+json"]) else { return nil }
        return parseGitHub(object)
    }

    /// A repository (`full_name`, `description`, owner avatar) or an issue
    /// or pull request (`title`, `body`, author avatar).
    public static func parseGitHub(_ object: Any) -> LinkPreview? {
        guard let json = object as? [String: Any] else { return nil }
        if let fullName = json["full_name"] as? String {
            return LinkPreview(siteName: "GitHub", title: fullName, description: truncated(json["description"] as? String, 200),
                               imageURL: ((json["owner"] as? [String: Any])?["avatar_url"] as? String).flatMap(URL.init(string:)))
        }
        guard let title = json["title"] as? String else { return nil }
        return LinkPreview(siteName: "GitHub", title: title, description: truncated(json["body"] as? String, 200),
                           imageURL: ((json["user"] as? [String: Any])?["avatar_url"] as? String).flatMap(URL.init(string:)))
    }

    private static func bluesky(_ parts: (actor: String, rkey: String), session: URLSession) async -> LinkPreview? {
        var did = parts.actor
        if !did.hasPrefix("did:") {
            var components = URLComponents(string: "https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle")!
            components.queryItems = [URLQueryItem(name: "handle", value: parts.actor)]
            guard let object = await json(components.url!, session: session),
                  let resolved = (object as? [String: Any])?["did"] as? String else { return nil }
            did = resolved
        }
        var components = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread")!
        components.queryItems = [URLQueryItem(name: "uri", value: "at://\(did)/app.bsky.feed.post/\(parts.rkey)"),
                                 URLQueryItem(name: "depth", value: "0"),
                                 URLQueryItem(name: "parentHeight", value: "0")]
        guard let object = await json(components.url!, session: session) else { return nil }
        return BlueskyPost.parseThread(object)
    }

    private static func crossref(doi: String, url: URL, session: URLSession) async -> LinkPreview? {
        let allowed = CharacterSet.urlPathAllowed
        guard let encoded = doi.addingPercentEncoding(withAllowedCharacters: allowed),
              let apiURL = URL(string: "https://api.crossref.org/works/\(encoded)"),
              let object = await json(apiURL, session: session) else { return nil }
        return CrossrefWork.parse(object, url: url)
    }
}

/// Bluesky post links: `bsky.app/profile/<handle or did>/post/<rkey>`.
public enum BlueskyPost {
    public static func parts(from url: URL) -> (actor: String, rkey: String)? {
        guard LinkPreviewHosts.hostIs(url, "bsky.app") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[0].lowercased() == "profile", parts[2].lowercased() == "post" else { return nil }
        return (parts[1], parts[3])
    }

    /// `getPostThread`: thread.post.{author{displayName, handle, avatar},
    /// record.text, embed.images[0] | embed.external.thumb}.
    public static func parseThread(_ object: Any) -> LinkPreview? {
        guard let post = ((object as? [String: Any])?["thread"] as? [String: Any])?["post"] as? [String: Any] else { return nil }
        let author = post["author"] as? [String: Any] ?? [:]
        let text = ((post["record"] as? [String: Any])?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let embed = post["embed"] as? [String: Any] ?? [:]
        // Quote posts with media nest the media one level down.
        let media = embed["media"] as? [String: Any] ?? embed
        let image = (media["images"] as? [[String: Any]])?.first
        let ratio = image?["aspectRatio"] as? [String: Any]
        let external = media["external"] as? [String: Any]
        let imageString = image?["thumb"] as? String ?? image?["fullsize"] as? String ?? external?["thumb"] as? String
        let name = (author["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let handle = (author["handle"] as? String).map { "@" + $0 }
        let body = text?.isEmpty == false ? text : (external?["description"] as? String ?? external?["title"] as? String)
        return LinkPreview(kind: .socialPost, siteName: "Bluesky", title: name ?? handle,
                           description: body, imageURL: imageString.flatMap(URL.init(string:)),
                           imageWidth: TweetClient.jsonNumber(ratio?["width"]),
                           imageHeight: TweetClient.jsonNumber(ratio?["height"]),
                           avatarURL: (author["avatar"] as? String).flatMap(URL.init(string:)),
                           authorName: name, authorHandle: handle, postText: body)
    }
}

/// DOI links, looked up on Crossref.
public enum CrossrefWork {
    /// The DOI in a doi.org address, a Nature article (`10.1038/<id>`), or
    /// a `/doi/<prefix>/<suffix>` path.
    public static func doi(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if LinkPreviewHosts.hostIs(url, "doi.org"), !parts.isEmpty {
            return parts.joined(separator: "/")
        }
        if LinkPreviewHosts.hostIs(url, "nature.com"), parts.count >= 2, parts[0].lowercased() == "articles",
           parts[1].allSatisfy({ $0.isLetter || $0.isNumber || "-_.".contains($0) }) {
            return "10.1038/" + parts[1]
        }
        if let i = parts.firstIndex(where: { $0.lowercased() == "doi" }), parts.count > i + 2, parts[i + 1].hasPrefix("10.") {
            return parts[(i + 1)...].joined(separator: "/")
        }
        return nil
    }

    /// `works/<doi>`: title; the journal (or publisher) as the site; the
    /// abstract, or "journal - publisher - date".
    public static func parse(_ object: Any, url: URL) -> LinkPreview? {
        guard let message = (object as? [String: Any])?["message"] as? [String: Any],
              let title = (message["title"] as? [String])?.first, !title.isEmpty else { return nil }
        let container = (message["container-title"] as? [String])?.first
        let publisher = message["publisher"] as? String
        var summary: String?
        if let abstract = message["abstract"] as? String {
            summary = abstract.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        if summary?.isEmpty != false {
            var parts: [String] = []
            if let container { parts.append(container) }
            if let publisher, publisher != container { parts.append(publisher) }
            let dates = ((message["published-print"] ?? message["published-online"] ?? message["issued"]) as? [String: Any])?["date-parts"] as? [[Any]]
            if let date = dates?.first, !date.isEmpty {
                parts.append(date.compactMap { TweetClient.jsonNumber($0).map { String(Int($0)) } }.joined(separator: "-"))
            }
            summary = parts.isEmpty ? nil : parts.joined(separator: " - ")
        }
        if let text = summary, text.count > 220 { summary = String(text.prefix(220)) + "…" }
        return LinkPreview(siteName: container ?? publisher ?? LinkPreviewHosts.displayHost(url),
                           title: title, description: summary)
    }
}
