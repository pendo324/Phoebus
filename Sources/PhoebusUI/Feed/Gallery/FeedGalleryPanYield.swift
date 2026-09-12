#if canImport(UIKit)
import SwiftUI
import UIKit
import PhoebusCore

/// Lets a feed gallery give an outward pan away as it begins
/// (`FeedGalleryPanPolicy`, Reborn #1271). A SwiftUI `TabView`'s paging
/// scroll view can't be subclassed, so a probe finds it and adds a gate
/// recognizer its pan must wait on. The gate only begins for a pan the
/// policy yields, which fails the carousel's pan for that touch; it
/// recognizes alongside everything and never cancels touches, so the row
/// swipe and the page swipes still see the finger.
struct FeedGalleryPanYield: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        private weak var carousel: UIScrollView?
        private weak var gate: UIPanGestureRecognizer?
        private let gateDelegate = GateDelegate()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                // Off screen: take the gate back off, or a reused
                // carousel collects one per row that ever hosted it.
                if let gate { carousel?.removeGestureRecognizer(gate) }
                carousel = nil
                return
            }
            guard carousel == nil else { return }
            // The TabView lays its scroll view out after this view.
            DispatchQueue.main.async { [weak self] in self?.install() }
        }

        /// The paging scroll view sharing this probe's frame: the nearest
        /// ancestor's descendants hold the TabView's.
        private func install() {
            guard let window, carousel == nil else { return }
            let mine = convert(bounds, to: window)
            var ancestor = superview
            for _ in 0..<6 {
                guard let root = ancestor else { break }
                if let scroll = UIKitTree.firstDescendant(of: UIScrollView.self, in: root, where: { scroll in
                    scroll.isPagingEnabled && scroll.window != nil
                        && abs(scroll.convert(scroll.bounds, to: window).midY - mine.midY) < 4
                }) {
                    let gate = UIPanGestureRecognizer(target: nil, action: nil)
                    gateDelegate.carousel = scroll
                    gate.delegate = gateDelegate
                    gate.cancelsTouchesInView = false
                    gate.delaysTouchesBegan = false
                    gate.delaysTouchesEnded = false
                    scroll.addGestureRecognizer(gate)
                    scroll.panGestureRecognizer.require(toFail: gate)
                    carousel = scroll
                    self.gate = gate
                    return
                }
                ancestor = root.superview
            }
        }

    }

    final class GateDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var carousel: UIScrollView?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let carousel, let pan = recognizer as? UIPanGestureRecognizer,
                  GeneralSettingsStore.load().feedGalleryEdgeSwipeNav else { return false }
            let space: UIView = carousel.window ?? carousel
            let velocity = pan.velocity(in: carousel)
            let touchX = pan.location(in: space).x - pan.translation(in: space).x
            let disposition = FeedGalleryPanPolicy.disposition(
                contentOffsetX: Double(carousel.contentOffset.x),
                maximumOffsetX: Double(carousel.contentSize.width - carousel.bounds.width),
                velocityX: Double(velocity.x), velocityY: Double(velocity.y),
                touchX: Double(touchX), viewWidth: Double(space.bounds.width),
                rightToLeft: carousel.effectiveUserInterfaceLayoutDirection == .rightToLeft,
                canGoBack: PageSwipeController.canGoBack,
                canGoForward: ForwardNavigationStore.shared.canGoForward)
            return disposition == .yield
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
