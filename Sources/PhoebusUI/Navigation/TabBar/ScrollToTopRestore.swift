import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit

/// Apollo: tapping the status bar scrolls the current list to the top, and
/// tapping it again returns to exactly where you were reading (stock iOS
/// scroll-to-top is one-way).
///
/// Two UIKit constraints shape this:
///
/// **1. The status-bar strip cannot be observed by the app.** A
/// `UITapGestureRecognizer` on the key window never receives taps in
/// the status-bar region; only `UIScrollView.scrollsToTop` reaches it.
///
/// **2. UIKit skips the delegate once the scroll view is at the top.**
/// `scrollViewShouldScrollToTop(_:)` stops being called once already
/// at true top, so the second tap would never arrive. The approach is to
/// never let the scroll view sit at *exactly* the top: always return
/// `false` (decline UIKit's own scroll), perform the movement
/// manually, and land the first tap `topEpsilon` points below true
/// top, small enough to be invisible but enough to keep UIKit
/// delivering the callback.
///
/// SwiftUI owns the `List`'s backing scroll view and its own delegate
/// (needed for infinite scroll's cell lifecycle), so this proxy
/// forwards every selector it does not implement via
/// `forwardingTarget(for:)` rather than replacing it.
/// Publishes whether a scroll-to-top return position is currently
/// available, so a screen can offer the Return Button affordance.
///
/// Reborn "Return Button" (`ScrollReturnButton`, default on). The saved
/// position and the second status-bar tap are always on; this setting governs
/// only the visible affordance.
@MainActor
public final class ScrollReturnStore: ObservableObject {
    public static let shared = ScrollReturnStore()

    /// True while a first status-bar tap has parked a position that a
    /// return would restore.
    @Published public private(set) var canReturn = false

    private var restore: (() -> Void)?

    func offer(_ restore: @escaping () -> Void) {
        self.restore = restore
        if !canReturn { canReturn = true }
    }

    func withdraw() {
        restore = nil
        if canReturn { canReturn = false }
    }

    /// Real footer: "tap it, the navigation bar, or the status bar
    /// again to go back to where you were."
    public func performReturn() {
        let action = restore
        withdraw()
        action?()
    }
}

final class ScrollToTopDelegateProxy: NSObject, UIScrollViewDelegate {
    /// The delegate SwiftUI installed. Everything this proxy does not
    /// implement is forwarded here.
    weak var forwardingDelegate: NSObjectProtocol?

    /// Offset to return to on the second tap. `nil` means "no place
    /// saved", the state after any manual scroll.
    private var savedOffset: CGPoint?

    /// How far below true top the first tap lands, keeping UIKit
    /// delivering the callback. See the type's doc comment.
    private static let topEpsilon: CGFloat = 1

    /// "Effectively at the top", tolerant of the epsilon above.
    /// Points of movement before a drag counts as a direction change.
    private static let directionThreshold: CGFloat = 12

    /// Last observed offset, for direction detection.
    private var lastScrollOffset: CGFloat = 0

    private func isAtTop(_ scrollView: UIScrollView) -> Bool {
        scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + Self.topEpsilon + 1
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        let top = CGPoint(
            x: scrollView.contentOffset.x,
            y: -scrollView.adjustedContentInset.top + Self.topEpsilon
        )
        if isAtTop(scrollView) {
            // Second tap: back to where the user was reading.
            guard let offset = savedOffset else { return false }
            savedOffset = nil
            ScrollReturnStore.shared.withdraw()
            scrollView.setContentOffset(offset, animated: true)
        } else {
            // First tap: remember this spot, then go (almost) to top.
            let parked = scrollView.contentOffset
            savedOffset = parked
            scrollView.setContentOffset(top, animated: true)
            // Offer the Return Button affordance. Populated
            // unconditionally; the setting gates only the UI.
            ScrollReturnStore.shared.offer { [weak self, weak scrollView] in
                guard let scrollView else { return }
                self?.savedOffset = nil
                scrollView.setContentOffset(parked, animated: true)
            }
        }
        // Always decline UIKit's own scroll: this proxy already
        // performed the movement, and letting UIKit also scroll would
        // race with the restore and land exactly at top.
        return false
    }

