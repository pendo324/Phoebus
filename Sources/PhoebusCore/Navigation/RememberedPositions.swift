import Foundation

/// A saved scroll position for one list, keyed by whatever the list shows
/// (a thread's post id, a feed's path).
public protocol RememberedPosition: Codable, Sendable, Equatable {
    var key: String { get }
}

/// The most recently saved positions, newest first, capped by evicting the
/// least recently saved.
public struct RememberedPositions<Entry: RememberedPosition>: Codable, Sendable, Equatable {
    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public func entry(for key: String) -> Entry? {
        entries.first { $0.key == key }
    }

    /// `entry` moved to the front, replacing any older one for its key.
    public func recording(_ entry: Entry, capacity: Int) -> Self {
        var updated = entries.filter { $0.key != entry.key }
        updated.insert(entry, at: 0)
        return Self(entries: Array(updated.prefix(max(0, capacity))))
    }

    public func removing(key: String) -> Self {
        Self(entries: entries.filter { $0.key != key })
    }
}

/// The visible part of a scrolling list, in its content coordinates: below
/// the navigation bar and any pinned bars, above the bottom safe area.
public struct ListViewport: Sendable, Equatable {
    public var top: Double
    public var bottom: Double

    public init(top: Double, bottom: Double) {
        self.top = top
        self.bottom = bottom
    }

    /// A scroll view's visible area: its bounds start at the content
    /// offset, and the adjusted insets are what the bars cover.
    public static func visibleArea(contentOffsetY: Double, boundsHeight: Double,
                                   insetTop: Double, insetBottom: Double) -> ListViewport {
        ListViewport(top: contentOffsetY + insetTop, bottom: contentOffsetY + boundsHeight - insetBottom)
    }
}

/// Which row a list is showing at its top. A `List` realizes rows before
/// they scroll in and keeps some alive after they scroll out, so
/// `onAppear`/`onDisappear` overstate what is on screen; the rows' cell
/// frames are checked against the viewport instead, and reading order decides.
public enum TopVisibleRowPolicy {
    /// How much of a row must show to count: this much, or half of a
    /// shorter row, so a sliver left under the navigation bar doesn't.
    public static let minimumVisibleHeight = 44.0

    public static func isVisible(minY: Double, maxY: Double, in viewport: ListViewport) -> Bool {
        guard viewport.bottom > viewport.top, maxY > minY else { return false }
        let shown = min(maxY, viewport.bottom) - max(minY, viewport.top)
        return shown >= min(minimumVisibleHeight, (maxY - minY) / 2)
    }

    public static func topmost(order: [String], onScreen: Set<String>) -> String? {
        guard !onScreen.isEmpty else { return nil }
        return order.first(where: onScreen.contains)
    }
}

/// Stepping a list to a row its own `scrollTo` cannot reach: a long jump
/// lands on estimated heights, short of the row, and then reports arrival.
public enum ScrollRestorePolicy {
    public enum Step: Equatable, Sendable { case up, down }

    /// Each step moves this much of the visible height, so the rows passed
    /// over are realized and measured.
    public static let stepFraction = 0.8
    public static let maxSteps = 40

    /// Which way the unrealized target lies, from the reading-order indices
    /// of the rows on screen; nil when it should already be among them, or
    /// when no tracked row is on screen at all (the list was lost track of).
    public static func step(targetIndex: Int, realizedIndices: [Int]) -> Step? {
        guard let lowest = realizedIndices.min(), let highest = realizedIndices.max() else { return nil }
        if targetIndex > highest { return .down }
        if targetIndex < lowest { return .up }
        return nil
    }

    /// The content offset that puts a row's top edge just under the bars.
    public static func offset(aligningRowTop rowTop: Double, insetTop: Double) -> Double {
        rowTop - insetTop
    }

    public static func clamped(_ offset: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(offset, lower), upper)
    }
}
