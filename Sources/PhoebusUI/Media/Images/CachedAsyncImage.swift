import SwiftUI
import PhoebusCore
#if canImport(ImageIO)
import ImageIO
#endif

/// Async image loader with an in-memory cache, which SwiftUI's built-in
/// `AsyncImage` lacks.
///
/// Bounded by bytes and emptied on a memory warning (Reborn #1169).
/// `NSCache` needs a cost on every insert for `totalCostLimit` to mean
/// anything.
actor ImageCache {
    static let shared = ImageCache()
    static let byteBudget = 64 * 1024 * 1024
    private let cache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = ImageCache.byteBudget
        return cache
    }()

    init() {
        MemoryWarningPurge.register { [weak self] in await self?.removeAll() }
    }

    func data(for url: URL) -> Data? {
        cache.object(forKey: url as NSURL) as Data?
    }

    func store(_ data: Data, for url: URL) {
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Runs cache purges when iOS warns about memory.
enum MemoryWarningPurge {
    static func register(_ purge: @escaping @Sendable () async -> Void) {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: nil) { _ in
            Task { await purge() }
        }
        #endif
    }
}

/// A target rung to downsample a decoded image to, rather than keeping the
/// fetched bytes at full resolution in memory.
///
/// Gallery View picks a rung near a 640pt target for grid thumbnails.
/// Downsampling via `CGImageSourceCreateThumbnailAtIndex` keeps one shared
/// cache, network path and Imgur-proxy rewrite.
public enum ImageDownsampleTarget: Equatable, Sendable {
    /// No downsampling: decode and display at native resolution. For the
    /// zoomable viewers.
    case none
    /// No wider than the screen: what inline media can show. The default,
    /// so a 12-megapixel photo in a comment isn't decoded and drawn in full
    /// while the list scrolls.
    case screenWidth
    /// Downsample so the image's longer side is approximately this
    /// many points, at the given scale.
    case pixelWidth(CGFloat, scale: CGFloat)

    /// Gallery View's grid rung target.
    public static let galleryTile = ImageDownsampleTarget.pixelWidth(640, scale: 2)

    /// The longest side to decode at, for an image of `pixelSize`; nil
    /// decodes at full size.
    func maxPixelSize(for pixelSize: CGSize, screenPixelWidth: CGFloat) -> CGFloat? {
        switch self {
        case .none:
            return nil
        case .screenWidth:
            guard pixelSize.width > screenPixelWidth, pixelSize.width > 0 else { return nil }
            return (max(pixelSize.width, pixelSize.height) * screenPixelWidth / pixelSize.width).rounded(.up)
        case .pixelWidth(let width, let scale):
            return width * scale
        }
    }

    var cacheKey: String {
        switch self {
        case .none: return "full"
        case .screenWidth: return "screen"
        case .pixelWidth(let width, let scale): return "\(Int(width * scale))"
        }
    }
}

public struct CachedAsyncImage: View {
    let url: URL?
    /// Decoded once per load, not in every `body`.
    @State private var image: PlatformImage?
    @State private var failed = false
    /// The URL `image`/`failed` belong to, so a reused view whose URL
    /// changes shows its placeholder instead of the previous image.
    @State private var loadedURL: URL?

    /// How the decoded image fills its frame. Defaults to `.fit`; a banner
    /// needs `.fill` to cover a fixed-height strip. An outer
    /// `.aspectRatio(.fill)` has no effect since `.fit` is already applied.
    private let contentMode: ContentMode
    /// See `ImageDownsampleTarget`. Defaults to `.none` (native
    /// resolution).
    private let downsampleTarget: ImageDownsampleTarget

    public init(url: URL?, contentMode: ContentMode = .fit, downsampleTarget: ImageDownsampleTarget = .screenWidth) {
        self.url = url
        self.contentMode = contentMode
        self.downsampleTarget = downsampleTarget
    }

