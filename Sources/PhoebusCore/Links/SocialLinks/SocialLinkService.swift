import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches and parses a user's social links from Reddit's public profile
/// page HTML (Reborn; no public API field exposes these). Only the direct
/// HTML fetch is implemented, not Reborn's WKWebView fallback for JS-only
/// page shapes.
public enum SocialLinkService {
    public enum FetchError: Error, Sendable {
        case userNotFound
        case unrecognizedPage
        case network(Error)
    }

    /// Desktop User-Agent: the mobile UA is redirected to a JS-only page
    /// shape that doesn't server-render the tracker tags this parses.
    private static let desktopUserAgent = BrowserUserAgent.desktopSafari

    public static func fetchSocialLinks(username: String) async throws -> [SocialLink] {
        guard let escaped = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.reddit.com/user/\(escaped)/") else {
            throw FetchError.unrecognizedPage
        }
        var request = URLRequest(url: url)
        request.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 12

        let session = ephemeralSession()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw FetchError.network(URLError(.badServerResponse))
        }

        if SocialLinkScraper.looksLikeUserGone(html: html) {
            throw FetchError.userNotFound
        }
        guard SocialLinkScraper.looksLikeRealProfile(html: html) else {
            throw FetchError.unrecognizedPage
        }
        return SocialLinkScraper.parse(html: html)
    }

    /// Ephemeral, cookie-jar-free session, so the scrape can't poison shared
    /// session state.
    private static func ephemeralSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        return URLSession(configuration: config)
    }
}
