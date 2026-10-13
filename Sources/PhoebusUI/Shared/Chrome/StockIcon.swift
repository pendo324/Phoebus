import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
import CoreGraphics
import CoreText
#endif

/// Draws one of the named interface glyphs (`posts-points`,
/// `slide-save-hollow`, `option-sort-top`, ...) from its `StockGlyph`
/// recipe: an SF Symbol, a kit icon bundled as a PDF in `Resources/Glyphs`,
/// or a glyph composed in code.
///
/// `size` defaults to the frame Apollo's glyph occupied, so rows keep their
/// layout; another size scales the whole glyph. SF Symbols draw natively;
/// everything else is rasterised at screen scale, cached per (name, size),
/// and marked `.alwaysTemplate` so `foregroundStyle` tints it like a symbol.
/// The feed orbs are the only full-colour glyphs.
public struct StockIcon: View {
    public let name: String
    public let size: CGSize?

    public init(_ name: String, size: CGSize? = nil) {
        self.name = name
        self.size = size
    }

    public static func intrinsicSize(_ name: String) -> CGSize {
        StockGlyph.glyph(name)?.frame ?? CGSize(width: 16, height: 16)
    }

    /// Whether `name` is one of the named glyphs rather than an SF Symbol
    /// name.
    public static func isBundled(_ name: String) -> Bool {
        StockGlyph.glyph(name) != nil
    }

    static func isColored(_ name: String) -> Bool {
        StockGlyph.glyph(name)?.isColored ?? false
    }

    private var resolvedSize: CGSize { size ?? StockIcon.intrinsicSize(name) }

    public var body: some View {
        let frame = resolvedSize
        Group {
            if let glyph = StockGlyph.glyph(name),
               case let .symbol(symbol, pointSize, weight, rotation) = glyph.recipe {
                Image(systemName: symbol)
                    .font(.system(size: pointSize * Self.scale(glyph, frame), weight: weight.fontWeight))
                    .imageScale(.medium)
                    .symbolRenderingMode(.monochrome)
                    .rotationEffect(.degrees(rotation))
            } else {
                #if canImport(UIKit)
                if let image = StockIcon.image(named: name, size: frame) {
                    Image(uiImage: image)
                        .renderingMode(StockIcon.isColored(name) ? .original : .template)
                        .resizable()
                }
                #endif
            }
        }
        .frame(width: frame.width, height: frame.height)
        // Sits on its bottom edge in baseline-aligned stacks, like an image.
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
        .accessibilityHidden(true)
    }

    static func scale(_ glyph: StockGlyph.Glyph, _ frame: CGSize) -> CGFloat {
        min(frame.width / glyph.frame.width, frame.height / glyph.frame.height)
    }

    /// A glyph as a plain template `Image` at its own size, for menu rows and
    /// other slots that take only an image.
    static func image(_ name: String) -> Image {
        #if canImport(UIKit)
        if let image = image(named: name, size: intrinsicSize(name)) {
            return Image(uiImage: image)
        }
        #endif
        return Image(systemName: "questionmark.square.dashed")
    }

    #if canImport(UIKit)
    /// A named glyph at its own size, else the SF Symbol `name`: for UIKit
    /// controls (bar buttons, `UIMenu` rows) that take an image.
    public static func uiImage(_ name: String) -> UIImage? {
        isBundled(name) ? image(named: name, size: intrinsicSize(name)) : UIImage(systemName: name)
    }

    private struct CacheKey: Hashable {
        let name: String
        let width: CGFloat
        let height: CGFloat
    }

    nonisolated(unsafe) private static var cache: [CacheKey: UIImage] = [:]
    private static let cacheLock = NSLock()

    static func image(named name: String, size: CGSize) -> UIImage? {
        guard let glyph = StockGlyph.glyph(name), size.width > 0, size.height > 0 else { return nil }
        let key = CacheKey(name: name, width: size.width, height: size.height)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            GlyphRenderer.draw(glyph.recipe, in: CGRect(origin: .zero, size: size),
                               scale: scale(glyph, size), color: .black, cg: context.cgContext)
        }.withRenderingMode(glyph.isColored ? .alwaysOriginal : .alwaysTemplate)
        cache[key] = rendered
        return rendered
    }
    #endif
}

