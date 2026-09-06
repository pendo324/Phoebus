import SwiftUI
#if canImport(UIKit)
import UIKit
import CoreGraphics
#endif

/// Renders one of Apollo's own vector glyphs, bundled as PDFs in
/// `Resources/StockIcons`.
///
/// SF Symbols (`arrow.up`, `bubble.right`, `clock`, `ellipsis`) differ visibly
/// from Apollo's shapes in stroke weight, proportions and arrow head. The
/// stock glyphs are `posts-points` (10x12.01), `posts-comments` (14x13),
/// `posts-clock` (13x13), `inline-more-options` (18x4) and
/// `inline-upvote`/`inline-downvote` (14.75x18.19), exactly the MediaBox sizes
/// of the bundled PDFs, so `size` defaults to the intrinsic box.
///
/// `UIImage(contentsOfFile:)` cannot decode a PDF, so the page is
/// rasterised through `CGPDFDocument` + `UIGraphicsImageRenderer` at
/// screen scale and cached per (name, size). The result is marked
/// `.alwaysTemplate` so `foregroundStyle` tints it like a symbol.
public struct StockIcon: View {
    public let name: String
    public let size: CGSize?

    public init(_ name: String, size: CGSize? = nil) {
        self.name = name
        self.size = size
    }

    /// The intrinsic MediaBox sizes, kept as a table so non-UIKit
    /// builds (and the smoke test) can reason about the geometry
    /// without a renderer.
    /// PDF MediaBoxes of the bundled assets.
    public static let intrinsicSizes: [String: CGSize] = [
        "posts-points": CGSize(width: 10, height: 12.01),
        "posts-comments": CGSize(width: 14, height: 13),
        "posts-clock": CGSize(width: 13, height: 13),
        "inline-more-options": CGSize(width: 18, height: 4),
        "inline-upvote": CGSize(width: 14.75, height: 18.19),
        "inline-downvote": CGSize(width: 14.75, height: 18.19),
        // The post-detail quick bar and info row, matching these
        // PDFs' own MediaBoxes exactly.
        "option-upvote": CGSize(width: 19, height: 24),
        "option-downvote": CGSize(width: 19, height: 24),
        "option-save": CGSize(width: 16, height: 21.79822),
        "option-reply": CGSize(width: 24.9635, height: 21.23779),
        "option-share": CGSize(width: 20, height: 26),
        // The upvote-ratio smiley in the post info row.
        "posts-liked": CGSize(width: 13, height: 13),
        // Pinned (stickied) and locked comment markers in the byline.
        "inline-sticky": CGSize(width: 12, height: 18),
        "inline-locked": CGSize(width: 11, height: 14),
        // Apollo's tab bar glyphs.
        "tab-bar-posts": CGSize(width: 20, height: 24),
        "tab-bar-inbox": CGSize(width: 26, height: 17),
        "tab-bar-profile": CGSize(width: 25, height: 25),
        "tab-bar-search": CGSize(width: 23, height: 24),
        "tab-bar-settings": CGSize(width: 26, height: 26),
        // The feed's nav-bar sort button and its menu rows, and the
        // nav-bar "•••" (hollow circles, unlike the row's filled ones).
        "option-sort-best": CGSize(width: 24.51562, height: 24),
        "option-sort-hot": CGSize(width: 21, height: 27),
        "option-sort-new": CGSize(width: 24, height: 24),
        "option-sort-top": CGSize(width: 29, height: 21),
        "option-sort-rising": CGSize(width: 28, height: 24),
        "option-sort-controversial": CGSize(width: 25, height: 22),
        "option-more": CGSize(width: 25, height: 7),
        // The Inbox's Boxes menu and its mark-all-read button.
        "option-inbox": CGSize(width: 23, height: 21),
        "option-unread-box": CGSize(width: 20, height: 20),
        "option-posts": CGSize(width: 21, height: 25),
        "option-comments": CGSize(width: 24, height: 22),
        "option-author": CGSize(width: 24, height: 24),
        "option-mail": CGSize(width: 26, height: 17),
        "option-moderator": CGSize(width: 29, height: 27),
        "option-mark-all-read": CGSize(width: 27, height: 19),
        // A compact self post's placeholder thumbnail.
        "self-post-indicator": CGSize(width: 28, height: 26),
        // The feed's floating Hide Read button.
        "hide-read-posts-button-eye": CGSize(width: 48, height: 48),
        "option-hide-read": CGSize(width: 32, height: 22),
        // The in-app browser's comments button.
        "safari-vc-comments": CGSize(width: 25, height: 23),
        // Row swipe actions.
        "slide-upvote-hollow": CGSize(width: 34, height: 30),
        "slide-unupvote-hollow": CGSize(width: 34, height: 30),
        "slide-downvote-hollow": CGSize(width: 34, height: 30),
        "slide-undownvote-hollow": CGSize(width: 34, height: 30),
        "slide-save-hollow": CGSize(width: 34, height: 30),
        "slide-unsave-hollow": CGSize(width: 34, height: 30),
        "slide-reply-solid": CGSize(width: 34, height: 30),
        "slide-share-hollow": CGSize(width: 34, height: 30),
        "slide-hide-hollow": CGSize(width: 34, height: 30),
        "slide-collapse-hollow": CGSize(width: 34, height: 30),
        "slide-read-hollow": CGSize(width: 34, height: 30),
        "slide-unread-hollow": CGSize(width: 34, height: 30),
        // The Subreddits list's Home / Popular / All / Moderator
        // badges, full colour, drawn at 28pt.
        "orb-home": CGSize(width: 38, height: 38),
        "orb-popular": CGSize(width: 38, height: 38),
        "orb-all": CGSize(width: 38, height: 38),
        "orb-moderator": CGSize(width: 38, height: 38),
    ]

