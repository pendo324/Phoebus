import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import PhoebusCore

/// One network path for every widget.
///
/// Reborn's widgets each fetch a pool and rotate through it; the mechanism
/// is shared here.
///
/// Every widget is unauthenticated except Home, which is served from the App
/// Group cache the app writes (standing in for Reborn's Setup Code). Feeds
/// that need an account say "Sign in for this feed" rather than failing quietly.
enum WidgetFetcher {
    /// Fetches a pool of posts for a source, already content-filtered.
    static func pool(
        source: WidgetFeedSource,
        sort: WidgetKitShared.Sort,
        limit: Int
    ) async -> Result<[RedditPost], WidgetFetchError> {
        let credentials = await WidgetAuth.current()
        if source.requiresAccount {
            // Home is personal: the app's cached pool first, else fetched
            // here with the account's own credentials.
            if let cached = SharedFeedCache.loadPosts(), !cached.isEmpty {
                return .success(WidgetKitShared.filtered(cached))
            }
            guard credentials != nil else { return .failure(.needsAccount) }
        }

        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let timeframe = sort.timeframe {
            query.append(URLQueryItem(name: "t", value: timeframe))
        }
        guard let request = listingRequest(path: "\(source.path)/\(sort.listingPath)", query: query,
                                           credentials: credentials) else { return .failure(.failed) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // Distinguish "Reddit refused us" from "Reddit had nothing to say"
            // so the widget can say which it is.
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return .failure(http.statusCode == 401 || http.statusCode == 403
                                ? .needsAccount : .failed)
            }
            let listing = try JSONDecoder.reddit.decode(RedditListing.self, from: data)
            let filtered = WidgetKitShared.filtered(listing.posts())
            return filtered.isEmpty ? .failure(.empty) : .success(filtered)
        } catch {
            return .failure(.failed)
        }
    }

    static func isRedditHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "reddit.com" || host.hasSuffix(".reddit.com")
    }

    /// A listing request carrying the signed-in account's identity.
    ///
    /// Anonymous requests get 403 from Reddit, so every request carries the
    /// account's identity when there is one: a bearer goes to `oauth.reddit.com`
    /// (www ignores it), a cookie to `www.reddit.com` with the browser identity.
    ///
    /// Cookies must not ride along automatically: the extension has its own
    /// cookie jar, and letting URLSession attach it alongside an explicit
    /// Cookie header risks sending two conflicting sessions.
    static func listingRequest(path: String, query: [URLQueryItem],
                               credentials: SharedFeedCache.WidgetCredentials?) -> URLRequest? {
        let useBearer = credentials?.hasFreshBearer == true
        var components = URLComponents(string: useBearer
                                       ? "https://oauth.reddit.com\(path)"
                                       : "https://www.reddit.com\(path).json")
        components?.queryItems = query + [URLQueryItem(name: "raw_json", value: "1")]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        if useBearer, let credentials, let token = credentials.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
        } else if let cookie = credentials?.cookieHeader, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            request.setValue(RedditAPIClient.webBrowserUserAgent, forHTTPHeaderField: "User-Agent")
        } else {
            // Signed out: still worth attempting with a browser identity rather than
            // a bot-shaped one.
            request.setValue(RedditAPIClient.webBrowserUserAgent, forHTTPHeaderField: "User-Agent")
        }
        return request
    }

    /// Downloads a post's image so the timeline entry carries the bytes. A widget
    /// view is rendered once into an archived snapshot and cannot run async work,
    /// so `AsyncImage` and friends would show their placeholder forever.
    ///
    /// Downscaled before storing: a timeline entry is archived and passed across
    /// an XPC boundary with a hard memory budget, and a full-resolution Reddit
    /// image risks the extension being killed.
    static func imageData(for post: RedditPost, maxPixel: CGFloat = 1200) async -> Data? {
        guard let raw = post.url, let url = URL(string: raw) else { return nil }
        do {
            // Media hosts (i.redd.it, i.imgur.com) serve images without
            // an account, and credentials must never go to a third party.
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) { return nil }
            return downscaled(data, maxPixel: maxPixel) ?? data
        } catch {
            return nil
        }
    }

    /// Re-encodes to at most `maxPixel` on the long edge. Uses
    /// ImageIO's thumbnail path so the full image is never fully
    /// decoded into memory.
    private static func downscaled(_ data: Data, maxPixel: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
                output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

enum WidgetFetchError: Error {
    /// Home or your own multireddit with nothing cached yet.
    case needsAccount
    case empty
    case failed

    /// The message the widget shows. The account case uses Reborn's
    /// own copy verbatim.
    var message: String {
        switch self {
        case .needsAccount: return WidgetFeedSource.signInMessage
        case .empty: return "No posts"
        case .failed: return "Couldn't load"
        }
    }
}

/// The widget's credentials, renewing an expired bearer itself.
enum WidgetAuth {
    /// The app's shared credentials; an expired bearer is renewed here
    /// and written back for the other widgets.
    static func current() async -> SharedFeedCache.WidgetCredentials? {
        guard var credentials = SharedFeedCache.loadCredentials(), credentials.isUsable else { return nil }
        if !credentials.hasFreshBearer, credentials.canRefreshBearer,
           let renewed = await refreshed(credentials) {
            credentials = renewed
            SharedFeedCache.store(credentials: renewed)
        }
        return credentials
    }

    /// Reddit's refresh-token grant, as the app's `RedditAuthClient` does it.
    private static func refreshed(_ credentials: SharedFeedCache.WidgetCredentials) async -> SharedFeedCache.WidgetCredentials? {
        guard let refreshToken = credentials.refreshToken, let clientID = credentials.clientID,
              let url = URL(string: RedditOAuthConfig.accessTokenURL) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let basic = Data("\(clientID):\(credentials.clientSecret ?? "")".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(FormEncoding.encode(["grant_type": "refresh_token", "refresh_token": refreshToken]).utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue else { return nil }
        var renewed = credentials
        renewed.accessToken = token
        renewed.expiration = Date().addingTimeInterval(expiresIn - 60)
        return renewed
    }
}
