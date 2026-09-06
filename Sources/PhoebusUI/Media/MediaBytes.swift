import Foundation
import PhoebusCore

/// Fetches an image's or GIF's bytes the one way: through the shared
/// `ImageCache` and the Imgur proxy, refusing error pages (a 404 body or
/// an HTML bot wall) instead of caching them. Every image fetch outside
/// `CachedAsyncImage` goes through here.
enum MediaBytes {
    static func data(for url: URL) async -> Data? {
        let effectiveURL = ImgurClient.proxiedImageURL(for: url)
        if let cached = await ImageCache.shared.data(for: effectiveURL) { return cached }
        guard let (fetched, response) = try? await URLSession.shared.data(from: effectiveURL) else { return nil }
        if let http = response as? HTTPURLResponse {
            let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            guard (200..<300).contains(http.statusCode), !type.hasPrefix("text/") else { return nil }
        }
        await ImageCache.shared.store(fetched, for: effectiveURL)
        return fetched
    }
}
