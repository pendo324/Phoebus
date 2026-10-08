import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// RedGifs API v2 client. RedGifs uses a keyless temporary-token flow (no
/// client registration, unlike Reddit's OAuth).
public actor RedGifsClient {
    private var cachedToken: String?
    private var tokenExpiration: Date?
    /// The one in-flight token request. The actor is reentrant, so without
    /// this every post that asked while a mint was pending minted its own
    /// (Reborn #1240 serialises the same queue).
    private var pendingToken: Task<String, Error>?
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private func validToken() async throws -> String {
        if let cachedToken, let tokenExpiration, Date() < tokenExpiration {
            return cachedToken
        }
        if let pendingToken { return try await pendingToken.value }
        let task = Task { try await self.mintToken() }
        pendingToken = task
        defer { pendingToken = nil }
        return try await task.value
    }

    private func mintToken() async throws -> String {
        // GET /v2/auth/temporary returns a JWT bound to the requesting IP and
        // User-Agent, so the same User-Agent must be sent on the follow-up
        // /v2/gifs/<id> request or the token is rejected.
        var request = URLRequest(url: URL(string: "https://api.redgifs.com/v2/auth/temporary")!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, status) = try await send(request)
        if let failure = RedGifsError.failure(status: status, data: data) { throw failure }
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = response.token
        // The JWT's exp is typically ~24h out; refresh hourly to stay well
        // inside it without parsing the JWT.
        tokenExpiration = Date().addingTimeInterval(3600)
        return response.token
    }

    /// Must match across the token request and all authenticated
    /// requests, since RedGifs binds temp tokens to the request's
    /// User-Agent header.
    private static let userAgent = "Phoebus/1.0"

    /// Resolves a redgifs.com/watch/<id> or i.redgifs.com URL to its
    /// playable video URL (HD if available, else SD).
    ///
    /// A token only works from the IP that minted it (Wi-Fi/cellular switch,
    /// VPN, IPv6 rotation), so a 401 mints a fresh token and retries once
    /// (Reborn #1256).
    ///
    /// Failures are thrown as `RedGifsError` where the cause is known
    /// (Reborn #1359).
    public func resolvePlayableURL(forID rawID: String) async throws -> URL {
        // The v2 API only knows lowercase ids; a CamelCase id in a watch link 404s.
        let id = rawID.lowercased()
        var (data, status) = try await fetchGif(id: id, token: try await validToken())
        if Self.isRejectedToken(status: status) {
            cachedToken = nil
            tokenExpiration = nil
            (data, status) = try await fetchGif(id: id, token: try await validToken())
        }
        if let failure = RedGifsError.failure(status: status, data: data) { throw failure }
        let response = try JSONDecoder().decode(GifResponse.self, from: data)
        let candidates = [response.gif.urls.hd, response.gif.urls.sd]
            .compactMap { $0.flatMap(URL.init(string:)) }
            .filter { $0.pathExtension.lowercased() == "mp4" }
        guard let first = candidates.first else { throw RedGifsError.noPlayableURL }
        // The HD rendition is sometimes gone while the mobile one still loads,
        // so HD is checked before it is used.
        for url in candidates where await isAvailable(url) { return url }
        return first
    }

    private func isAvailable(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 6
        guard let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return false }
        return (200..<400).contains(status)
    }

    private func fetchGif(id: String, token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: "https://api.redgifs.com/v2/gifs/\(id)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return try await send(request)
    }

    /// Performs `request`, naming a network failure as `RedGifsError.unreachable`.
    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw RedGifsError.failure(transport: error) ?? error
        }
    }

    /// Whether RedGIFs refused the token itself (upstream retries on 401 only).
    public static func isRejectedToken(status: Int) -> Bool { status == 401 }

    /// Extracts a RedGifs GIF ID from a redgifs.com URL: handles the CDN
    /// subdomains (`giant`/`fat`/`thumbs`/`zippy`, optionally digit-suffixed),
    /// the `ifr`, `gifs/detail` and `watch` prefixes, an optional two-letter
    /// locale segment, and a trailing SEO slug.
    private static let realApolloRedGifsPattern =
        #"^http(?:s)?://(?:www\.)?(?:(?:giant|fat|thumbs|zippy)\d*\.)?redgifs\.com/(?:(?:\w{2}|ifr|gifs/detail|watch)/)?(\w+)[\w-]*"#
    private static let redGifsRegex = try! NSRegularExpression(pattern: realApolloRedGifsPattern, options: [.caseInsensitive])

    public static func extractID(from url: URL) -> String? {
        guard url.host?.contains("redgifs.com") == true else { return nil }
        let s = url.absoluteString
        if let match = redGifsRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: s) {
            return String(s[range])
        }
        // Fallback for anything the capture group misses.
        let components = url.pathComponents.filter { $0 != "/" }
        guard let last = components.last else { return nil }
        return (last as NSString).deletingPathExtension.isEmpty ? last : (last as NSString).deletingPathExtension
    }
}

/// Why a RedGIFs post failed to load. Reborn "RedGIFs failure reasons" (#1359):
/// the messages are what Reborn titles its failure card with.
public enum RedGifsError: Error, Equatable {
    case noPlayableURL
    case deleted
    case notFound
    case regionBlocked
    case unreachable
    /// An image post: the player only shows videos.
    case image
    case httpStatus(Int)

    /// Names the failure of an API answer, or nil for a usable one. RedGIFs'
    /// own error code in the body wins over the status if they ever disagree.
    public static func failure(status: Int, data: Data) -> RedGifsError? {
        if status >= 400 {
            switch apiErrorCode(in: data) {
            case "GifDeleted": return .deleted
            case "GifNotFound": return .notFound
            default: break
            }
            switch status {
            case 404: return .notFound
            case 410: return .deleted
            case 451: return .regionBlocked
            default: return .httpStatus(status)
            }
        }
        if (200..<300).contains(status), isImageRecord(data) { return .image }
        return nil
    }

    /// Names a transport failure (no route, DNS, dropped connection, TLS,
    /// offline). Cancellation isn't one: it says nothing about RedGIFs.
    public static func failure(transport error: Error) -> RedGifsError? {
        guard let code = (error as? URLError)?.code else { return nil }
        switch code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff,
             .callIsActive, .dataNotAllowed, .secureConnectionFailed,
             .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired, .cannotLoadFromNetwork:
            return .unreachable
        default:
            return nil
        }
    }

    /// RedGIFs' error body: {"error":{"code":"GifDeleted","description":"..."}}.
    private static func apiErrorCode(in data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data)
        return ((json as? [String: Any])?["error"] as? [String: Any])?["code"] as? String
    }

    /// A lookup answer for an image (type 2); it has no mp4 renditions.
    private static func isImageRecord(_ data: Data) -> Bool {
        let json = try? JSONSerialization.jsonObject(with: data)
        let gif = (json as? [String: Any])?["gif"] as? [String: Any]
        return (gif?["type"] as? NSNumber)?.intValue == 2
    }
}

extension RedGifsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noPlayableURL: return nil
        case .deleted: return "Removed from RedGIFs"
        case .notFound: return "Not found on RedGIFs"
        case .regionBlocked: return "RedGIFs isn't available in your region"
        case .unreachable: return "Can't reach RedGIFs"
        case .image: return "Can't show RedGIFs images"
        case .httpStatus(let status): return "RedGIFs error (HTTP \(status))"
        }
    }
}

/// Gfycat ID extraction, so gfycat.com links are recognized as
/// inline-previewable media.
///
/// Gfycat shut down in 2023; RedGifs' API resolves legacy Gfycat IDs (same
/// ID namespace), so this reuses `RedGifsClient.resolvePlayableURL`.
public enum GfycatURLParser {
    private static let realApolloGfycatPattern =
        #"^http(?:s)?://(?:www\.)?(?:(?:giant|fat|zippy)\.)?gfycat\.com/(?:(?:\w{2}|ifr|gifs/detail|watch)/)?(\w+)[\w-]*"#
    private static let gfycatRegex = try! NSRegularExpression(pattern: realApolloGfycatPattern, options: [.caseInsensitive])

    public static func extractID(from url: URL) -> String? {
        guard url.host?.contains("gfycat.com") == true else { return nil }
        let s = url.absoluteString
        guard let match = gfycatRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: s) else { return nil }
        return String(s[range])
    }
}

private struct TokenResponse: Decodable {
    let token: String
}

private struct GifResponse: Decodable {
    let gif: GifData

    struct GifData: Decodable {
        let urls: URLs
    }

    struct URLs: Decodable {
        let sd: String?
        let hd: String?
    }
}