    /// The image to draw now: this view's own, or one already decoded for a
    /// row that scrolled away and back, so it comes back at its size on the
    /// first frame instead of as a placeholder that then resizes the row.
    private var shownImage: PlatformImage? {
        if let image, loadedURL == url { return image }
        guard let url else { return nil }
        return DecodedImageCache.shared.image(for: ImgurClient.proxiedImageURL(for: url), target: downsampleTarget)
    }

    public var body: some View {
        Group {
            if let image = shownImage {
                image.swiftUIImage
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed, loadedURL == url {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 120)
            } else {
                // A bare `ProgressView()` has a tiny intrinsic size, and in a `List` that
                // near-zero height gets locked into the scroll content height, pushing
                // later content out of `ScrollViewProxy.scrollTo` reach. Reserve a stable
                // minimum height.
                ProgressView()
                    .frame(minHeight: 200)
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard loadedURL != url || (image == nil && !failed) else { return }
        guard let url else {
            image = nil; failed = true; loadedURL = nil
            return
        }
        let result = await Self.fetch(url, downsampleTarget: downsampleTarget, screenPixelWidth: Self.screenPixelWidth)
        // A cancelled load (the row scrolled away mid-fetch) is not a
        // failure: leave it loading so the next appearance retries.
        guard !Task.isCancelled, let result else { return }
        loadedURL = url
        switch result {
        case .success(let decoded): image = decoded; failed = false
        case .failure: image = nil; failed = true
        }
    }

    private struct LoadFailed: Error {}

    /// The screen's width in pixels, for `ImageDownsampleTarget.screenWidth`.
    static var screenPixelWidth: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.nativeBounds.width
        #else
        2048
        #endif
    }

    /// Fetches (or reads from cache) and decodes off the main actor.
    /// Nil means cancelled.
    private nonisolated static func fetch(_ url: URL, downsampleTarget: ImageDownsampleTarget,
                                          screenPixelWidth: CGFloat) async -> Result<PlatformImage, LoadFailed>? {
        // Reborn's Imgur proxy workaround is applied here, in the shared loader
        // every Imgur direct-image URL goes through.
        let effectiveURL = ImgurClient.proxiedImageURL(for: url)
        if let cached = DecodedImageCache.shared.image(for: effectiveURL, target: downsampleTarget) {
            return .success(cached)
        }
        var bytes = await ImageCache.shared.data(for: effectiveURL)
        if bytes == nil {
            do {
                let (fetched, response) = try await URLSession.shared.data(from: effectiveURL)
                // Never cache an error page: a 403/404 body or an HTML
                // bot wall would otherwise sit in the cache and fail to
                // decode on every later appearance.
                if let http = response as? HTTPURLResponse {
                    let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                    guard (200..<300).contains(http.statusCode), !type.hasPrefix("text/") else {
                        return .failure(LoadFailed())
                    }
                }
                await ImageCache.shared.store(fetched, for: effectiveURL)
                bytes = fetched
            } catch {
                if (error as? URLError)?.code == .cancelled || error is CancellationError || Task.isCancelled {
                    return nil
                }
                return .failure(LoadFailed())
            }
        }
        guard let bytes,
              let decoded = await PlatformImage.displayReady(bytes, for: effectiveURL, target: downsampleTarget,
                                                            screenPixelWidth: screenPixelWidth)
        else { return .failure(LoadFailed()) }
        return .success(decoded)
    }
}

extension PlatformImage {
    /// Decodes `bytes` at `target`'s size, ready to draw, and keeps the
    /// result in `DecodedImageCache` under `url`. Off the main actor: a full
    /// decode of a camera photo takes long enough to drop frames.
    nonisolated static func displayReady(_ bytes: Data, for url: URL, target: ImageDownsampleTarget,
                                         screenPixelWidth: CGFloat) async -> PlatformImage? {
        let image: PlatformImage
        if let maxPixelSize = target.maxPixelSize(for: pixelSize(of: bytes), screenPixelWidth: screenPixelWidth),
           let downsampled = PlatformImage(data: bytes, downsampledToMaxPixelSize: maxPixelSize) {
            image = downsampled
        } else {
            guard let decoded = PlatformImage(data: bytes) else { return nil }
            image = await decoded.preparedForDisplay()
        }
        DecodedImageCache.shared.store(image, for: url, target: target)
        return image
    }
}

/// Decoded images, ready to draw, separate from `ImageCache`'s raw bytes:
/// re-decoding each time a row scrolls back wastes CPU and shows a
/// placeholder first, which resizes the row mid-scroll. `NSCache` is
/// thread-safe, so a view reads it synchronously while it draws.
///
/// Costed by decoded bytes (width × height × 4 at the image's scale) and
/// emptied on a memory warning, like `ImageCache`.
final class DecodedImageCache: @unchecked Sendable {
    static let shared = DecodedImageCache()
    static let byteBudget = 96 * 1024 * 1024
    private final class Entry { let image: PlatformImage; init(_ image: PlatformImage) { self.image = image } }
    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = DecodedImageCache.byteBudget
        return cache
    }()

