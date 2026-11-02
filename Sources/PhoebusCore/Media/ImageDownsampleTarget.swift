import Foundation

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

    /// A user picture drawn `pointSize` wide: decoded at its own pixels, so a
    /// 256 px avatar in a 27pt row is not kept at 256 KB. Larger views of the
    /// same picture (the profile header) ask for their own, bigger target and
    /// decode from the same fetched bytes.
    public static func avatar(pointSize: CGFloat, scale: CGFloat) -> ImageDownsampleTarget {
        .pixelWidth(pointSize, scale: scale)
    }

    /// The longest side to decode at, for an image of `pixelSize`; nil
    /// decodes at full size. An image already no larger than a
    /// `pixelWidth` target is decoded as it is, never scaled up.
    public func maxPixelSize(for pixelSize: CGSize, screenPixelWidth: CGFloat) -> CGFloat? {
        switch self {
        case .none:
            return nil
        case .screenWidth:
            guard pixelSize.width > screenPixelWidth, pixelSize.width > 0 else { return nil }
            return (max(pixelSize.width, pixelSize.height) * screenPixelWidth / pixelSize.width).rounded(.up)
        case .pixelWidth(let width, let scale):
            let limit = width * scale
            guard pixelSize != .zero else { return limit }
            return max(pixelSize.width, pixelSize.height) > limit ? limit : nil
        }
    }

    /// The key suffix that keeps one picture's decoded sizes apart in
    /// `DecodedImageCache`.
    public var cacheKey: String {
        switch self {
        case .none: return "full"
        case .screenWidth: return "screen"
        case .pixelWidth(let width, let scale): return "\(Int(width * scale))"
        }
    }
}
