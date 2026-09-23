import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Fetches the picture a Share as Image card carries, so an image post's card
/// shows the picture rather than the title alone.
///
/// For a gallery post, Reborn composes the items into a feed-style collage
/// instead of stock Apollo's compact link card. This does the composing
/// directly.
public enum ShareCardImageLoader {
    #if canImport(UIKit)
    /// Reborn's collage geometry.
    static let contentWidth: CGFloat = 320
    static let gap: CGFloat = 3
    static let cornerRadius: CGFloat = 12
    /// Beyond this many, the last tile becomes a "+N" overflow badge.
    static let maxVisible = 4

    /// The card image plus its aspect ratio, which the card needs to
    /// lay the picture out at a fixed width.
    public struct Result {
        public let image: Image
        public let aspect: CGFloat
    }

    public static func load(urls: [URL], session: URLSession = .shared) async -> Result? {
        guard !urls.isEmpty else { return nil }
        if urls.count == 1 {
            guard let image = await fetch(urls[0], session: session),
                  image.size.height > 0 else { return nil }
            return Result(
                image: Image(uiImage: image),
                aspect: image.size.width / image.size.height)
        }
        let visible = Array(urls.prefix(maxVisible))
        var tiles: [UIImage] = []
        for url in visible {
            guard let image = await fetch(url, session: session) else { continue }
            tiles.append(image)
        }
        guard !tiles.isEmpty else { return nil }
        guard let collage = collage(tiles: tiles, overflow: max(0, urls.count - tiles.count)),
              collage.size.height > 0 else { return nil }
        return Result(
            image: Image(uiImage: collage),
            aspect: collage.size.width / collage.size.height)
    }

    private static func fetch(_ url: URL, session: URLSession) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    /// Composes tiles into Reborn's feed-style collage.
    ///
    /// One large tile on the left and the rest stacked on the right,
    /// which is the layout the feed's own gallery cell uses.
    static func collage(tiles: [UIImage], overflow: Int) -> UIImage? {
        guard let first = tiles.first else { return nil }
        let height = contentWidth * 0.62
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: contentWidth, height: height))
        return renderer.image { context in
            let rects = layout(count: tiles.count, in: CGRect(
                x: 0, y: 0, width: contentWidth, height: height))
            for (index, rect) in rects.enumerated() {
                let tile = index < tiles.count ? tiles[index] : first
                drawAspectFill(tile, in: rect)
                // The "+N" badge replaces nothing; it sits over the last
                // tile, which is what makes the count legible.
                if index == rects.count - 1, overflow > 0 {
                    context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
                    context.cgContext.fill(rect)
                    let text = "+\(overflow)"
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                        .foregroundColor: UIColor.white,
                    ]
                    let size = (text as NSString).size(withAttributes: attributes)
                    (text as NSString).draw(
                        at: CGPoint(x: rect.midX - size.width / 2,
                                    y: rect.midY - size.height / 2),
                        withAttributes: attributes)
                }
            }
        }
    }

    /// Tile rects for a collage of `count` images.
    static func layout(count: Int, in bounds: CGRect) -> [CGRect] {
        guard count > 1 else { return [bounds] }
        let leftWidth = (bounds.width - gap) * (count == 2 ? 0.5 : 0.62)
        let left = CGRect(x: 0, y: 0, width: leftWidth, height: bounds.height)
        let rightX = leftWidth + gap
        let rightWidth = bounds.width - rightX
        let stacked = count - 1
        let tileHeight = (bounds.height - gap * CGFloat(stacked - 1)) / CGFloat(stacked)
        var rects = [left]
        for index in 0..<stacked {
            rects.append(CGRect(
                x: rightX,
                y: (tileHeight + gap) * CGFloat(index),
                width: rightWidth,
                height: tileHeight))
        }
        return rects
    }

    /// Draws aspect-filled and cropped, so a tile is never squashed.
    private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        path.addClip()
        image.draw(in: CGRect(origin: origin, size: size))
        UIGraphicsGetCurrentContext()?.resetClip()
    }
    #endif
}