    /// A real user drag invalidates the saved position. Forwarded on
    /// so SwiftUI still sees the event.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        savedOffset = nil
        // The affordance must disappear with the saved position it
        // would have restored.
        ScrollReturnStore.shared.withdraw()
        // Reborn collapse trigger: an expanded navigation action group closes on
        // the first scroll. This proxy is already the List's scroll view delegate,
        // so it is the one place that observes the drag (a SwiftUI `DragGesture`
        // cannot: the List's own pan consumes it).
        NotificationCenter.default.post(
            name: .apolloNavigationActionsCollapse,
            object: NavigationActionsPolicy.CollapseReason.scrolled
        )
        lastScrollOffset = scrollView.contentOffset.y
        NotificationCenter.default.post(name: .apolloScrollGestureBegan, object: nil)
        (forwardingDelegate as? UIScrollViewDelegate)?.scrollViewWillBeginDragging?(scrollView)
    }

    /// Reports scroll DIRECTION for "Hide Bars on Scroll". Posted from
    /// here because this proxy is already the real `UIScrollView`'s
    /// delegate; SwiftUI has no scroll-direction callback of its own.
    /// `LiquidGlassTabBar` and "Hide Header on Scroll" both observe
    /// `.apolloScrollDidScrollDown`/`Up`.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        defer { (forwardingDelegate as? UIScrollViewDelegate)?.scrollViewDidScroll?(scrollView) }
        // Only react to genuine user dragging, not to programmatic
        // scrolls (scroll-to-top, jump-to-comment), which would
        // otherwise hide the bars behind the user's back.
        guard scrollView.isDragging || scrollView.isDecelerating else {
            lastScrollOffset = scrollView.contentOffset.y
            return
        }
        let offset = scrollView.contentOffset.y
        let delta = offset - lastScrollOffset
        // A small threshold so a few stray points of rubber-banding do
        // not count as a gesture.
        guard abs(delta) >= Self.directionThreshold else { return }
        lastScrollOffset = offset
        // Never hide the bars while bouncing above the top.
        if delta > 0, offset > -scrollView.adjustedContentInset.top {
            NotificationCenter.default.post(name: .apolloScrollDidScrollDown, object: nil)
        } else if delta < 0 {
            NotificationCenter.default.post(name: .apolloScrollDidScrollUp, object: nil)
        }
    }

    /// Forwarded so SwiftUI's refresh control sees the drag end: it
    /// decides whether a pull committed when the drag ends.
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        NotificationCenter.default.post(name: .apolloScrollGestureEnded, object: nil)
        (forwardingDelegate as? UIScrollViewDelegate)?
            .scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }

    /// Forwarded for the same reason: the refresh control ends its
    /// animation from here.
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        (forwardingDelegate as? UIScrollViewDelegate)?
            .scrollViewDidEndDecelerating?(scrollView)
    }

    // MARK: - Message forwarding

    override func responds(to aSelector: Selector!) -> Bool {
        // FORWARD FIRST for callbacks SwiftUI's own coordinator needs,
        // even though this proxy also implements them.
        // `.refreshable` installs a `UIRefreshControl` on the List's
        // backing scroll view driven by the scroll view's delegate
        // callbacks; `forwardingTarget(for:)` only runs for selectors
        // this object does NOT implement, so those callbacks must
        // check here first or the refresh control never sees them.
        if super.responds(to: aSelector) { return true }
        return forwardingDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let forwardingDelegate, forwardingDelegate.responds(to: aSelector) {
            return forwardingDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

/// Injects a probe view, finds the List's backing scroll view, and
/// installs the proxy above.
///
/// Introspection like this is version-sensitive, so every step fails
/// soft: if the scroll view cannot be found, the modifier does nothing
/// and the user keeps stock iOS scroll-to-top behaviour.
struct ScrollToTopRestoreModifier: UIViewRepresentable {
    func makeCoordinator() -> ScrollToTopDelegateProxy {
        ScrollToTopDelegateProxy()
    }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        probe.isHidden = true
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Deferred: at `updateUIView` time the probe is not yet in its
        // final position in the view hierarchy.
        DispatchQueue.main.async {
            guard let scrollView = uiView.associatedScrollView() else { return }
            let proxy = context.coordinator
            // `updateUIView` runs on every SwiftUI update; re-installing
            // would make the proxy forward to itself and recurse.
            if scrollView.delegate === proxy { return }
            proxy.forwardingDelegate = scrollView.delegate
            scrollView.delegate = proxy
            // Only one scroll view on screen may claim the status-bar
            // tap; iOS ignores the gesture entirely if several do.
            scrollView.scrollsToTop = true
        }
    }
}

extension UIView {
    /// The scroll view this probe should drive. Walks DOWN from the
    /// probe's own view controller's view (falling back to the
    /// window), preferring the largest scroll view, since walking UP
    /// doesn't work: `.background(...)` places the probe outside the
    /// List's backing scroll view in a sibling layer.
    func associatedScrollView() -> UIScrollView? {
        guard let root: UIView = owningViewController()?.view ?? window else { return nil }
        var best: UIScrollView?
        var bestArea: CGFloat = 0
        for candidate in UIKitTree.scrollViews(in: root) {
            let area = candidate.bounds.width * candidate.bounds.height
            if area > bestArea {
                bestArea = area
                best = candidate
            }
        }
        return best
    }
}

/// The Return Button affordance: an arrow beside Back, plus a
/// nav-bar tap, both of which return to the saved reading position.
///
/// Real footer copy: "Return Button puts an arrow beside Back after a
/// status bar tap scrolls to the top; tap it, the navigation bar, or
/// the status bar again to go back to where you were".
///
/// Gated on `scrollReturnButton` (default ON). The saved position and
/// the status-bar tap are NOT gated - see that setting's doc comment.
public struct ScrollReturnButtonModifier: ViewModifier {
    @ObservedObject private var store = ScrollReturnStore.shared
    private let enabled: Bool

    public init() {
        enabled = GeneralSettingsStore.load().scrollReturnButton
    }

    public func body(content: Content) -> some View {
        content.toolbar {
            // `.navigation` is the placement beside the back button,
            // which is where the real arrow sits.
            ToolbarItem(placement: .navigation) {
                if enabled && store.canReturn {
                    Button {
                        ScrollReturnStore.shared.performReturn()
                    } label: {
                        Image(systemName: "arrow.uturn.down")
                    }
                    .accessibilityLabel("Return to Position")
                    .accessibilityIdentifier("scroll.returnButton")
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.canReturn)
    }
}

public extension View {
    /// See `ScrollReturnButtonModifier`.
    func apolloScrollReturnButton() -> some View {
        modifier(ScrollReturnButtonModifier())
    }

    /// Adds tap-status-bar-again-to-return behaviour to the enclosing
    /// `List`/`ScrollView`. See `ScrollToTopDelegateProxy` for the two UIKit
    /// constraints this works around.
    func restoresPositionOnSecondScrollToTop() -> some View {
        background(
            ScrollToTopRestoreModifier()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}
#else
public extension View {
    func apolloScrollReturnButton() -> some View { self }
    func restoresPositionOnSecondScrollToTop() -> some View { self }
}
#endif
