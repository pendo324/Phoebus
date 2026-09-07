import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Resolves a streamable.com/<id> URL to its playable .mp4 URL via
/// Streamable's public video-info endpoint (`api.streamable.com/videos/<id>`),
/// which needs no authentication.
public actor StreamableClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Resolves a Streamable video ID to its highest-quality playable
    /// .mp4 URL.
    public func resolvePlayableURL(forID id: String) async throws -> URL {
        let request = URLRequest(url: URL(string: "https://api.streamable.com/videos/\(id)")!)
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(VideoResponse.self, from: data)
        guard let file = response.files.mp4Mobile ?? response.files.mp4,
              var urlString = file.url else {
            throw StreamableError.noPlayableURL
        }
        // Streamable's API sometimes returns protocol-relative or doubly-prefixed
        // URLs (e.g. "https:https://..."); normalize to a single https:// scheme.
        if urlString.hasPrefix("https:https://") {
            urlString = String(urlString.dropFirst("https:".count))
        } else if urlString.hasPrefix("//") {
            urlString = "https:" + urlString
        }
        guard let url = URL(string: urlString) else {
            throw StreamableError.noPlayableURL
        }
        return url
    }

    /// Handles `streamable.com/edit/<id>` (the creator's editing link, same
    /// video), which a "last path component" approach would read as "edit".
    private static let realApolloStreamablePattern =
        #"^(?:(?:https?:)?//)?(?:www\.)?streamable\.com/(?:edit/)?(\w+)$"#

    private static let streamableRegex = try! NSRegularExpression(pattern: realApolloStreamablePattern, options: [.caseInsensitive])

    /// Extracts a Streamable video ID from a streamable.com/<id> URL.
    public static func extractID(from url: URL) -> String? {
        guard url.host?.contains("streamable.com") == true else { return nil }
        let s = url.absoluteString
        if let match = streamableRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: s) {
            return String(s[range])
        }
        let components = url.pathComponents.filter { $0 != "/" }
        return components.last
    }
}

public enum StreamableError: Error {
    case noPlayableURL
}

private struct VideoResponse: Decodable {
    let files: Files

    struct Files: Decodable {
        let mp4: File?
        let mp4Mobile: File?

        enum CodingKeys: String, CodingKey {
            case mp4
            case mp4Mobile = "mp4-mobile"
        }
    }

    struct File: Decodable {
        let url: String?
    }
}
