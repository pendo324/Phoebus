import SwiftUI
#if canImport(UIKit)
import UIKit
import ObjectiveC

/// Apollo's comment collapse animation.
///
/// Apollo flips the comment's collapsed flag, then commits one animated
/// batch update in which the toggled row is reloaded (a new cell for the
/// collapsed header) and its visible descendants are deleted (expanding
/// inserts them):
///
/// - collapse: the old expanded cell stays put and fades out while the
///   new collapsed header rises into place from below with the rows
///   after it, and the replies fade out while drifting down;
/// - expand: the replies fan out from under the header, starting stacked
///   at its top and sliding down to their places, while the old collapsed
///   header drifts down and fades.
///
/// When the batch finishes, a comment whose top is above the visible
/// area is scrolled back to the top edge so the collapsed header stays
/// on screen.
///
/// SwiftUI's `List` is a `UICollectionView` that exposes neither the row
/// animations nor the batch completion, so this steps in at the layout's
/// appearing/disappearing attributes and gives the toggled row a new
/// identity for the change (`rowGeneration`) so it is reloaded like
/// Apollo's instead of resized in place.
@MainActor
enum CommentCollapseAnimation {
    /// UIKit's row-animation length.
    static let duration: TimeInterval = 0.3

    private static var activeUntil: CFAbsoluteTime = 0
    static var isActive: Bool { CFAbsoluteTimeGetCurrent() < activeUntil }

    /// Runs `change` as an animated collapse/expand. `revealsRow` is false
    /// for bulk changes ("Collapse Child Comments"), which have no single
    /// comment to bring back on screen.
    static func perform(revealsRow: Bool = true, _ change: () -> Void) {
        let list = commentsList()
        if let list { install(on: type(of: list.collectionViewLayout)) }
        activeUntil = CFAbsoluteTimeGetCurrent() + duration + 0.3
        pending = Update()
        heightsBefore = list.map(visibleHeights) ?? [:]
        listBefore = list
        withAnimation(.easeInOut(duration: duration)) { change() }
        DispatchQueue.main.async {
            riseHeader()
            fanOutReplies()
        }
        guard revealsRow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { revealToggledRow() }
    }

    // MARK: - Batch bookkeeping

    private struct Update {
        weak var collectionView: UICollectionView?
        var deleted: [IndexPath] = []
        var inserted: [IndexPath] = []
        /// The toggled comment: its old cell (pre-update) and its reloaded
        /// cell (post-update).
        var toggledOld: IndexPath?
        var toggledRow: IndexPath?
        var isCollapse = true
        /// Height of the rows the collapse removes (old cell + replies)
        /// that were on screen.
        var removedHeight: CGFloat = 0
        /// How far the new collapsed header starts below its place.
        var headerRise: CGFloat = 0
    }

    private static var pending = Update()

    /// Visible row heights before the change, to find the toggled row
    /// when no rows are inserted or deleted (a comment with no replies
    /// only changes height).
    private static var heightsBefore: [IndexPath: CGFloat] = [:]
    private static weak var listBefore: UICollectionView?

    private static func visibleHeights(_ list: UICollectionView) -> [IndexPath: CGFloat] {
        var heights: [IndexPath: CGFloat] = [:]
        for path in list.indexPathsForVisibleItems {
            heights[path] = list.layoutAttributesForItem(at: path)?.frame.height
        }
        return heights
    }

    // MARK: - Layout hooks

    private static var installed: Set<ObjectIdentifier> = []

    private typealias Prepare = @convention(c) (UICollectionViewLayout, Selector, NSArray) -> Void
    private typealias Attributes = @convention(c) (UICollectionViewLayout, Selector, NSIndexPath) -> UICollectionViewLayoutAttributes?

