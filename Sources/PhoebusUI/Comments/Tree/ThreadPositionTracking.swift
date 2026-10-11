import SwiftUI
import UIKit
import PhoebusCore

/// "Remember Thread Position" reads the comment list from UIKit: SwiftUI's
/// `List` realizes rows early, keeps some alive off screen, and its
/// `scrollTo` trusts estimated heights, so neither row callbacks nor
/// `scrollTo` say where the reader really is. Each tracked row carries a
/// hidden marker view; the list's visible cells say which rows are on screen.
@MainActor
final class ThreadScrollTracker: NSObject {
    /// The comment list, found from a marker's own superviews so it is the
    /// list the rows are in, not some other scroll view on screen.
    private weak var scrollView: UIScrollView?
    var onDragBegan: (() -> Void)?
    private let markers = NSHashTable<ThreadRowMarkerView>.weakObjects()

    fileprivate func register(_ marker: ThreadRowMarkerView) {
        markers.add(marker)
    }

    fileprivate func markerMovedToWindow(_ marker: ThreadRowMarkerView) {
        guard marker.window != nil, scrollView?.window == nil else { return }
        var view = marker.superview
        while let current = view, !(current is UICollectionView || current is UITableView) {
            view = current.superview
        }
        guard let list = view as? UIScrollView else { return }
        scrollView?.panGestureRecognizer.removeTarget(self, action: nil)
        // A target on the list's own pan recognizer, so the scroll view's
        // delegate (SwiftUI's, or the scroll-to-top proxy) is left alone.
        list.panGestureRecognizer.addTarget(self, action: #selector(panned(_:)))
        scrollView = list
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .began { onDragBegan?() }
    }

    /// The cells the list is showing. Off-screen cells it keeps alive or
    /// holds for reuse (hidden, with stale rows and positions) are not in it.
    private func shownCells(of scrollView: UIScrollView) -> [UIView] {
        let cells: [UIView] = (scrollView as? UICollectionView)?.visibleCells
            ?? (scrollView as? UITableView)?.visibleCells ?? []
        return cells.filter { !$0.isHidden && $0.alpha > 0 }
    }

    /// Each shown row's cell frame in content coordinates (a scroll view's
    /// bounds start at its content offset), by row id. No window check:
    /// leaving saves from `onDisappear`, after the list left the window.
    private func shownCellFrames(in scrollView: UIScrollView) -> [String: CGRect] {
        let cells = shownCells(of: scrollView)
        let cellIDs = Set(cells.map(ObjectIdentifier.init))
        var frames: [String: CGRect] = [:]
        for marker in markers.allObjects {
            guard let id = marker.rowID,
                  let cell = marker.enclosingView(in: cellIDs) else { continue }
            frames[id] = cell.convert(cell.bounds, to: scrollView)
        }
        return frames
    }

    private func visibleArea(of scrollView: UIScrollView) -> ListViewport {
        ListViewport.visibleArea(contentOffsetY: Double(scrollView.contentOffset.y),
                                 boundsHeight: Double(scrollView.bounds.height),
                                 insetTop: Double(scrollView.adjustedContentInset.top),
                                 insetBottom: Double(scrollView.adjustedContentInset.bottom))
    }

    /// Row ids really on screen.
    func visibleRowIDs() -> Set<String> {
        guard let scrollView else { return [] }
        let area = visibleArea(of: scrollView)
        return Set(shownCellFrames(in: scrollView).filter { _, frame in
            TopVisibleRowPolicy.isVisible(minY: Double(frame.minY), maxY: Double(frame.maxY), in: area)
        }.keys)
    }

    /// Brings `target` to the top of the list. A long `scrollTo` lands short
    /// on estimated heights and then believes it has arrived, so this steps
    /// the offset toward the target until its row is shown, then aligns
    /// that row's cell under the bars. Returns false when it gave up (no
    /// list, out of steps, or the reader dragged).
    func scroll(toRow target: String, order: [String], shouldContinue: () -> Bool) async -> Bool {
        guard let targetIndex = order.firstIndex(of: target) else { return false }
        let indexByID = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        for _ in 0..<ScrollRestorePolicy.maxSteps {
            // Two frames: the cells for the new offset get built and sized.
            try? await Task.sleep(nanoseconds: 33_000_000)
            guard shouldContinue() else { return false }
            // The rows may not be in the window yet on the first pass.
            guard let scrollView else { continue }
            scrollView.layoutIfNeeded()
            let frames = shownCellFrames(in: scrollView)
            let inset = scrollView.adjustedContentInset
            let minOffset = Double(-inset.top)
            let maxOffset = max(minOffset, Double(scrollView.contentSize.height + inset.bottom - scrollView.bounds.height))
            let current = Double(scrollView.contentOffset.y)
            let next: Double
            if let frame = frames[target] {
                next = ScrollRestorePolicy.clamped(
                    ScrollRestorePolicy.offset(aligningRowTop: Double(frame.minY), insetTop: Double(inset.top)),
                    min: minOffset, max: maxOffset)
                if abs(next - current) < 1 { return true }
            } else {
                // The header has no index, so a screen of header alone steps down.
                let shown = frames.keys.map { indexByID[$0] ?? -1 }
                guard let step = ScrollRestorePolicy.step(targetIndex: targetIndex, realizedIndices: shown) else { return false }
                let distance = Double(scrollView.bounds.height - inset.top - inset.bottom) * ScrollRestorePolicy.stepFraction
                next = ScrollRestorePolicy.clamped(step == .down ? current + distance : current - distance,
                                                   min: minOffset, max: maxOffset)
                // Against the end of the content and still not shown.
                if abs(next - current) < 1 { return false }
            }
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: next), animated: false)
        }
        return false
    }
}

