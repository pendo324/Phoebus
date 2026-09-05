import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One GIF from a Giphy trending/search response.
public struct GiphyGIF: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    /// Full-resolution GIF URL for the actual post/comment upload.
    public let downloadURL: URL?
    /// Smaller preview URL for the picker grid.
    public let previewURL: URL?
    public let pageURL: String

    public init(id: String, title: String, downloadURL: URL?, previewURL: URL?, pageURL: String) {
        self.id = id
        self.title = title
        self.downloadURL = downloadURL
        self.previewURL = previewURL
        self.pageURL = pageURL
    }
}

/// Reimplements Apollo-Reborn's Giphy client: a GIF search/
/// trending client for the Quick Bar's GIF picker.
/// Requires the user's own registered Giphy API key
/// (developers.giphy.com); Apollo's own key is never reused (see
/// `CustomAPISettings.giphyAPIKey`).
public enum GiphyClient {
    /// Set from `CustomAPISettingsStore` when the user configures
    /// their own Giphy API key.
    public nonisolated(unsafe) static var apiKey: String?

    public enum ClientError: Error, Sendable, LocalizedError {
        case notConfigured
        case invalidResponse
        case apiError(String)

        /// Without this, Swift's default `Error` description collapses to
        /// "ClientError error 0" and hides the real Giphy API message (e.g.
        /// "BANNED" for a rate-limited or blocked key), which is what the user
        /// needs to diagnose a bad or overused key.
        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Configure your Giphy API key in Settings > Custom API to use the GIF picker."
            case .invalidResponse:
                return "Giphy returned an unexpected response."
            case .apiError(let message):
                return "Giphy API error: \(message)"
            }
        }
    }

    /// Page size 25 and query parameters (`rating=pg-13`,
    /// `bundle=messaging_non_clips`).
    private static let pageSize = 25

    public static func fetchTrending(offset: Int = 0, session: URLSession = .shared) async throws -> (gifs: [GiphyGIF], hasMore: Bool) {
        try await fetch(path: "trending", extraItems: [], offset: offset, session: session)
    }

    public static func search(query: String, offset: Int = 0, session: URLSession = .shared) async throws -> (gifs: [GiphyGIF], hasMore: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await fetchTrending(offset: offset, session: session)
        }
        return try await fetch(path: "search", extraItems: [URLQueryItem(name: "q", value: trimmed)], offset: offset, session: session)
    }

    private static func fetch(path: String, extraItems: [URLQueryItem], offset: Int, session: URLSession) async throws -> (gifs: [GiphyGIF], hasMore: Bool) {
        guard let apiKey, !apiKey.isEmpty else { throw ClientError.notConfigured }

        var components = URLComponents(string: "https://api.giphy.com/v1/gifs/\(path)")!
        var items = extraItems
        items.append(contentsOf: [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "limit", value: "\(pageSize)"),
            URLQueryItem(name: "rating", value: "pg-13"),
            URLQueryItem(name: "bundle", value: "messaging_non_clips"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        components.queryItems = items

        let (data, _) = try await session.data(from: components.url!)
        return try parse(data: data, requestedOffset: offset)
    }

    /// Exposed for testing response-shape parsing without a live network call.
    public static func parse(data: Data, requestedOffset: Int) throws -> (gifs: [GiphyGIF], hasMore: Bool) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.invalidResponse
        }
        if let meta = root["meta"] as? [String: Any], let status = meta["status"] as? Int, status != 200 {
            throw ClientError.apiError((meta["msg"] as? String) ?? "Giphy request failed")
        }
        let dataArray = root["data"] as? [[String: Any]] ?? []
        let gifs = dataArray.compactMap(gif(fromDictionary:))

        let pagination = root["pagination"] as? [String: Any]
        let hasMore: Bool
        if let totalCount = pagination?["total_count"] as? Int,
           let offset = pagination?["offset"] as? Int,
           let count = pagination?["count"] as? Int {
            hasMore = count > 0 && (offset + count) < totalCount
        } else {
            hasMore = dataArray.count >= pageSize
        }
        return (gifs, hasMore)
    }

    private static func gif(fromDictionary dict: [String: Any]) -> GiphyGIF? {
        guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
        let title = dict["title"] as? String ?? ""
        let pageURL = (dict["url"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "https://giphy.com/gifs/\(id)"

        let images = dict["images"] as? [String: Any]
        let original = images?["original"] as? [String: Any]
        let downsizedMedium = images?["downsized_medium"] as? [String: Any]
        let fixedWidth = images?["fixed_width"] as? [String: Any]
        let fixedHeightSmall = images?["fixed_height_small"] as? [String: Any]

        let downloadURL = imageURL(from: original) ?? imageURL(from: downsizedMedium) ?? imageURL(from: fixedWidth) ?? imageURL(from: fixedHeightSmall)
        let previewURL = imageURL(from: fixedWidth) ?? imageURL(from: fixedHeightSmall)

        return GiphyGIF(id: id, title: title, downloadURL: downloadURL, previewURL: previewURL, pageURL: pageURL)
    }

    private static func imageURL(from dict: [String: Any]?) -> URL? {
        guard let urlString = dict?["url"] as? String, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
}