    private static func install(on cls: AnyClass) {
        guard installed.insert(ObjectIdentifier(cls)).inserted else { return }

        let prepareSel = #selector(UICollectionViewLayout.prepare(forCollectionViewUpdates:))
        if let method = class_getInstanceMethod(cls, prepareSel) {
            let original = unsafeBitCast(method_getImplementation(method), to: Prepare.self)
            let block: @convention(block) (UICollectionViewLayout, NSArray) -> Void = { layout, items in
                original(layout, prepareSel, items)
                MainActor.assumeIsolated { record(items, layout: layout) }
            }
            replace(cls, prepareSel, method, block)
        }

        for (selector, appearing) in [
            (#selector(UICollectionViewLayout.finalLayoutAttributesForDisappearingItem(at:)), false),
            (#selector(UICollectionViewLayout.initialLayoutAttributesForAppearingItem(at:)), true),
        ] {
            guard let method = class_getInstanceMethod(cls, selector) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: Attributes.self)
            let block: @convention(block) (UICollectionViewLayout, NSIndexPath) -> UICollectionViewLayoutAttributes? = { layout, path in
                let attributes = original(layout, selector, path)
                return MainActor.assumeIsolated {
                    adjust(attributes, at: path as IndexPath, appearing: appearing, layout: layout, original: { original(layout, selector, $0 as NSIndexPath) })
                }
            }
            replace(cls, selector, method, block)
        }
    }

    private static func replace(_ cls: AnyClass, _ selector: Selector, _ method: Method, _ block: Any) {
        let imp = imp_implementationWithBlock(block)
        // Added on the class itself when it only inherits the method, so
        // the base class's other subclasses are untouched.
        if !class_addMethod(cls, selector, imp, method_getTypeEncoding(method)) {
            method_setImplementation(method, imp)
        }
    }

    private static func record(_ items: NSArray, layout: UICollectionViewLayout) {
        guard isActive, pending.collectionView == nil else { return }
        var update = Update()
        update.collectionView = layout.collectionView
        for case let item as UICollectionViewUpdateItem in items {
            switch item.updateAction {
            case .delete: if let path = item.indexPathBeforeUpdate, path.count == 2 { update.deleted.append(path) }
            case .insert: if let path = item.indexPathAfterUpdate, path.count == 2 { update.inserted.append(path) }
            default: break
            }
        }
        update.deleted.sort()
        update.inserted.sort()
        update.toggledOld = update.deleted.first
        update.toggledRow = update.inserted.first
        update.isCollapse = update.deleted.count >= update.inserted.count
        if let list = layout.collectionView {
            // Only what is on screen: rows past the bottom are capped by
            // `capTravel` anyway.
            for path in update.deleted {
                guard let cell = list.cellForItem(at: path) else { break }
                update.removedHeight += cell.frame.height
            }
        }
        pending = update
    }

    private static func adjust(_ attributes: UICollectionViewLayoutAttributes?, at path: IndexPath, appearing: Bool,
                               layout: UICollectionViewLayout,
                               original: (IndexPath) -> UICollectionViewLayoutAttributes?) -> UICollectionViewLayoutAttributes? {
        guard isActive, pending.collectionView === layout.collectionView,
              let attributes, attributes.representedElementCategory == .cell else { return attributes }
        let members = appearing ? pending.inserted : pending.deleted
        guard members.contains(path) else {
            return capTravel(attributes, at: path, appearing: appearing, layout: layout)
        }
        guard let copy = attributes.copy() as? UICollectionViewLayoutAttributes else { return attributes }
        let isToggled = path == (appearing ? pending.toggledRow : pending.toggledOld)
        switch (pending.isCollapse, appearing, isToggled) {
        case (true, true, true):
            // The collapsed header rises into place from where the first
            // surviving row starts, drawn over the fading old cell. The
            // layout ignores an appearing cell's start frame when the row
            // keeps its index, so the rise is also driven on the cell
            // itself once it exists (`riseHeader`).
            let shift = collapseShift(header: copy.frame, layout: layout)
            copy.frame.origin.y += shift
            copy.alpha = 1
            copy.zIndex = 2
            pending.headerRise = shift
        case (true, false, true):
            // The old expanded cell stays put and fades out.
            copy.alpha = 0
            copy.zIndex = 1
        case (true, false, false):
            // Replies fade out while drifting down, behind everything.
            copy.frame.origin.y += copy.frame.height
            copy.alpha = 0
            copy.zIndex = -1
        case (false, true, false):
            // Replies fan out from under the header down to their places,
            // fully drawn, the way Apollo's opaque cells slide out.
            if let row = pending.toggledRow, let header = layout.layoutAttributesForItem(at: row) {
                copy.frame.origin.y = header.frame.minY
            }
            copy.alpha = 1
            copy.zIndex = -1
        case (false, false, true):
            // The old collapsed header drifts down and fades.
            copy.frame.origin.y += max(copy.frame.height, 60)
            copy.alpha = 0
            copy.zIndex = 0
        default:
            // The expanded comment appears where it lands, over its
            // replies as they fan out.
            copy.alpha = 1
            copy.zIndex = 2
        }
        return copy
    }

    /// How far below its final place the collapsed header starts: the
    /// height the collapse removes, capped like the rows after it
    /// (`capTravel`) so the two stay together.
    private static func collapseShift(header: CGRect, layout: UICollectionViewLayout) -> CGFloat {
        guard let list = layout.collectionView else { return 0 }
        let cap = max(0, list.bounds.maxY - header.maxY)
        return max(0, min(pending.removedHeight - header.height, cap))
    }

    /// The rows after the toggled comment move by the height of the whole
    /// run, which for a top-level thread is thousands of points. Travel is
    /// capped at the visible space below the comment so every collapse moves
    /// the screen's rows the way a short nested one does.
    private static func capTravel(_ attributes: UICollectionViewLayoutAttributes, at path: IndexPath, appearing: Bool,
                                  layout: UICollectionViewLayout) -> UICollectionViewLayoutAttributes {
        guard let list = layout.collectionView, let row = pending.toggledRow,
              let header = layout.layoutAttributesForItem(at: row) else { return attributes }
        let cap = max(0, list.bounds.maxY - header.frame.maxY)
        let start: CGFloat
        let end: CGFloat
        if appearing {
            guard let final = layout.layoutAttributesForItem(at: path) else { return attributes }
            start = attributes.frame.minY
            end = final.frame.minY
        } else {
            guard let cell = list.cellForItem(at: path) else { return attributes }
            start = cell.frame.minY
            end = attributes.frame.minY
        }
        let travel = start - end
        guard abs(travel) > cap, let copy = attributes.copy() as? UICollectionViewLayoutAttributes else { return attributes }
        let capped = travel > 0 ? cap : -cap
        copy.frame.origin.y = appearing ? end + capped : start - capped
        return copy
    }

    /// Slides the new collapsed header up from `headerRise` below its
    /// place, on top of the fading old cell, with the rows below.
    private static func riseHeader() {
        guard pending.isCollapse, pending.headerRise > 0.5,
              let list = pending.collectionView, let row = pending.toggledRow,
              let cell = list.cellForItem(at: row) else { return }
        // An additive layer animation: the collection view rewrites the cell's
        // frame and transform whenever it applies attributes, which cancels a
        // UIView animation of either.
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = pending.headerRise
        rise.toValue = 0
        rise.duration = duration
        rise.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rise.isAdditive = true
        cell.layer.add(rise, forKey: "apolloCollapseRise")
        cell.layer.zPosition = 2
        // Apollo's cells are opaque, so the rising header hides the old
        // cell fading beneath it. List rows are transparent over the page,
        // so paint the page colour behind this one for the rise.
        let previous = cell.layer.backgroundColor
        cell.layer.backgroundColor = pageColor(behind: list)?.cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            cell.layer.zPosition = 0
            cell.layer.backgroundColor = previous
        }
    }

