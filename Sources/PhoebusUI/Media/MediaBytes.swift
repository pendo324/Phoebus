import Foundation
import PhoebusCore

/// Fetches an image's or GIF's bytes the one way: through the shared
/// `ImageCache` and the Imgur proxy, refusing error pages (a 404 body or
/// an HTML bot wall) instead of caching them. Every image fetch outside
/// `CachedAsyncImage` goes through here, and so does `CachedAsyncImage`'s
/// own: rows, the prefetcher and viewers that ask for one URL at the same
/// time share a single request.
enum MediaBytes {
    private struct DownloadFailed: Error {}

    private static let downloads = InFlightCoalescer<URL, Data>()

    static func data(for url: URL) async -> Data? {
        await data(forProxied: ImgurClient.proxiedImageURL(for: url))
    }

    /// For a URL already passed through `ImgurClient.proxiedImageURL`.
    static func data(forProxied effectiveURL: URL) async -> Data? {
        if let cached = await ImageCache.shared.data(for: effectiveURL) { return cached }
        return try? await downloads.value(for: effectiveURL) {
            if let cached = await ImageCache.shared.data(for: effectiveURL) { return cached }
            guard let (fetched, response) = try? await URLSession.shared.data(from: effectiveURL) else { throw DownloadFailed() }
            if let http = response as? HTTPURLResponse {
                let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                guard (200..<300).contains(http.statusCode), !type.hasPrefix("text/") else { throw DownloadFailed() }
            }
            await ImageCache.shared.store(fetched, for: effectiveURL)
            return fetched
        }
    }
}
