import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Wikipedia article's summary, as Apollo's link card shows it: the
/// article title, the opening of its text, and its lead image.
public struct WikipediaSummary: Sendable, Equatable, Codable {
    public var title: String
    public var extract: String?
    public var thumbnailURL: URL?

    public init(title: String, extract: String?, thumbnailURL: URL?) {
        self.title = title
        self.extract = extract
        self.thumbnailURL = thumbnailURL
    }
}

/// Wikipedia article links get their own card, filled from Wikipedia's
/// REST summary endpoint rather than the page's OpenGraph tags.
public enum WikipediaClient {
    /// The article a link points at: the wiki's language and the page
    /// title as it appears in the path, or nil for anything that isn't
    /// a `*.wikipedia.org/wiki/…` article.
    public static func article(from url: URL) -> (language: String, title: String)? {
        guard let host = url.host?.lowercased(),
              host == "wikipedia.org" || host.hasSuffix(".wikipedia.org") else { return nil }
        let path = url.path
        guard path.hasPrefix("/wiki/") else { return nil }
        let title = String(path.dropFirst("/wiki/".count))
        guard !title.isEmpty else { return nil }
        // "en.m.wikipedia.org" and "en.wikipedia.org" are the same wiki.
        let labels = host.split(separator: ".").dropLast(2).filter { $0 != "m" && $0 != "www" }
        return (labels.first.map(String.init) ?? "en", title)
    }

    /// The summary request for an article link.
    public static func summaryURL(for url: URL) -> URL? {
        guard let article = article(from: url) else { return nil }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
        guard let encoded = article.title.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://\(article.language).wikipedia.org/api/rest_v1/page/summary/\(encoded)")
    }

    public static func parse(_ data: Data) -> WikipediaSummary? {
        struct Response: Decodable {
            struct Image: Decodable { let source: String }
            let title: String?
            let extract: String?
            let thumbnail: Image?
            let originalimage: Image?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let title = response.title, !title.isEmpty else { return nil }
        let extract = response.extract?.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = (response.thumbnail ?? response.originalimage).flatMap { URL(string: $0.source) }
        return WikipediaSummary(title: title, extract: extract?.isEmpty == false ? extract : nil,
                                thumbnailURL: image)
    }

    public static func fetchSummary(for url: URL, session: URLSession = .shared) async throws -> WikipediaSummary {
        guard let summaryURL = summaryURL(for: url) else { throw ClientError.notAnArticle }
        var request = URLRequest(url: summaryURL, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let summary = parse(data) else { throw ClientError.invalidResponse }
        return summary
    }

    public enum ClientError: Error {
        case notAnArticle
        case invalidResponse
    }
}
