import SwiftUI
import AVKit
import UIKit
import PhoebusCore

/// The pager: a horizontal, paging `UICollectionView`, not a SwiftUI
/// `TabView`.
///
/// A `TabView` rebuilds its page strip whenever any state its body reads
/// changes, and `selection` flips mid-swipe, so pages over-scroll or park
/// halfway. A plain collection view tracks the page by rounding content
/// offset over width; chrome, playback sync and prefetch hang off that
/// callback. UIKit owns the scrolling; SwiftUI owns only each page's
/// contents.
struct GalleryPager<Page: View>: UIViewControllerRepresentable {
    let count: Int
    @Binding var selection: Int
    @ViewBuilder let page: (Int) -> Page

    func makeUIViewController(context: Context) -> UIViewController {
        let layout = UICollectionViewFlowLayout()
        // Matches Reborn's own flow layout configuration.
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        let controller = GalleryPagerController(layout: layout)
        controller.coordinator = context.coordinator
        context.coordinator.controller = controller
        context.coordinator.page = { AnyView(page($0)) }
        context.coordinator.count = count
        context.coordinator.onSelect = { selection = $0 }
        controller.pendingInitialIndex = selection
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.page = { AnyView(page($0)) }
        context.coordinator.onSelect = { selection = $0 }
        guard let controller = controller as? GalleryPagerController else { return }
        if context.coordinator.count != count {
            context.coordinator.count = count
            controller.collectionView.reloadData()
        }
        // Re-host live pages only when the selection actually moved: assigning
        // `hosting.rootView` invalidates SwiftUI and schedules another
        // `updateUIViewController`, an update loop that starves rendering.
        controller.refreshVisiblePages(ifSelectionChangedTo: selection)
        // Never move the scroll view while the user is driving it.
        controller.scrollToPageIfNeeded(selection)
    }

    func makeCoordinator() -> GalleryPagerCoordinator { GalleryPagerCoordinator() }
}

/// Non-generic so the controller can reference it.
@MainActor
final class GalleryPagerCoordinator: NSObject {
    var page: (Int) -> AnyView = { _ in AnyView(EmptyView()) }
    var count = 0
    var onSelect: (Int) -> Void = { _ in }
    weak var controller: GalleryPagerController?
}

/// Hosts the paging collection view and reports the settled page.
@MainActor
final class GalleryPagerController: UIViewController,
                                    UICollectionViewDataSource,
                                    UICollectionViewDelegateFlowLayout {
    let collectionView: UICollectionView
    weak var coordinator: GalleryPagerCoordinator?
    /// Applied once the collection view has a real size; setting the
    /// offset before layout lands on the wrong page.
    var pendingInitialIndex: Int?
    private var currentIndex = 0
    private var lastLaidOutSize: CGSize = .zero

    init(layout: UICollectionViewFlowLayout) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Matches Reborn's own collection view configuration.
        collectionView.isPagingEnabled = true
        collectionView.backgroundColor = .black
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceVertical = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(GalleryPagerCell.self,
                                forCellWithReuseIdentifier: GalleryPagerCell.reuseID)
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .black
        view.addSubview(collectionView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard collectionView.bounds.size != lastLaidOutSize else { return }
        lastLaidOutSize = collectionView.bounds.size
        collectionView.collectionViewLayout.invalidateLayout()
        if let index = pendingInitialIndex, collectionView.bounds.width > 1 {
            pendingInitialIndex = nil
            currentIndex = index
            collectionView.layoutIfNeeded()
            collectionView.setContentOffset(
                CGPoint(x: CGFloat(index) * collectionView.bounds.width, y: 0),
                animated: false)
        }
    }

    /// The selection the visible pages were last built for.
    private var hostedSelection: Int?

    /// The selection a deferred re-host is waiting to apply.
    private var pendingSelection: Int?

    func refreshVisiblePages(ifSelectionChangedTo selection: Int) {
        guard hostedSelection != selection else { return }
        // Not while the scroll view is moving: swapping a hosting
        // controller's `rootView` mid-scroll makes SwiftUI relayout
        // inside the collection view, cancelling in-flight tracking
        // and parking the page halfway. Deferred until settled instead.
        if collectionView.isDragging || collectionView.isDecelerating {
            pendingSelection = selection
            return
        }
        pendingSelection = nil
        hostedSelection = selection
        guard let coordinator else { return }
        for cell in collectionView.visibleCells {
            guard let cell = cell as? GalleryPagerCell,
                  let indexPath = collectionView.indexPath(for: cell),
                  indexPath.item < coordinator.count
            else { continue }
            cell.host(coordinator.page(indexPath.item), in: self)
        }
    }

    func scrollToPageIfNeeded(_ index: Int) {
        guard pendingInitialIndex == nil,
              index != currentIndex,
              !collectionView.isDragging,
              !collectionView.isDecelerating,
              collectionView.bounds.width > 1,
              index >= 0, index < (coordinator?.count ?? 0)
        else { return }
        currentIndex = index
        collectionView.setContentOffset(
            CGPoint(x: CGFloat(index) * collectionView.bounds.width, y: 0),
            animated: true)
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        coordinator?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GalleryPagerCell.reuseID, for: indexPath)
        guard let cell = cell as? GalleryPagerCell, let coordinator else { return cell }
        cell.host(coordinator.page(indexPath.item), in: self)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // The pager's own bounds, matching the offsets and rotation guard: on an
        // external display (CarPlay) pixel snapping leaves `view` a fraction of a
        // point off, so pages sized from it drift from the offsets and videos don't
        // start on swipe (Reborn #1257).
        let size = collectionView.bounds.size
        return CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    /// The deferred re-host, once the scroll view has stopped.
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        applyPendingSelection()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { applyPendingSelection() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        applyPendingSelection()
    }

    private func applyPendingSelection() {
        guard let pending = pendingSelection else { return }
        refreshVisiblePages(ifSelectionChangedTo: pending)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Mid-rotation this fires with transitional geometry, which
        // lands on an unrelated page.
        guard scrollView.bounds.size == lastLaidOutSize else { return }
        let width = max(scrollView.bounds.width, 1)
        let count = coordinator?.count ?? 0
        guard count > 0 else { return }
        var page = Int((scrollView.contentOffset.x / width).rounded())
        page = max(0, min(page, count - 1))
        guard page != currentIndex else { return }
        currentIndex = page
        coordinator?.onSelect(page)
    }
}

/// One page, hosting SwiftUI content.
@MainActor
final class GalleryPagerCell: UICollectionViewCell {
    static let reuseID = "GalleryPagerCell"
    private var hosting: UIHostingController<AnyView>?

    func host(_ content: AnyView, in parent: UIViewController) {
        if let hosting {
            // Same cell, new content: swap the root view rather than
            // rebuild, so the page's own playing AVPlayer survives.
            hosting.rootView = content
            return
        }
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        controller.view.frame = contentView.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addChild(controller)
        contentView.addSubview(controller.view)
        controller.didMove(toParent: parent)
        hosting = controller
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hosting?.willMove(toParent: nil)
        hosting?.view.removeFromSuperview()
        hosting?.removeFromParent()
        hosting = nil
    }
}
