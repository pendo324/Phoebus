import Foundation

/// Reborn's "Inline Media Previews": finds image/GIF/video/RedGifs/
/// Streamable URLs in a post or comment's markdown body so they render as
/// inline media rather than plain links.
public enum InlineMediaKind: Sendable, Equatable {
    case image(URL)
    case gif(URL)
    case video(URL)
    case redgifs(id: String)
    case streamable(id: String)
    /// gfycat.com legacy links, resolved via RedGifs' API after their
    /// merger. See `GfycatURLParser`.
    case gfycat(id: String)
    /// An `imgur.com/a/<id>` or `/gallery/<id>` album, rendered inline
    /// as Inline Media Previews covers Imgur images and albums.
    case imgurAlbum(id: String)
    /// Apollo-Reborn's "Compact Multi-Link Comments": every markdown
    /// link inside a comment body that isn't image/gif/video renders
    /// as its own compact rich-preview card, stacked below the others.
    case link(URL)
}

public enum InlineMediaDetector {
    /// A conservative Markdown/bare-URL matcher: anything that looks
    /// like `http(s)://...` up to the next whitespace or closing
    /// markdown-link paren/bracket. Good enough for Reddit-authored
    /// bodies, which rarely embed URLs inside other punctuation.
    private static let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s\)\]]+"#)

    /// Scans `body` for every URL and returns the ones that classify
    /// as inline-previewable media, in the order they appear,
    /// preserving duplicates (Apollo-Reborn shows each occurrence).
    public static func detect(in body: String, imageURLs: [String: String] = [:]) -> [InlineMediaKind] {
        let body = RedditMediaTokens.expand(body, imageURLs: imageURLs)
        let regex = urlRegex
        let range = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, range: range)
        return matches.compactMap { match -> InlineMediaKind? in
            guard let matchRange = Range(match.range, in: body) else { return nil }
            let urlString = String(body[matchRange])
            guard let url = URL(string: urlString) else { return nil }
            return classify(url)
        }
    }

    /// Whether tapping this URL should open the in-app image viewer
    /// rather than a web view, e.g. a
    /// `https://preview.redd.it/<id>.png?width=...` link in a post
    /// body.
    ///
    /// Reuses the same host allowlist and extension rules the inline
    /// detector uses, including the `format=mp4` exclusion.
    ///
    /// Returns the HLS playlist for a Reddit-hosted video URL, or nil.
    /// Handles two extension-less shapes: a bare `v.redd.it/<assetID>`,
    /// and a `reddit.com/link/<post>/video/<assetID>/player` page.
    public static func redditVideoPlaylistURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let assetID: String
        if host == "v.redd.it" {
            // Already a playable manifest or file: leave it to the
            // extension checks so the original URL is preserved.
            let path = url.path.lowercased()
            if path.contains(".m3u8") || path.contains(".mpd") || path.contains(".mp4") {
                return nil
            }
            let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
            guard let first = components.first, !first.isEmpty else { return nil }
            assetID = String(first)
        } else if host == "reddit.com" || host.hasSuffix(".reddit.com") {
            // `/link/<post>/video/<asset>/player`.
            let parts = url.path.components(separatedBy: "/")
            guard parts.count >= 6, parts[1] == "link", parts[3] == "video" else { return nil }
            assetID = parts[4]
        } else {
            return nil
        }
        guard !assetID.isEmpty else { return nil }
        return URL(string: "https://v.redd.it/\(assetID)/HLSPlaylist.m3u8")
    }

    public static func isViewableImageURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), isAllowedInlineMediaHost(host) else {
            return false
        }
        if url.query?.lowercased().contains("format=mp4") == true { return false }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "webp", "gif"].contains(ext)
    }

    /// Allowlist for the inline-image host gate.
    static let allowedInlineMediaHosts = [
        "redd.it",
        "imgur.com",
        "giphy.com",
        "tenor.com",
        "redgifs.com",
        "twimg.com",
        "discordapp.com",
        "discordapp.net",
        "imgchest.com",
    ]

    static func isAllowedInlineMediaHost(_ host: String) -> Bool {
        allowedInlineMediaHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Classifies a single URL, reusing the same host/extension rules
    /// as `PostMediaKind.classify` (PhoebusUI) so a link behaves
    /// identically whether it's the post's own URL or one embedded in
    /// its body text.
    public static func classify(_ url: URL) -> InlineMediaKind? {
        if url.host?.contains("redgifs.com") == true, let id = RedGifsClient.extractID(from: url) {
            return .redgifs(id: id)
        }
        if url.host?.contains("gfycat.com") == true, let id = GfycatURLParser.extractID(from: url) {
            return .gfycat(id: id)
        }
        if url.host?.contains("streamable.com") == true, let id = StreamableClient.extractID(from: url) {
            return .streamable(id: id)
        }
        // Reddit-hosted video, which the extension checks below cannot
        // reach: the shareable forms carry no file extension.
        //
        // Reddit's public CDN serves the asset id from a
        // `/link/<post>/video/<asset>/player` path as HLS at
        // `https://v.redd.it/<id>/HLSPlaylist.m3u8`, since the player
        // page itself cannot be turned into a playable asset.
        if let playlist = redditVideoPlaylistURL(for: url) {
            return .video(playlist)
        }

        // Checked with the other host-specific parsers, keeping the
        // album case independent of the general host allowlist below.
        if let id = ImgurClient.extractAlbumID(from: url) {
            return .imgurAlbum(id: id)
        }

        // Reddit's pseudo-MP4 GIFs: the path ends .gif but the query
        // says format=mp4, so the bytes are MP4, not a GIF. The image
        // pipeline can't decode them as image or animated image,
        // leaving an empty grey container.
        if url.query?.lowercased().contains("format=mp4") == true {
            return nil
        }

        // Host allowlist, curated to cover common image hosts in
        // Reddit comments while keeping random tracker pixels and
        // arbitrary image-extensioned URLs out (privacy + bandwidth).
        //
        // A host matches if it equals a parent domain or is a subdomain
        // of one.
        guard let host = url.host?.lowercased(), isAllowedInlineMediaHost(host) else {
            return nil
        }

        // By the path's extension, not the whole string: Reddit's
        // `preview.redd.it/<id>.jpeg?width=…&format=pjpg…` links carry a
        // query after the extension.
        let ext = "." + url.pathExtension.lowercased()
        if ext == ".gif" || ext == ".gifv" {
            return .gif(url)
        }
        if [".mp4", ".mov", ".m3u8", ".webm"].contains(ext) {
            return .video(url)
        }
        if [".jpg", ".jpeg", ".png", ".webp"].contains(ext) {
            return .image(url)
        }
        // A bare link is not inline media here. Reborn's own gate
        // requires both an image extension and an allowlisted host,
        // and its multi-link collapse only applies in comments, once
        // a comment holds 2+ eligible links. Returning nil keeps an
        // ordinary link as ordinary text.
        return nil
    }
}