    /// Full-colour artwork rather than a tintable glyph.
    static func isColored(_ name: String) -> Bool { name.hasPrefix("orb-") }

    public static func intrinsicSize(_ name: String) -> CGSize {
        intrinsicSizes[name] ?? CGSize(width: 16, height: 16)
    }

    private var resolvedSize: CGSize { size ?? StockIcon.intrinsicSize(name) }

    public var body: some View {
        #if canImport(UIKit)
        if let image = StockIcon.image(named: name, size: resolvedSize) {
            Image(uiImage: image)
                .renderingMode(StockIcon.isColored(name) ? .original : .template)
                .resizable()
                .frame(width: resolvedSize.width, height: resolvedSize.height)
                .accessibilityHidden(true)
        } else {
            // Missing asset must not collapse the row's layout, so the
            // slot keeps its measured size.
            Color.clear
                .frame(width: resolvedSize.width, height: resolvedSize.height)
        }
        #else
        Color.clear
            .frame(width: resolvedSize.width, height: resolvedSize.height)
        #endif
    }

    /// Whether `name` is one of the bundled glyphs rather than an SF
    /// Symbol name.
    public static func isBundled(_ name: String) -> Bool {
        intrinsicSizes[name] != nil
    }

    #if canImport(UIKit)
    /// A bundled glyph at its own size, else the SF Symbol `name`: for
    /// UIKit controls (bar buttons, `UIMenu` rows) that take an image.
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
        let key = CacheKey(name: name, width: size.width, height: size.height)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "pdf", subdirectory: "StockIcons")
                ?? Bundle.module.url(forResource: name, withExtension: "pdf"),
              let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: size.width / box.width, y: -size.height / box.height)
            cg.drawPDFPage(page)
        }.withRenderingMode(isColored(name) ? .alwaysOriginal : .alwaysTemplate)
        cache[key] = rendered
        return rendered
    }
    #endif
}

/// An icon by name: a bundled Apollo glyph (`StockIcon`) when there is
/// one, else the SF Symbol of that name.
struct ApolloIconImage: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        if StockIcon.isBundled(name) {
            StockIcon(name)
        } else {
            Image(systemName: name)
        }
    }
}
