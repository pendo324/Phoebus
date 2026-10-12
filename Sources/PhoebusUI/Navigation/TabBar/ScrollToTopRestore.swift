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
/// Publishes which screens have a scroll-to-top return position available,
/// so each can offer the Return Button affordance for its own position only.
///
/// Reborn "Return Button" (`ScrollReturnButton`, default on). The saved
/// position and the second status-bar tap are always on; this setting governs
/// only the visible affordance.
@MainActor
public final class ScrollReturnStore: ObservableObject {
    public static let shared = ScrollReturnStore()

    @Published private var offers = ScrollReturnOffers<UUID>()

    private var restores: [UUID: () -> Void] = [:]

    /// True while a first status-bar tap in `owner`'s list has parked a
    /// position that a return would restore.
    public func canReturn(_ owner: ScrollReturnOwner) -> Bool {
        offers.canReturn(owner.id)
    }

    func offer(for owner: UUID, _ restore: @escaping () -> Void) {
        restores[owner] = restore
        if !offers.canReturn(owner) { offers.offer(owner) }
    }

    func withdraw(for owner: UUID) {
        restores[owner] = nil
        if offers.canReturn(owner) { offers.withdraw(owner) }
    }

    /// Real footer: "tap it, the navigation bar, or the status bar
    /// again to go back to where you were."
    public func performReturn(_ owner: ScrollReturnOwner) {
        let action = restores[owner.id]
        withdraw(for: owner.id)
        action?()
    }
}

final class ScrollToTopDelegateProxy: NSObject, UIScrollViewDelegate {
    /// The screen this proxy's list belongs to; its saved position is offered
    /// to that screen's Return arrow only.
    let owner: UUID

    init(owner: UUID) {
        self.owner = owner
        super.init()
    }

    deinit {
        // The screen is gone with its list, and so is the position.
        let owner = owner
        Task { @MainActor in ScrollReturnStore.shared.withdraw(for: owner) }
    }

    /// The delegate SwiftUI installed. Everything this proxy does not
    /// implement is forwarded here.
    weak var forwardingDelegate: NSObjectProtocol?

    /// Long scrolls jump most of the way first (`UIScrollView.apolloScroll`).
    var shortensLongScrolls = false

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

    /// True from a jump to the top starting until it settles; a re-tap of
    /// the Posts tab is ignored meanwhile.
    private(set) var isJumping = false

