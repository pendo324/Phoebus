import SwiftUI

#if canImport(UIKit)
import UIKit

/// A horizontal scroll view that cannot be scrolled vertically.
///
/// SwiftUI's `ScrollView(.horizontal)` still tracks a two-dimensional
/// pan: once a horizontal drag is recognised, continuing the same touch
/// downward moves the content vertically inside its frame, clipping the
/// cards. Reborn sets `directionalLockEnabled` on its scroller.
///
/// That alone is not enough: the lock only applies "if the user drags
/// in one general direction", so a drag already started horizontally is
/// not covered. Clamping the SwiftUI frame height and clipping does not
/// help either, since the offset is applied within the view's height.
/// So `contentOffset` itself is clamped, which no gesture, deceleration
/// or bounce can route around, and layout is manual: the content is
/// exactly as tall as the scroll view and as wide as it needs to be,
/// with no constraint system to arbitrate.
struct DirectionalLockScrollView<Content: View>: UIViewRepresentable {
    let height: CGFloat
    @ViewBuilder var content: () -> Content

    /// Pins `contentOffset.y` to zero at the lowest level available; every
    /// vertical movement (drag, deceleration, bounce) lands here.
    final class HorizontalOnlyScrollView: UIScrollView {
        var contentWidthProvider: (() -> CGFloat)?

        override var contentOffset: CGPoint {
            get { super.contentOffset }
            set { super.contentOffset = CGPoint(x: newValue.x, y: 0) }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let hosted = subviews.first else { return }
            let width = max(contentWidthProvider?() ?? 0, bounds.width)
            // Exactly the scroll view's own height: no vertical content to scroll.
            hosted.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            contentSize = CGSize(width: width, height: bounds.height)
        }
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = HorizontalOnlyScrollView()
        scrollView.isDirectionalLockEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        // Without this a tap that begins a scroll is swallowed and the cards
        // feel unresponsive.
        scrollView.delaysContentTouches = false
        // The feed lives in a navigation stack, so UIKit would otherwise add
        // a safe-area inset here and shift the cards.
        scrollView.contentInsetAdjustmentBehavior = .never

        let host = context.coordinator.host
        host.view.backgroundColor = .clear
        // Manual layout throughout; see the note above.
        host.view.translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(host.view)

        scrollView.contentWidthProvider = { [weak host] in
            guard let host else { return 0 }
            // The width the cards actually need. Otherwise the hosted view takes
            // the width it is given, the content size matches the frame, and there
            // is nothing to scroll horizontally.
            return host.sizeThatFits(in: CGSize(
                width: .greatestFiniteMagnitude,
                height: host.view.bounds.height
            )).width
        }

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.host.rootView = content()
        // A hosted view does not re-measure when the SwiftUI content changes
        // size, which would leave a stale contentSize.
        uiView.setNeedsLayout()
    }

    @MainActor
    final class Coordinator {
        let host: UIHostingController<Content>
        init(content: Content) {
            host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            // Not in a view-controller hierarchy, so it must not claim safe-area
            // insets.
            host.safeAreaRegions = []
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content())
    }
}
#endif