/// An icon by name: a named glyph (`StockIcon`) when there is one, else the
/// SF Symbol of that name.
struct ApolloIconImage: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        if StockIcon.isBundled(name) {
            // A plain `Image`, so SwiftUI menus can carry it into `UIMenu` rows.
            StockIcon.image(name)
        } else {
            Image(systemName: name)
        }
    }
}

extension StockGlyph.Weight {
    var fontWeight: Font.Weight {
        switch self {
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    #if canImport(UIKit)
    var uiWeight: UIImage.SymbolWeight {
        switch self {
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    var fontWeightUIKit: UIFont.Weight {
        switch self {
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
    #endif
}

#if canImport(UIKit)
/// Draws a `StockGlyph.Recipe` into a CoreGraphics context (UIKit's
/// y-down coordinates), centred in `rect`.
enum GlyphRenderer {
    static func draw(_ recipe: StockGlyph.Recipe, in rect: CGRect, scale k: CGFloat,
                     color: UIColor, cg: CGContext) {
        switch recipe {
        case let .symbol(name, size, weight, rotation):
            guard let image = symbol(name, size * k, weight, color: color) else { return }
            cg.saveGState()
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: CGFloat(rotation) * .pi / 180)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
            cg.restoreGState()
        case let .asset(name, ink):
            drawPDF(name, fittedTo: CGSize(width: ink.width * k, height: ink.height * k),
                    centredIn: rect, color: color, cg: cg)
        case let .composed(composition, size):
            drawComposition(composition, size: size * k, in: rect, color: color, cg: cg)
        case let .text(string, size, weight, rounded):
            drawText(string, font: font(size * k, weight.fontWeightUIKit, rounded: rounded),
                     inkCentredAt: CGPoint(x: rect.midX, y: rect.midY), color: color, cg: cg)
        case let .orb(inner, rgb):
            cg.setFillColor(UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                                    green: CGFloat((rgb >> 8) & 0xFF) / 255,
                                    blue: CGFloat(rgb & 0xFF) / 255, alpha: 1).cgColor)
            cg.fillEllipse(in: rect)
            draw(inner, in: rect, scale: k, color: .white, cg: cg)
        }
    }

    // MARK: - Pieces

    static func symbol(_ name: String, _ pointSize: CGFloat, _ weight: StockGlyph.Weight,
                       color: UIColor) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight.uiWeight)
        return UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }

    /// Draws `image` centred on `centre` and returns the rectangle of its ink.
    @discardableResult
    static func drawCentred(_ image: UIImage, at centre: CGPoint) -> CGRect {
        let frame = CGRect(x: centre.x - image.size.width / 2, y: centre.y - image.size.height / 2,
                           width: image.size.width, height: image.size.height)
        image.draw(in: frame)
        let ink = inkBounds(of: image)
        return ink.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    /// The opaque part of an image, in its own points (y down).
    static func inkBounds(of image: UIImage) -> CGRect {
        let scale: CGFloat = 4
        let width = Int((image.size.width * scale).rounded(.up))
        let height = Int((image.size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else {
            return CGRect(origin: .zero, size: image.size)
        }
        UIGraphicsPushContext(context)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        UIGraphicsPopContext()
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return CGRect(origin: .zero, size: image.size)
        }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[y * width + x] > 127 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return CGRect(origin: .zero, size: image.size) }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    static func font(_ size: CGFloat, _ weight: UIFont.Weight, rounded: Bool = false,
                     serif: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign? = rounded ? .rounded : (serif ? .serif : nil)
        guard let design, let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Draws a string with its ink centred on `centre`. `strokeWidth` (a
    /// percentage of the font size) draws the outline only.
    static func drawText(_ string: String, font: UIFont, inkCentredAt centre: CGPoint,
                         color: UIColor, strokeWidth: CGFloat? = nil, cg: CGContext) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        if let strokeWidth {
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = strokeWidth
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        cg.saveGState()
        cg.setFillColor(color.cgColor)
        cg.setStrokeColor(color.cgColor)
        cg.textMatrix = .identity
        cg.translateBy(x: centre.x - ink.midX, y: centre.y + ink.midY)
        cg.scaleBy(x: 1, y: -1)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    static func drawPDF(_ name: String, fittedTo box: CGSize, centredIn rect: CGRect,
                        color: UIColor, cg: CGContext) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "pdf",
                                          subdirectory: StockGlyph.assetDirectory),
              let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else { return }
        let media = page.getBoxRect(.mediaBox)
        guard media.width > 0, media.height > 0 else { return }
        let s = min(box.width / media.width, box.height / media.height)
        let size = CGSize(width: media.width * s, height: media.height * s)
        let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                            width: size.width, height: size.height)
        // Draw the black artwork, then recolour it through its own alpha.
        cg.saveGState()
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        cg.translateBy(x: target.minX, y: target.maxY)
        cg.scaleBy(x: s, y: -s)
        cg.translateBy(x: -media.minX, y: -media.minY)
        cg.drawPDFPage(page)
        cg.setBlendMode(.sourceIn)
        cg.setFillColor(color.cgColor)
        cg.fill(media)
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    // MARK: - Compositions

    static func drawComposition(_ composition: StockGlyph.Composition, size p: CGFloat, in rect: CGRect,
                                color: UIColor, cg: CGContext) {
        // SF Symbols' light stroke is 1/16 of the point size.
        let s = p * 0.0625
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setLineCap(.round)
        cg.setStrokeColor(color.cgColor)
        cg.setFillColor(color.cgColor)
        switch composition {
        case .slashedUpArrow, .slashedDownArrow:
            // A slash from the arrow's top-left to its bottom-right with a
            // one-stroke gap on its upper-right side, as SF's `.slash` symbols.
            let arrow = composition == .slashedUpArrow ? "arrow.up" : "arrow.down"
            guard let image = symbol(arrow, p, .light, color: color) else { return }
            let ink = drawCentred(image, at: centre)
            let half = (ink.height - s) / 2
            let a = CGPoint(x: ink.midX - half, y: ink.minY + s / 2)
            let b = CGPoint(x: ink.midX + half, y: ink.maxY - s / 2)
            let n = CGPoint(x: s / sqrt(2), y: -s / sqrt(2))
            cg.setBlendMode(.clear)
            cg.setLineWidth(s * 2)
            cg.strokeLineSegments(between: [CGPoint(x: a.x + n.x, y: a.y + n.y), CGPoint(x: b.x + n.x, y: b.y + n.y)])
            cg.setBlendMode(.normal)
            cg.setLineWidth(s)
            cg.strokeLineSegments(between: [a, b])
        case .parentComment:
            guard let bubble = symbol("bubble", p, .light, color: color),
                  let chevron = symbol("chevron.up", p * 0.5, .light, color: color) else { return }
            drawCentred(bubble, at: centre)
            drawCentred(chevron, at: CGPoint(x: centre.x, y: centre.y - p * 0.07))
        case .collapseToRoot:
            // The collapse glyph moved down so it and the bar above are centred.
            guard let chevron = symbol("chevron.up", p, .light, color: color) else { return }
            let ink = drawCentred(chevron, at: CGPoint(x: centre.x, y: centre.y + s * 1.25))
            cg.setLineWidth(s)
            let y = ink.minY - s * 2
            cg.strokeLineSegments(between: [CGPoint(x: ink.minX + s / 2, y: y), CGPoint(x: ink.maxX - s / 2, y: y)])
        case .hideAbove:
            // An eye under a small chevron and a bar: everything above goes.
            guard let eye = symbol("eye", p, .light, color: color),
                  let chevron = symbol("chevron.up", p * 0.4, .light, color: color) else { return }
            let eyeInk = inkBounds(of: eye)
            let chevronInk = inkBounds(of: chevron)
            let gap = s * 1.5
            let total = s + gap + chevronInk.height + gap * 1.5 + eyeInk.height
            let top = centre.y - total / 2
            cg.setLineWidth(s)
            let barInset = eyeInk.width * 0.05
            cg.strokeLineSegments(between: [CGPoint(x: centre.x - eyeInk.width / 2 + barInset, y: top + s / 2),
                                            CGPoint(x: centre.x + eyeInk.width / 2 - barInset, y: top + s / 2)])
            let chevronMid = top + s + gap + chevronInk.height / 2
            chevron.draw(at: CGPoint(x: centre.x - chevronInk.midX, y: chevronMid - chevronInk.midY))
            let eyeMid = top + total - eyeInk.height / 2
            eye.draw(at: CGPoint(x: centre.x - eyeInk.midX, y: eyeMid - eyeInk.midY))
        case .multireddit:
            guard let circle = symbol("circle.fill", p, .regular, color: color) else { return }
            let ink = drawCentred(circle, at: centre)
            cg.setBlendMode(.clear)
            drawText("m", font: font(p * 0.8, .semibold, rounded: true),
                     inkCentredAt: CGPoint(x: ink.midX, y: ink.midY), color: color, cg: cg)
        case .subredditWiki:
            // The W's outline only is cut from the cover, right of the spine.
            guard let book = symbol("book.closed.fill", p, .regular, color: color) else { return }
            let ink = drawCentred(book, at: centre)
            cg.setBlendMode(.clear)
            drawText("W", font: font(p * 0.48, .regular, serif: true),
                     inkCentredAt: CGPoint(x: ink.midX + ink.width * 0.06, y: ink.midY - p * 0.067),
                     color: color, strokeWidth: 6, cg: cg)
        case .smiley:
            guard let circle = symbol("circle", p, .regular, color: color) else { return }
            let ink = drawCentred(circle, at: centre)
            let r = ink.width / 2
            let eye = r * 0.13
            for dx in [-r * 0.36, r * 0.36] {
                cg.fillEllipse(in: CGRect(x: ink.midX + dx - eye, y: ink.midY - r * 0.28 - eye,
                                          width: eye * 2, height: eye * 2))
            }
            cg.setLineWidth(r * 0.15)
            cg.addArc(center: CGPoint(x: ink.midX, y: ink.midY - r * 0.05), radius: r * 0.48,
                      startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: false)
            cg.strokePath()
        case .subredditTag, .subredditTagSolid:
            drawTag(side: p, solid: composition == .subredditTagSolid, centre: centre, color: color, cg: cg)
        }
    }

    /// The subreddit tag: a pentagon pointing up-left with a lower-case r
    /// in its body, drawn for Phoebus.
    private static func drawTag(side: CGFloat, solid: Bool, centre: CGPoint, color: UIColor, cg: CGContext) {
        let width: CGFloat = 92, height: CGFloat = 112, tip: CGFloat = 40
        let outline = CGMutablePath()
        outline.addLines(between: [
            CGPoint(x: 0, y: -height / 2),
            CGPoint(x: width / 2, y: -height / 2 + tip),
            CGPoint(x: width / 2, y: height / 2),
            CGPoint(x: -width / 2, y: height / 2),
            CGPoint(x: -width / 2, y: -height / 2 + tip),
        ])
        outline.closeSubpath()
        var rotate = CGAffineTransform(rotationAngle: -.pi / 4)
        guard let bounds = outline.copy(using: &rotate)?.boundingBoxOfPath else { return }
        let stroke = solid ? 0 : side * 0.058
        let k = (side - stroke) / max(bounds.width, bounds.height)
        var transform = CGAffineTransform(translationX: centre.x - bounds.midX * k, y: centre.y - bounds.midY * k)
            .scaledBy(x: k, y: k)
            .rotated(by: -.pi / 4)
        guard let path = outline.copy(using: &transform) else { return }
        // The r sits in the middle of the tag's body, away from the point.
        let body = CGPoint(x: 0, y: tip / 2).applying(transform)
        cg.setLineJoin(.round)
        if solid {
            cg.addPath(path)
            cg.fillPath()
            cg.setBlendMode(.clear)
            drawText("r", font: font(side * 0.55, .semibold, rounded: true), inkCentredAt: body, color: color, cg: cg)
        } else {
            cg.setLineWidth(stroke)
            cg.addPath(path)
            cg.strokePath()
            drawText("r", font: font(side * 0.55, .light, rounded: true), inkCentredAt: body, color: color, cg: cg)
        }
    }
}
#endif