    /// Bumped whenever a jump is cancelled (drag, return), so its pending
    /// settle does nothing.
    private var jumpGeneration = 0

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        if isAtTop(scrollView) {
            // Second tap: back to where the user was reading.
            guard let offset = savedOffset else { return false }
            savedOffset = nil
            cancelJump()
            ScrollReturnStore.shared.withdraw(for: owner)
            scroll(scrollView, to: offset)
        } else {
            // First tap: remember this spot, then go (almost) to top.
            scrollToTopSavingPosition(scrollView, animated: true)
        }
        // Always decline UIKit's own scroll: this proxy already
        // performed the movement, and letting UIKit also scroll would
        // race with the restore and land exactly at top.
        return false
    }

    /// The jump shared by a status-bar tap and a Posts-tab re-tap (Reborn
    /// "Fix Posts tab scroll-to-top and preserve return position", #1360):
    /// park the reading position, offer the Return Button, and scroll to just
    /// below the top. A repeat while the first jump runs keeps the original
    /// spot.
    func scrollToTopSavingPosition(_ scrollView: UIScrollView, animated: Bool) {
        let parked = savedOffset ?? scrollView.contentOffset
        savedOffset = parked
        jumpGeneration += 1
        let generation = jumpGeneration
        isJumping = animated
        if animated {
            scroll(scrollView, to: topOffset(of: scrollView))
        } else {
            scrollView.setContentOffset(topOffset(of: scrollView), animated: false)
        }
        // Offer the Return Button affordance. Populated
        // unconditionally; the setting gates only the UI.
        ScrollReturnStore.shared.offer(for: owner) { [weak self, weak scrollView] in
            guard let self, let scrollView else { return }
            self.savedOffset = nil
            self.cancelJump()
            self.scroll(scrollView, to: parked)
        }
        guard animated else { return }
        // A lazy SwiftUI List re-estimates row heights as rows scroll in,
        // which can leave one animated scroll short of the top. Settle once
        // it ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self, weak scrollView] in
            guard let self, let scrollView, self.jumpGeneration == generation else { return }
            self.isJumping = false
            guard !scrollView.isDragging, !self.isAtTop(scrollView) else { return }
            scrollView.setContentOffset(self.topOffset(of: scrollView), animated: false)
        }
    }

    private func topOffset(of scrollView: UIScrollView) -> CGPoint {
        CGPoint(x: scrollView.contentOffset.x,
                y: -scrollView.adjustedContentInset.top + Self.topEpsilon)
    }

    private func cancelJump() {
        jumpGeneration += 1
        isJumping = false
    }

    private func scroll(_ scrollView: UIScrollView, to offset: CGPoint) {
        if shortensLongScrolls {
            scrollView.apolloScroll(to: offset)
        } else {
            scrollView.setContentOffset(offset, animated: true)
        }
    }

    /// A real user drag invalidates the saved position. Forwarded on
    /// so SwiftUI still sees the event.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        savedOffset = nil
        cancelJump()
        // The affordance must disappear with the saved position it
        // would have restored.
        ScrollReturnStore.shared.withdraw(for: owner)
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
    let owner: ScrollReturnOwner
    var shortensLongScrolls = false

    func makeCoordinator() -> ScrollToTopDelegateProxy {
        ScrollToTopDelegateProxy(owner: owner.id)
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
            proxy.shortensLongScrolls = shortensLongScrolls
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

extension UIScrollView {
    /// An animated scroll to `target` that, from more than a screen and a
    /// half away, first jumps without animation to a screen short of it. A
    /// lazy `List` builds and sizes a cell for every row an animated scroll
    /// passes, so a long one stalls on a big comment thread; this way only
    /// about two screens of rows are built.
    func apolloScroll(to target: CGPoint) {
        let screen = bounds.height
        let distance = target.y - contentOffset.y
        if abs(distance) > screen * 1.5 {
            setContentOffset(CGPoint(x: target.x, y: target.y - (distance > 0 ? screen : -screen)), animated: false)
            layoutIfNeeded()
        }
        setContentOffset(target, animated: true)
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
    private let owner: ScrollReturnOwner
    private let enabled: Bool

    /// `owner` is the screen's token, the one its list was given in
    /// `restoresPositionOnSecondScrollToTop(owner:)`.
    public init(owner: ScrollReturnOwner) {
        self.owner = owner
        enabled = GeneralSettingsStore.load().scrollReturnButton
    }

    private var canReturn: Bool { store.canReturn(owner) }

    /// With Liquid Glass the arrow shares the back button's glass, as the
    /// trailing actions share theirs: the system back button can't be grouped
    /// with anything, so while the arrow shows it is swapped for an
    /// identical chevron in one group with it.
    private var mergesWithBack: Bool { enabled && canReturn && LiquidGlass.isEnabled }

    public func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(mergesWithBack)
            .toolbar {
                // Beside the back button, where the real arrow sits. Not
                // `.navigation`: on iOS 26+ that can join the trailing glass
                // group, over the title.
                if mergesWithBack {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        ScrollReturnBackButton()
                            .apolloGlassBarTint()
                        ScrollReturnArrow(owner: owner, enabled: enabled)
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        ScrollReturnArrow(owner: owner, enabled: enabled)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: canReturn)
    }
}

/// The back chevron standing in for the system one while the Return arrow
/// shares its glass. `dismiss` is read in this leaf, not the screen.
struct ScrollReturnBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
        }
        .accessibilityLabel("Back")
        .accessibilityIdentifier("scroll.returnBack")
    }
}

/// The Return Button's arrow, for a screen that draws its own back button and
/// has to put the arrow after it in its own toolbar.
public struct ScrollReturnArrow: View {
    @ObservedObject private var store = ScrollReturnStore.shared
    private let owner: ScrollReturnOwner
    private let enabled: Bool

    public init(owner: ScrollReturnOwner,
                enabled: Bool = GeneralSettingsStore.load().scrollReturnButton) {
        self.owner = owner
        self.enabled = enabled
    }

    public var body: some View {
        if enabled && store.canReturn(owner) {
            Button {
                ScrollReturnStore.shared.performReturn(owner)
            } label: {
                Image(systemName: "arrow.uturn.down")
            }
            .accessibilityLabel("Return to Position")
            .accessibilityIdentifier("scroll.returnButton")
            .transition(.opacity)
        }
    }
}

public extension View {
    /// See `ScrollReturnButtonModifier`.
    func apolloScrollReturnButton(owner: ScrollReturnOwner) -> some View {
        modifier(ScrollReturnButtonModifier(owner: owner))
    }

    /// Adds tap-status-bar-again-to-return behaviour to the enclosing
    /// `List`/`ScrollView`. See `ScrollToTopDelegateProxy` for the two UIKit
    /// constraints this works around. The position it saves is offered to
    /// the Return arrows given the same `owner`, and to no other screen's.
    /// `shortensLongScrolls` is for comment threads; a feed's image rows
    /// resize after the jump and land short.
    func restoresPositionOnSecondScrollToTop(owner: ScrollReturnOwner, shortensLongScrolls: Bool = false) -> some View {
        background(
            ScrollToTopRestoreModifier(owner: owner, shortensLongScrolls: shortensLongScrolls)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}
#else
public extension View {
    func apolloScrollReturnButton(owner: ScrollReturnOwner) -> some View { self }
    func restoresPositionOnSecondScrollToTop(owner: ScrollReturnOwner, shortensLongScrolls: Bool = false) -> some View { self }
}
#endif