extension View {
    /// Marks this row for `ThreadScrollTracker`.
    @ViewBuilder
    func threadRowMarker(_ rowID: String, tracker: ThreadScrollTracker, enabled: Bool) -> some View {
        if enabled {
            background(ThreadRowMarker(rowID: rowID, tracker: tracker).accessibilityHidden(true))
        } else {
            self
        }
    }

    /// See `ThreadPositionBackToTop`.
    func threadPositionBackToTop(isPresented: Binding<Bool>, accessibilityIdentifier: String,
                                 onTap: @escaping () -> Void) -> some View {
        modifier(ThreadPositionBackToTop(isPresented: isPresented,
                                         accessibilityIdentifier: accessibilityIdentifier, onTap: onTap))
    }
}

final class ThreadRowMarkerView: UIView {
    var rowID: String?
    weak var tracker: ThreadScrollTracker?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        tracker?.markerMovedToWindow(self)
    }

    /// The nearest view above this marker among `views`: its row's cell,
    /// however deep SwiftUI nests the row inside it.
    func enclosingView(in views: Set<ObjectIdentifier>) -> UIView? {
        var view = superview
        while let current = view {
            if views.contains(ObjectIdentifier(current)) { return current }
            view = current.superview
        }
        return nil
    }
}

private struct ThreadRowMarker: UIViewRepresentable {
    let rowID: String
    let tracker: ThreadScrollTracker

    func makeUIView(context: Context) -> ThreadRowMarkerView {
        let marker = ThreadRowMarkerView(frame: .zero)
        marker.isUserInteractionEnabled = false
        marker.isHidden = true
        marker.tracker = tracker
        tracker.register(marker)
        return marker
    }

    func updateUIView(_ marker: ThreadRowMarkerView, context: Context) {
        marker.rowID = rowID
    }
}

/// "Remember Thread Position": after a reopened thread lands on the saved
/// comment, a pill offers the way back to the top for a few seconds.
struct ThreadPositionBackToTop: ViewModifier {
    @Binding var isPresented: Bool
    let accessibilityIdentifier: String
    let onTap: () -> Void

    func body(content: Content) -> some View {
        // A zero-height inset pins the pill just under the navigation bar
        // (and any pinned bar) without changing the list's insets, which
        // would shift the restored rows.
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .overlay(alignment: .top) {
                        if isPresented { pill }
                    }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
    }

    private var pill: some View {
        Button {
            isPresented = false
            onTap()
        } label: {
            Label("Back to Top", systemImage: "chevron.up")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.apolloAccent))
                .foregroundStyle(.white)
                .fixedSize()
        }
        .padding(.top, 8)
        .accessibilityIdentifier(accessibilityIdentifier)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            // Only a full wait hides it: a cancelled task (the view rebuilt
            // while the restore scrolls) must not dismiss it at once.
            guard (try? await Task.sleep(nanoseconds: 6_000_000_000)) != nil else { return }
            isPresented = false
        }
    }
}
