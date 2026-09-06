import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Lays out a post's title and link-flair capsule as one run, as Apollo
/// does: the capsule follows the last title glyph when it fits, else wraps
/// under it.
///
/// SwiftUI cannot report a `Text`'s last-line width, so the title is
/// measured with TextKit using the same `UIFont` and the capsule is placed
/// from that. The caller's `Text` still draws the title.
struct TitleFlairLayout: Layout {
    /// The exact string the title `Text` draws, for measurement.
    let titleString: String
    let fontSize: CGFloat
    let bold: Bool
    /// Gap between the last title glyph and the capsule, 3.7pt.
    var gap: CGFloat = 4
    var lineSpacing: CGFloat = 3

    struct Cache {
        var width: CGFloat = -1
        /// The string the lines were measured for. Keyed alongside width because
        /// title translation can change the text in place.
        var text: String = ""
        var lines: [CGRect] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func lineRects(width: CGFloat, cache: inout Cache) -> [CGRect] {
        if cache.width == width, cache.text == titleString { return cache.lines }
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular)
        // `.standard` line breaking, as `Text` and UILabel use, so TextKit and
        // SwiftUI agree on where lines break.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakStrategy = .standard
        let storage = NSTextStorage(string: titleString, attributes: [.font: font, .paragraphStyle: paragraph])
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var rects: [CGRect] = []
        var index = 0
        let count = manager.numberOfGlyphs
        while index < count {
            var range = NSRange()
            let used = manager.lineFragmentUsedRect(forGlyphAt: index, effectiveRange: &range)
            rects.append(used)
            index = NSMaxRange(range)
        }
        cache = Cache(width: width, text: titleString, lines: rects)
        return rects
        #else
        return []
        #endif
    }

    /// The flair's natural size, capped at the row width so a long flair
    /// truncates instead of running off the edge.
    private static func flairSize(_ flair: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = flair.sizeThatFits(.unspecified)
        guard ideal.width > width else { return ideal }
        return flair.sizeThatFits(ProposedViewSize(width: width, height: ideal.height))
    }

    /// Whether the flair fits after the title's last line. Only trusted when
    /// TextKit's line count matches the rendered title's; otherwise the flair
    /// goes on its own line.
    private func fitsInline(lines: [CGRect], titleHeight: CGFloat, flairWidth: CGFloat, width: CGFloat) -> Bool {
        guard let last = lines.last, last.maxX + gap + flairWidth <= width else { return false }
        let measured = lines.reduce(0) { $0 + $1.height }
        return abs(measured - titleHeight) <= last.height * 0.5
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let title = subviews.first else { return .zero }
        // Min/max probes (0 or infinity) must not reach TextKit or be echoed back
        // as our width: iOS 17's layout engine re-proposes forever and pins the
        // CPU.
        guard let proposed = proposal.width, proposed.isFinite, proposed > 0 else {
            let title = title.sizeThatFits(proposal)
            guard subviews.count > 1 else { return title }
            let flair = subviews[1].sizeThatFits(.unspecified)
            return CGSize(width: title.width, height: title.height + lineSpacing + flair.height)
        }
        let width = proposed
        let titleSize = title.sizeThatFits(ProposedViewSize(width: width, height: nil))
        guard subviews.count > 1 else { return titleSize }
        let flair = Self.flairSize(subviews[1], width: width)
        let lines = lineRects(width: width, cache: &cache)
        let last = lines.last ?? CGRect(x: 0, y: 0, width: titleSize.width, height: titleSize.height)
        if fitsInline(lines: lines, titleHeight: titleSize.height, flairWidth: flair.width, width: width) {
            let lastLineTop = titleSize.height - last.height
            let height = max(titleSize.height, lastLineTop + flair.height)
            return CGSize(width: width, height: height)
        }
        return CGSize(width: width, height: titleSize.height + lineSpacing + flair.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let width = bounds.width
        guard let title = subviews.first, width.isFinite, width > 0 else { return }
        let titleSize = title.sizeThatFits(ProposedViewSize(width: width, height: nil))
        title.place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: titleSize.height))
        guard subviews.count > 1 else { return }
        let flair = Self.flairSize(subviews[1], width: width)
        let lines = lineRects(width: width, cache: &cache)
        let last = lines.last ?? CGRect(x: 0, y: 0, width: titleSize.width, height: titleSize.height)
        if fitsInline(lines: lines, titleHeight: titleSize.height, flairWidth: flair.width, width: width) {
            let lastLineTop = titleSize.height - last.height
            let y = bounds.minY + lastLineTop + (last.height - flair.height) / 2
            subviews[1].place(at: CGPoint(x: bounds.minX + last.maxX + gap, y: y), proposal: ProposedViewSize(flair))
        } else {
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + titleSize.height + lineSpacing), proposal: ProposedViewSize(flair))
        }
    }
}