    /// Expand: the replies fan out from under the header, like a deck,
    /// and the rows after them slide down to make room.
    ///
    /// Driven on the cells after the layout settles: inserted rows are
    /// self-sized right after the batch, and that second pass sets their
    /// final frames without animation, so the layout's own start frames
    /// never show. List rows are transparent, so each moving row gets the
    /// page colour behind it for the flight; otherwise the stacked
    /// replies show through one another.
    private static func fanOutReplies() {
        guard !pending.isCollapse, let list = pending.collectionView,
              let row = pending.toggledRow else { return }
        list.layoutIfNeeded()
        guard let header = list.layoutAttributesForItem(at: row) else { return }
        let inserted = Set(pending.inserted)
        let lastInserted = pending.inserted.last ?? row
        let collapsedHeight = pending.toggledOld.flatMap { heightsBefore[$0] } ?? header.frame.height
        let background = pageColor(behind: list)?.cgColor
        let cap = max(0, list.bounds.maxY - header.frame.maxY)
        var moved: [(CALayer, CGColor?)] = []
        for path in list.indexPathsForVisibleItems.sorted() where path > row {
            guard let cell = list.cellForItem(at: path) else { continue }
            let offset: CGFloat
            if inserted.contains(path) {
                // Stacked at the header's top, sliding to its place.
                offset = max(-cap, header.frame.minY - cell.frame.minY)
            } else if path > lastInserted {
                // Where it sat under the collapsed header before.
                guard let lastFrame = list.layoutAttributesForItem(at: lastInserted)?.frame else { continue }
                let block = lastFrame.maxY - header.frame.minY - collapsedHeight
                offset = -min(block, cap)
            } else { continue }
            guard offset < -0.5 else { continue }
            for key in cell.layer.animationKeys() ?? [] where key.hasPrefix("position") || key.hasPrefix("bounds") {
                cell.layer.removeAnimation(forKey: key)
            }
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = offset
            slide.toValue = 0
            slide.duration = duration
            slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            slide.isAdditive = true
            cell.layer.add(slide, forKey: "apolloExpandFan")
            // Earlier replies on top, all under the header.
            cell.layer.zPosition = inserted.contains(path) ? -1 - CGFloat(path.item - row.item) * 0.001 : -2
            moved.append((cell.layer, cell.layer.backgroundColor))
            cell.layer.backgroundColor = background
        }
        guard !moved.isEmpty, let headerCell = list.cellForItem(at: row) else { return }
        let headerBackground = headerCell.layer.backgroundColor
        headerCell.layer.backgroundColor = background
        headerCell.layer.zPosition = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            for (layer, color) in moved {
                layer.zPosition = 0
                layer.backgroundColor = color
            }
            headerCell.layer.zPosition = 0
            headerCell.layer.backgroundColor = headerBackground
        }
    }

    /// The first opaque background at or behind the list, else the stock
    /// page surface.
    private static func pageColor(behind list: UICollectionView) -> UIColor? {
        var view: UIView? = list
        while let current = view {
            if let color = current.backgroundColor, color.cgColor.alpha > 0.99 { return color }
            view = current.superview
        }
        return RowHighlight.surface
    }

    // MARK: - Reveal

    /// Apollo's completion: if the toggled comment's top is above the
    /// visible area, scroll it down to the top edge.
    private static func revealToggledRow() {
        defer { pending = Update(); heightsBefore = [:] }
        guard let collectionView = pending.collectionView ?? listBefore,
              let row = pending.toggledRow ?? resizedRow(in: collectionView),
              row.section < collectionView.numberOfSections,
              row.item < collectionView.numberOfItems(inSection: row.section),
              let frame = collectionView.layoutAttributesForItem(at: row)?.frame else { return }
        let inset = collectionView.adjustedContentInset.top
        let visibleTop = collectionView.contentOffset.y + inset
        guard frame.minY < visibleTop - 0.5 else { return }
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: frame.minY - inset), animated: true)
    }

    /// The first visible row whose height changed.
    private static func resizedRow(in list: UICollectionView) -> IndexPath? {
        heightsBefore.keys.sorted().first { path in
            guard path.section < list.numberOfSections,
                  path.item < list.numberOfItems(inSection: path.section),
                  let now = list.layoutAttributesForItem(at: path)?.frame.height,
                  let before = heightsBefore[path] else { return false }
            return abs(now - before) > 0.5
        }
    }

    /// The comments list on screen: the largest visible collection view.
    private static func commentsList() -> UICollectionView? {
        guard let window = UIKitTree.keyWindow else { return nil }
        return UIKitTree.scrollViews(in: window)
            .compactMap { $0 as? UICollectionView }
            .filter { $0.window != nil && !$0.isHidden && $0.alpha > 0.01 }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }
}
#else
@MainActor
enum CommentCollapseAnimation {
    static func perform(revealsRow: Bool = true, _ change: () -> Void) {
        withAnimation(.easeInOut(duration: 0.3)) { change() }
    }
}
#endif