    init() {
        MemoryWarningPurge.register { [weak self] in self?.removeAll() }
    }

    private func key(_ url: URL, _ target: ImageDownsampleTarget) -> NSString {
        "\(url.absoluteString)#\(target.cacheKey)" as NSString
    }

    func image(for url: URL, target: ImageDownsampleTarget) -> PlatformImage? {
        cache.object(forKey: key(url, target))?.image
    }

    func store(_ image: PlatformImage, for url: URL, target: ImageDownsampleTarget) {
        cache.setObject(Entry(image), forKey: key(url, target), cost: image.decodedByteCount)
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Thin cross-platform wrapper so this compiles for both iOS (UIImage) and
/// macOS (NSImage).
struct PlatformImage: @unchecked Sendable {
    #if canImport(UIKit)
    let uiImage: UIImage

    /// What the decoded bitmap costs in memory, for `DecodedImageCache`.
    var decodedByteCount: Int {
        let scale = uiImage.scale
        return Int(uiImage.size.width * scale * uiImage.size.height * scale * 4)
    }
    init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        uiImage = image
    }
    init(uiImage image: UIImage) { uiImage = image }
    /// Decodes the bitmap now, off the main thread, instead of lazily
    /// on the first draw.
    func preparedForDisplay() async -> PlatformImage {
        guard let prepared = await uiImage.byPreparingForDisplay() else { return self }
        return PlatformImage(uiImage: prepared)
    }
    /// ImageIO's hardware-accelerated downsampler: decodes directly at the
    /// target size. See `ImageDownsampleTarget`.
    init?(data: Data, downsampledToMaxPixelSize maxPixelSize: CGFloat) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        uiImage = UIImage(cgImage: cgImage)
    }
    var swiftUIImage: Image { Image(uiImage: uiImage) }
    /// The encoded image's pixel size, read from its header without decoding.
    static func pixelSize(of data: Data) -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return .zero }
        // Orientations 5–8 are rotated a quarter turn.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
    /// Height / width.
    var aspectRatio: CGFloat {
        uiImage.size.width > 0 ? uiImage.size.height / uiImage.size.width : 1
    }
    #elseif canImport(AppKit)
    let nsImage: NSImage

    var decodedByteCount: Int { Int(nsImage.size.width * nsImage.size.height * 4) }
    init?(data: Data) {
        guard let image = NSImage(data: data) else { return nil }
        nsImage = image
    }
    func preparedForDisplay() async -> PlatformImage { self }
    init?(data: Data, downsampledToMaxPixelSize maxPixelSize: CGFloat) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        nsImage = NSImage(cgImage: cgImage, size: .zero)
    }
    var swiftUIImage: Image { Image(nsImage: nsImage) }
    static func pixelSize(of data: Data) -> CGSize { .zero }
    /// Height / width.
    var aspectRatio: CGFloat {
        nsImage.size.width > 0 ? nsImage.size.height / nsImage.size.width : 1
    }
    #endif
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif
