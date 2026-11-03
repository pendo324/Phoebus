import Foundation

/// Where the comment list scrolls after a comment collapses. Apollo brings
/// the collapsed comment back to the top of the screen when its top has
/// scrolled off, so the thread below it follows directly; a comment still
/// on screen stays where it is. A swipe and a tap collapse through the same
/// rule, as does Collapse Top, whose comment is usually far above the finger.
public enum CollapseReveal {
    /// A comment row's frame in the list's content coordinates.
    public struct Row: Equatable, Sendable {
        public var id: String
        public var minY: Double
        public var maxY: Double

        public init(id: String, minY: Double, maxY: Double) {
            self.id = id
            self.minY = minY
            self.maxY = maxY
        }
    }

    /// The list's scroll geometry: its offset and bounds, the space the bars
    /// cover at either end, and the height of everything it holds.
    public struct Viewport: Equatable, Sendable {
        public var offsetY: Double
        public var boundsHeight: Double
        public var insetTop: Double
        public var insetBottom: Double
        public var contentHeight: Double

        public init(offsetY: Double, boundsHeight: Double, insetTop: Double, insetBottom: Double, contentHeight: Double) {
            self.offsetY = offsetY
            self.boundsHeight = boundsHeight
            self.insetTop = insetTop
            self.insetBottom = insetBottom
            self.contentHeight = contentHeight
        }

        var minOffset: Double { -insetTop }
        var maxOffset: Double { max(minOffset, contentHeight + insetBottom - boundsHeight) }
    }

    /// A comment's place among the list's comment and "more replies" rows, in
    /// the order the list draws them, and how many rows there are: enough to
    /// find its row in the list without the list's own update records, which
    /// a big collapse that reloads the list instead of animating it never
    /// produces. Rows above the comment do not change when it collapses.
    public struct Position: Equatable, Sendable {
        public var index: Int
        public var count: Int

        public init(index: Int, count: Int) {
            self.index = index
            self.count = count
        }
    }

    public static func position(of id: String, roots: [CommentTreeNode], rootMoreStub: MoreStub?) -> Position? {
        var ids = roots.flatMap { $0.visibleFlattenedWithMore() }.map(\.id)
        if let rootMoreStub { ids.append(rootMoreStub.id) }
        return ids.firstIndex(of: id).map { Position(index: $0, count: ids.count) }
    }

    /// Offsets closer than this to where the list already is are not a scroll.
    public static let tolerance = 1.0

    /// The content offset that puts the collapsed comment's top just under the
    /// bars, or nil when the list should stay.
    ///
    /// The first pass (`settling` false) scrolls only a comment whose top is
    /// above the visible area. A far-off row's frame is an estimate until the
    /// list has built the rows on the way to it, so the passes after it
    /// (`settling` true) measure again and correct in either direction until
    /// the row is where it belongs. The target stops at the ends of the
    /// content: a thread too short below the comment to put it at the top
    /// scrolls as far as it can.
    public static func scrollTarget(collapsedID: String, rows: [Row], viewport: Viewport, settling: Bool) -> Double? {
        guard let row = rows.first(where: { $0.id == collapsedID }) else { return nil }
        if !settling {
            let visibleTop = viewport.offsetY + viewport.insetTop
            guard row.minY < visibleTop - 0.5 else { return nil }
        }
        let target = ScrollRestorePolicy.clamped(
            ScrollRestorePolicy.offset(aligningRowTop: row.minY, insetTop: viewport.insetTop),
            min: viewport.minOffset, max: viewport.maxOffset)
        return abs(target - viewport.offsetY) < tolerance ? nil : target
    }
}
