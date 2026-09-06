#if canImport(UIKit)
import UIKit
import PhoebusCore

/// Makes horizontal gestures (row swipes, page back/forward swipes) and
/// vertical scrolling mutually exclusive, in both directions.
///
/// A row recognizer's own 40pt vertical cut-off is not enough: UIKit's scroll
/// pan begins at ~10pt, so for the 30pt in between the list is scrolling while
/// a row swipe can still begin, and once a row swipe has begun nothing stops
/// the list's own pan from scrolling under it (both recognize simultaneously
/// by design, so taps and long-presses keep working). Apollo's table rows get
/// arbitration from UIKit, so exactly one of the two wins a touch; this
/// reproduces that outcome explicitly:
///  - `isScrolling(...)`: a scroll view whose pan has begun AND has
///    moved along an axis it can actually scroll. The axis test
///    matters: a vertical-only `List`'s pan can begin on a horizontal
///    drag without scrolling anything, and treating that as "scrolling"
///    would make every row swipe impossible.
///  - `ScrollLock`: turns the relevant scroll views' pans off for the
///    lifetime of a horizontal gesture and restores exactly the ones it
///    changed.
@MainActor
enum ScrollGestureExclusivity {
    /// Every `UIScrollView` at or above `view`, nearest first.
    static func enclosingScrollViews(of view: UIView?) -> [UIScrollView] {
        var result: [UIScrollView] = []
        var candidate = view
        while let current = candidate {
            if let scrollView = current as? UIScrollView {
                result.append(scrollView)
            }
            candidate = current.superview
        }
        return result
    }

    /// Whether this scroll view is being dragged by the user along an
    /// axis it can scroll.
    static func isScrolling(_ scrollView: UIScrollView) -> Bool {
        let pan = scrollView.panGestureRecognizer
        guard scrollView.isScrollEnabled, pan.isEnabled,
              pan.state == .began || pan.state == .changed else { return false }
        let t = pan.translation(in: scrollView)
        let inset = scrollView.adjustedContentInset
        let canScrollY = scrollView.alwaysBounceVertical
            || scrollView.contentSize.height + inset.top + inset.bottom > scrollView.bounds.height
        let canScrollX = scrollView.alwaysBounceHorizontal
            || scrollView.contentSize.width + inset.left + inset.right > scrollView.bounds.width
        // A few points of travel, not zero: UIKit begins the pan on
        // 2D distance, so a horizontal swipe with an opening wobble
        // can begin it with a 1-2pt vertical component that no user
        // would call "the screen started scrolling".
        let minimum = CGFloat(PushPopGesturePolicy.scrollStartedDistance)
        if canScrollY && abs(t.y) > abs(t.x) && abs(t.y) >= minimum { return true }
        if canScrollX && abs(t.x) >= abs(t.y) && abs(t.x) >= minimum { return true }
        return false
    }

    /// Whether any scroll view containing `view` is currently scrolling
    /// under the user's finger.
    static func isAnyEnclosingScrollViewScrolling(_ view: UIView?) -> Bool {
        enclosingScrollViews(of: view).contains(where: isScrolling)
    }

    /// Whether any scroll view under `windowPoint` is currently
    /// scrolling. Used by the SwiftUI page swipes, which have no UIKit
    /// view of their own to walk up from.
    static func isScrolling(atWindowPoint windowPoint: CGPoint) -> Bool {
        guard let window = keyWindow(),
              let hit = window.hitTest(windowPoint, with: nil) else { return false }
        return isAnyEnclosingScrollViewScrolling(hit)
    }

    static func keyWindow() -> UIWindow? {
        UIKitTree.keyWindow
    }
}

/// Disables scrolling on a set of scroll views and restores it later.
///
/// Only pans that were enabled when locked are touched on release, so a
/// scroll view something else deliberately disabled is never
/// re-enabled by accident.
/// Held weakly, so a view that leaves the hierarchy mid-gesture is not
/// kept alive by the lock.
@MainActor
final class ScrollLock {
    private var locked: [WeakScrollView] = []

    var isHeld: Bool { !locked.isEmpty }

    /// Disables the scroll view's own PAN recognizer rather than
    /// `isScrollEnabled`: SwiftUI owns `isScrollEnabled` on the
    /// collection view behind a `List` (it is what `.scrollDisabled`
    /// drives) and can reassert it on any view update, which a
    /// revealing row causes every frame. Disabling a recognizer also
    /// cancels it for the touch in progress, so the list cannot pick
    /// the touch back up once the horizontal gesture owns it.
    func lock(_ scrollViews: [UIScrollView]) {
        release()
        for scrollView in scrollViews where scrollView.panGestureRecognizer.isEnabled {
            scrollView.panGestureRecognizer.isEnabled = false
            locked.append(WeakScrollView(scrollView))
        }
    }

    func release() {
        for entry in locked {
            entry.view?.panGestureRecognizer.isEnabled = true
        }
        locked.removeAll()
    }

    private struct WeakScrollView {
        weak var view: UIScrollView?
        init(_ view: UIScrollView) { self.view = view }
    }
}
#endif
