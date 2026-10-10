import SwiftUI
import PhoebusCore

/// Fetches and decodes images a few rows before they scroll in, into the
/// caches `CachedAsyncImage` and inline comment images draw from, so a row
/// arrives with its image instead of a placeholder that then resizes it.
@MainActor
final class ImagePrefetcher {
    static let shared = ImagePrefetcher()

    /// Images being fetched at once; the rest wait for the next row.
    private static let concurrency = 4
    private var inFlight: Set<URL> = []

    func prefetch(_ urls: [URL]) {
        let screenPixelWidth = CachedAsyncImage.screenPixelWidth
        for url in urls {
            guard inFlight.count < Self.concurrency else { return }
            let key = ImgurClient.proxiedImageURL(for: url)
            guard !inFlight.contains(key),
                  DecodedImageCache.shared.image(for: key, target: .screenWidth) == nil else { continue }
            inFlight.insert(key)
            Task.detached(priority: .utility) {
                if let bytes = await MediaBytes.data(for: url) {
                    _ = await PlatformImage.displayReady(bytes, for: key, target: .screenWidth,
                                                         screenPixelWidth: screenPixelWidth)
                }
                await MainActor.run { _ = ImagePrefetcher.shared.inFlight.remove(key) }
            }
        }
    }
}
