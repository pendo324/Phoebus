import Foundation

/// Normalizes Reddit/Imgur/YouTube link shapes that would otherwise
/// route to the wrong place, as Reborn's link normalizer does:
///
///   - `reddit.com/media?url=<encoded>` -> the decoded inner URL
///   - `imgur.com/hyphenated-title-imageId` -> `imgur.com/imageId`
///   - `youtube.com/shorts/<id>` -> `youtube.com/watch?v=<id>`
///
/// Normalising at the parser keeps these rewrites independent of which
/// call site a URL arrives through. `/s/` share links are handled by
/// `ShareLinkResolver`.
public enum ShareLinkNormalizer {
    /// The URL this one really points at, or nil when no rewrite applies.
    public static func normalized(_ url: URL) -> URL? {
        if let media = redditMediaWrapperTarget(url) { return media }
        if let imgur = imgurTitleIDTarget(url) { return imgur }
        if let shorts = youTubeShortsTarget(url) { return shorts }
        return nil
    }

    /// `reddit.com/media?url=<percent-encoded>`.
    ///
    /// The host is pinned to `reddit.com` with an optional `www.`/`np.` prefix.
    public static func redditMediaWrapperTarget(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == "reddit.com" || host == "www.reddit.com" || host == "np.reddit.com",
              url.path == "/media",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "url" })?.value,
              !encoded.isEmpty else {
            return nil
        }
        // `queryItems` already percent-decodes once.
        return URL(string: encoded)
    }

    /// `imgur.com/some-hyphenated-title-<imageID>` -> `imgur.com/<imageID>`.
    ///
    /// The path is a single component of word characters containing at least
    /// one hyphen, and the image id is the LAST hyphen-separated piece.
    public static func imgurTitleIDTarget(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == "imgur.com" || host == "www.imgur.com" else { return nil }
        let path = url.path
        let slug = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !slug.isEmpty, slug.contains("-") else { return nil }
        // Word characters and hyphens only (`\w+(?:-\w+)+`). This also rejects
        // multi-segment paths, since `/` is not in the set, so
        // `gallery/some-title-ID` never reaches the rewrite.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard slug.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              let imageID = slug.components(separatedBy: "-").last,
              !imageID.isEmpty else {
            return nil
        }
        return URL(string: "https://imgur.com/\(imageID)")
    }

    /// `youtube.com/shorts/<id>` -> a normal watch URL.
    ///
    /// `YouTubeURLParser` already understands the Shorts path, so this exists
    /// for the URL-rewriting path, not to add Shorts support.
    public static func youTubeShortsTarget(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host.contains("youtube.com"),
              url.path.hasPrefix("/shorts/") else { return nil }
        let id = String(url.path.dropFirst("/shorts/".count))
            .components(separatedBy: "/").first ?? ""
        guard !id.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }
}
