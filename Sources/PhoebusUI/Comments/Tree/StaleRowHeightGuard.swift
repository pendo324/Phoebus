import SwiftUI
#if canImport(UIKit)
import UIKit

/// SwiftUI's `List` sizes a comment's cell when it is built and trusts that size;
/// a row whose content grows afterwards (a link card, an award, wrapped text) can
/// leave its cell short, or its neighbours where they were. While the list is at
/// rest this asks each shown cell what its content now needs, and has the layout
/// measure again those that are short or overlapped.
private final class StaleRowHeightGuardView: UIView {
    private weak var list: UICollectionView?
    private var link: CADisplayLink?
    private var restingTicks = 0
    private var lastOffset = CGFloat.nan
    /// How many times each cell (by its current height) has been re-measured.
    private var attempts: [ObjectIdentifier: (height: CGFloat, count: Int)] = [:]
    private static let maxAttempts = 3

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 10
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func findList() -> UICollectionView? {
        var ancestor = superview
        while let current = ancestor {
            if let found = UIKitTree.firstDescendant(of: UICollectionView.self, in: current) { return found }
            ancestor = current.superview
        }
        return nil
    }

    @objc private func tick() {
        if list == nil { list = findList() }
        guard let list, list.window != nil else { return }
        // Only once the list has been still for a few ticks: a scroll builds and sizes cells itself.
        let offset = list.contentOffset.y
        if offset != lastOffset || list.isDragging || list.isDecelerating {
            lastOffset = offset
            restingTicks = 0
            return
        }
        restingTicks += 1
        guard restingTicks == 3 || restingTicks % 20 == 0 else { return }

        let shown = list.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        var stale: [UICollectionViewCell] = []
        for (index, cell) in shown.enumerated() {
            let overlapped = index + 1 < shown.count && cell.frame.maxY > shown[index + 1].frame.minY + 1
            let needed = cell.systemLayoutSizeFitting(
                CGSize(width: cell.bounds.width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel).height
            let short = needed > cell.bounds.height + 1
            guard overlapped || short else { continue }
            let key = ObjectIdentifier(cell)
            var record = attempts[key] ?? (cell.bounds.height, 0)
            if record.height != cell.bounds.height { record = (cell.bounds.height, 0) }
            guard record.count < Self.maxAttempts else { continue }
            record.count += 1
            attempts[key] = record
            stale.append(cell)
        }
        guard !stale.isEmpty else { return }
        let context = UICollectionViewLayoutInvalidationContext()
        context.invalidateItems(at: stale.compactMap { list.indexPath(for: $0) })
        list.collectionViewLayout.invalidateLayout(with: context)
    }
}

private struct StaleRowHeightGuard: UIViewRepresentable {
    func makeUIView(context: Context) -> StaleRowHeightGuardView {
        let view = StaleRowHeightGuardView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: StaleRowHeightGuardView, context: Context) {}
}

extension View {
    /// See `StaleRowHeightGuardView`; applied to a comment list.
    func guardsStaleRowHeights() -> some View {
        background(StaleRowHeightGuard())
    }
}
#else
extension View {
    func guardsStaleRowHeights() -> some View { self }
}
#endif
