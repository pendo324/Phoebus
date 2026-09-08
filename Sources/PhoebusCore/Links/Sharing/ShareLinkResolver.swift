import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Resolves Reddit's opaque `/s/` share links.
///
/// Reddit's share button produces links like
/// `https://www.reddit.com/r/swift/s/aBcD3fG`, which carry no post id; the
/// target is only discoverable by following the redirect. Media shares use
/// a second shape, `reddit.com/media?url=<encoded>`.
///
/// Without resolution, `RedditURLTarget.parse` would fall through to its
/// `/r/<sub>` branch and open the subreddit instead of the post.
///
/// Ported from Apollo-Reborn, including its regexes and network constants.
public enum ShareLinkResolver {
    /// Reborn's share-link pattern, verbatim. Matches every presentation host
    /// (www/old/new/np/m/language subdomains) and both `r/` and `u`/`user/`
    /// share links.
    public static let shareLinkPattern =
        #"^(?:https?:)?//(?:[A-Za-z0-9-]+\.)?reddit\.com/(?:r|u|user)/[^/?#]+/s/[A-Za-z0-9_-]+/?(?:[?#].*)?$"#

    /// Reborn's media-share pattern, verbatim: a media share wraps the real
    /// asset URL in a query parameter.
    public static let mediaShareLinkPattern =
        #"^(?:https?:)?//(?:www\.|np\.)?reddit\.com/media\?url=(.*?)$"#

    /// Maximum redirects followed.
    public static let maximumRedirects = 10

    /// Request timeout.
    public static let timeout: TimeInterval = 10

    /// Whether `url` is an opaque share link needing resolution.
    public static func isShareLink(_ url: URL) -> Bool {
        shareLinkRegex.firstMatch(in: url.absoluteString, range: NSRange(url.absoluteString.startIndex..., in: url.absoluteString)) != nil
    }

    /// The media URL wrapped in a `reddit.com/media?url=` link,
    /// or nil if this is not one.
    public static func mediaShareTarget(_ url: URL) -> URL? {
        let s = url.absoluteString
        guard let match = mediaShareLinkRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: s) else { return nil }
        let encoded = String(s[range])
        let decoded = encoded.removingPercentEncoding ?? encoded
        return URL(string: decoded)
    }

    /// Follows a share link to the post it points at.
    ///
    /// A plain GET with a 10s timeout, letting `URLSession` follow up to
    /// `maximumRedirects` hops, then reading the FINAL url. Results are cached
    /// by share link.
    ///
    /// Returns nil rather than throwing on any failure, so a share link that
    /// cannot be resolved still opens in the browser rather than producing an
    /// error the user cannot act on.
    public static func resolve(_ url: URL, session: URLSession = .shared) async -> URL? {
        guard isShareLink(url) else { return nil }
        if let cached = cache[url.absoluteString] { return cached }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeout)
        request.httpMethod = "GET"
        #if canImport(FoundationNetworking)
        let result = try? await session.data(for: request)
        #else
        let result = try? await session.data(for: request, delegate: RedirectLimit(maximum: maximumRedirects))
        #endif
        guard let (_, response) = result, let final = response.url, final != url else { return nil }
        cache[url.absoluteString] = final
        return final
    }

    #if !canImport(FoundationNetworking)
    /// Stops following after `maximum` hops; `URLSession` alone allows many
    /// more.
    private final class RedirectLimit: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let maximum: Int
        private var hops = 0
        init(maximum: Int) { self.maximum = maximum }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            hops += 1
            return hops <= maximum ? request : nil
        }
    }
    #endif

    /// Resolved share links, so tapping the same link twice does not
    /// re-hit the network.
    private static let cache = LockedCache<String, URL>()

    private static let shareLinkRegex = try! NSRegularExpression(pattern: shareLinkPattern, options: [.caseInsensitive])
    private static let mediaShareLinkRegex = try! NSRegularExpression(pattern: mediaShareLinkPattern, options: [.caseInsensitive])
}