/// Reddit's native comment media tokens. The official apps write a GIF
/// as `![gif](giphy|<id>)` and an uploaded image as `![img](<media id>)`,
/// which are not URLs. Reborn rewrites a Giphy token to the Giphy CDN
/// file whatever `media_metadata` says (Reddit marks most of them
/// `invalid`), so the GIF plays instead of showing the token.
public enum RedditMediaTokens {
    private static let giphyPattern = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\(giphy\|([A-Za-z0-9_-]{1,128})(?:\|[^)]*)?\)"#)
    private static let imgPattern = try! NSRegularExpression(
        pattern: #"!\[(?:img|gif)\]\(([A-Za-z0-9]{8,20})\)"#)
    /// The placeholder the web editor leaves in a post's or comment's
    /// markdown for an uploaded image, `*Processing img <media id>...*`:
    /// Reddit keeps it in `selftext` after the image is ready, and the
    /// image is that media id's `media_metadata` entry.
    private static let processingPattern = try! NSRegularExpression(
        pattern: #"[*_]{1,2}Processing img ([A-Za-z0-9]{8,20})(?:\.{3}|\x{2026})[*_]{1,2}"#)

    public static func giphyURL(id: String) -> String {
        "https://media.giphy.com/media/\(id)/giphy.gif"
    }

    /// Rewrites every token to a plain URL on its own. `![img](<id>)` needs
    /// the file's extension, which only `media_metadata` knows; an
    /// uploaded comment image is an `i.redd.it` jpeg by default.
    public static func expand(_ body: String, imageURLs: [String: String] = [:]) -> String {
        guard body.contains("](") || body.contains("Processing img") else { return body }
        var text = body
        for (pattern, isGiphy) in [(giphyPattern, true), (imgPattern, false), (processingPattern, false)] {
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range).reversed() {
                guard let whole = Range(match.range, in: text),
                      let idRange = Range(match.range(at: 1), in: text) else { continue }
                let id = String(text[idRange])
                let url = isGiphy ? giphyURL(id: id) : (imageURLs[id] ?? "https://i.redd.it/\(id).jpeg")
                text.replaceSubrange(whole, with: url)
            }
        }
        return text
    }

    private static let uploadPattern = try! NSRegularExpression(
        pattern: #"https?://(?:preview|i)\.redd\.it/([A-Za-z0-9]{8,20})\.(jpe?g|png|gif|webp)\b"#, options: [.caseInsensitive])

    /// The uploaded images a post's markdown links, `i.redd.it/<id>.<ext>`
    /// by media id. A post opened from a listing can still carry the
    /// `*Processing img <id>...*` placeholders and no `media_metadata`,
    /// while its comments response holds the same images as
    /// `preview.redd.it/<id>.<ext>` links: the only place the real
    /// extension is written (i.redd.it 404s for any other).
    public static func uploadedImageURLs(inBody body: String) -> [String: String] {
        guard body.contains("redd.it/") else { return [:] }
        var urls: [String: String] = [:]
        let range = NSRange(body.startIndex..., in: body)
        for match in uploadPattern.matches(in: body, range: range) {
            guard let id = Range(match.range(at: 1), in: body), let ext = Range(match.range(at: 2), in: body) else { continue }
            urls[String(body[id])] = "https://i.redd.it/\(body[id]).\(body[ext].lowercased())"
        }
        return urls
    }

    /// The file each `![img](<id>)` token names, from the comment's
    /// `media_metadata`: `i.redd.it/<id>.<ext>` with the extension the
    /// entry's own `s.u` link has, else its MIME type (the jpeg guess 404s
    /// for a png upload), or the GIF's own URL. Items Reddit hasn't
    /// finished processing are left out, and `uploaded` (see
    /// `uploadedImageURLs`) names the files metadata doesn't.
    public static func imageURLs(from metadata: [String: GalleryMediaItem]?,
                                 uploaded: [String: String] = [:]) -> [String: String] {
        var urls = uploaded
        guard let metadata else { return urls }
        for (id, item) in metadata where item.status == nil || item.status == "valid" {
            if item.kind == "AnimatedImage", let gif = item.source?.gifURL {
                let gifURL = gif.replacingOccurrences(of: "&amp;", with: "&")
                urls[id] = gifURL
                if let mp4 = item.source?.mp4URL {
                    GIFTranscodes.record(mp4: mp4.replacingOccurrences(of: "&amp;", with: "&"), forGIF: gifURL)
                }
                continue
            }
            let ext: String
            if let named = linkedExtension(item.source?.url) {
                ext = named
            } else {
                switch item.mimeType?.lowercased() {
                case "image/png": ext = "png"
                case "image/gif": ext = "gif"
                case "image/webp": ext = "webp"
                case "image/jpg": ext = "jpg"
                default: ext = "jpeg"
                }
            }
            urls[id] = "https://i.redd.it/\(id).\(ext)"
        }
        return urls
    }

    /// The image extension of an `s.u` link on Reddit's image hosts.
    private static func linkedExtension(_ link: String?) -> String? {
        guard let link, let url = URL(string: link.replacingOccurrences(of: "&amp;", with: "&")),
              let host = url.host?.lowercased(), host == "preview.redd.it" || host == "i.redd.it" else { return nil }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) ? ext : nil
    }

    /// Width over height for each of those URLs, from the metadata's pixel size,
    /// so the box is final before the image loads (Reborn #1273).
    public static func ratios(from metadata: [String: GalleryMediaItem]?) -> [String: Double] {
        guard let metadata else { return [:] }
        let urls = imageURLs(from: metadata)
        var ratios: [String: Double] = [:]
        for (id, url) in urls {
            guard let x = metadata[id]?.source?.x, let y = metadata[id]?.source?.y, x > 0, y > 0 else { continue }
            ratios[url] = Double(x) / Double(y)
        }
        return ratios
    }

    /// Text for display: a token contributes nothing to the prose, since
    /// its media is drawn below the text.
    public static func removingTokens(_ body: String) -> String {
        guard body.contains("](") || body.contains("Processing img") else { return body }
        var text = body
        for pattern in [giphyPattern, imgPattern, processingPattern] {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reddit's own mp4 transcode of a comment GIF, from its `media_metadata`
/// (`s.mp4`, a signed preview.redd.it URL): `i.redd.it` serves no `.mp4`
/// beside the GIF, and the GIF itself can run to megabytes.
public enum GIFTranscodes {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var mp4ByGIF: [String: String] = [:]

    public static func record(mp4: String, forGIF gif: String) {
        lock.lock(); defer { lock.unlock() }
        mp4ByGIF[gif] = mp4
    }

    public static func mp4(forGIF gif: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return mp4ByGIF[gif]
    }
}
