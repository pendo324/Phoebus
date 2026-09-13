import SwiftUI
import PhoebusCore
import UIKit

/// A raw `UIGestureRecognizer` (not `UIPanGestureRecognizer`), bridged
/// into SwiftUI, that reports live translation without blocking a
/// `List`'s own vertical scroll gesture.
///
/// `UIPanGestureRecognizer` asks `gestureRecognizerShouldBegin` only once,
/// so an ambiguous touch that only reveals horizontal intent later never
/// gets a second chance. This recognizer re-runs
/// `PushPopGesturePolicy.rowSwipeShouldBegin` on every `touchesMoved`
/// sample while `.possible`, so it commits as soon as any sample qualifies.
private final class ApolloSwipePanRecognizer: UIGestureRecognizer {
    var onChanged: ((CGSize) -> Void)?
    var onEnded: ((CGSize) -> Void)?
    var onCancelled: (() -> Void)?
    /// Reports the whole list cell's frame in window coordinates when a
    /// swipe begins, so the revealed panel can cover the full row (see
    /// `ProgressiveSwipeRowModifier.cellFrame`).
    var onBeganInCell: ((CGRect) -> Void)?

    /// The touch this recognizer is currently tracking. A raw
    /// `UIGestureRecognizer` computes translation/velocity by hand below.
    private weak var trackedTouch: UITouch?
    private var startLocation: CGPoint = .zero
    private var previousLocation: CGPoint = .zero
    private var previousTimestamp: TimeInterval = 0
    private var currentVelocity: CGPoint = .zero
    /// Set once cumulative vertical travel rules out a row swipe, and never
    /// cleared for the touch: a single frame-to-frame sample can look
    /// momentarily horizontal mid-scroll, so the cumulative distance guards
    /// against that.
    private var verticallyDisqualified = false
    /// Distance that permanently rules out a row swipe. Larger than
    /// `minimumHorizontalDistance`, since a real swipe's vertical wobble is
    /// only a few points.
    static let verticalDisqualifyDistance: CGFloat = 24

    /// Holds the enclosing scroll views still while a row swipe owns
    /// the touch. Released in `reset()`.
    private let scrollLock = ScrollLock()
    /// What the finger landed on, to find a sideways scroller under it.
    private weak var touchedView: UIView?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // Disable delay/cancel behaviors so this recognizer and SwiftUI's own
        // tap recognizer both see every touch immediately.
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        cancelsTouchesInView = false
    }

    /// Horizontal distance before this recognizer considers beginning.
    static let minimumHorizontalDistance = CGFloat(PushPopGesturePolicy.rowSwipeMinimumDistance)

    /// Direction-dominance ratio (1.65), shared with the navigation insets.
    static let directionRatio: CGFloat = CGFloat(PushPopGesturePolicy.horizontalDominance)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        // Single-touch only: a second finger doesn't restart or redirect an
        // already-possible/active touch.
        guard trackedTouch == nil, let touch = touches.first, let view else { return }
        trackedTouch = touch
        touchedView = touch.view
        startLocation = touch.location(in: view)
        previousLocation = startLocation
        previousTimestamp = touch.timestamp
        currentVelocity = .zero
        verticallyDisqualified = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let tracked = trackedTouch, touches.contains(tracked), let view else { return }
        let location = tracked.location(in: view)
        let dt = tracked.timestamp - previousTimestamp
        if dt > 0 {
            currentVelocity = CGPoint(
                x: (location.x - previousLocation.x) / CGFloat(dt),
                y: (location.y - previousLocation.y) / CGFloat(dt))
        }
        previousLocation = location
        previousTimestamp = tracked.timestamp
        let t = CGPoint(x: location.x - startLocation.x, y: location.y - startLocation.y)
        if abs(t.y) >= Self.verticalDisqualifyDistance {
            verticallyDisqualified = true
        }

        switch state {
        case .possible:
            // The info-row magnifier owns a touch it has opened on.
            if InfoRowHoldRecognizer.isHolding {
                state = .failed
                return
            }
            // Stays `.possible` until vertically disqualified or a qualifying
            // horizontal sample commits it.
            guard !verticallyDisqualified else { return }
            // Once any enclosing scroll view starts scrolling under this
            // finger, fail outright so it can never revive.
            if ScrollGestureExclusivity.isAnyEnclosingScrollViewScrolling(view) {
                state = .failed
                return
            }
            let ok = computeShouldBegin(t: t, v: currentVelocity)
            guard ok else { return }
            state = .began
            SwipeGestureArbiter.rowSwipeActive = true
            // Swipe first means swipe only: freeze every enclosing scroll view
            // for the rest of this touch, cancelling any scroll pan already begun.
            scrollLock.lock(ScrollGestureExclusivity.enclosingScrollViews(of: view))
            // Re-base translation on the point the swipe began, so the row
            // starts moving from where it is rather than jumping.
            startLocation.x = location.x
            onBeganInCell?(view.convert(view.bounds, to: nil))
            onChanged?(CGSize(width: 0, height: t.y))
        case .began, .changed:
            state = .changed
            onChanged?(CGSize(width: t.x, height: t.y))
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let tracked = trackedTouch, touches.contains(tracked), let view else { return }
        let location = tracked.location(in: view)
        let t = CGPoint(x: location.x - startLocation.x, y: location.y - startLocation.y)
        if state == .began || state == .changed {
            state = .ended
            onEnded?(CGSize(width: t.x, height: t.y))
        } else {
            // Never committed: reset via the same path a real end would use.
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let tracked = trackedTouch, touches.contains(tracked) else { return }
        let hadCommitted = (state == .began || state == .changed)
        state = .cancelled
        if hadCommitted, let view {
            // A cancelled pan still commits its action if the drag went far
            // enough: another recognizer (navigation pan, List scroll) can
            // cancel this one even after a real swipe, and `onEnded` re-checks
            // the distance so an abandoned drag still snaps back.
            let location = tracked.location(in: view)
            let t = CGPoint(x: location.x - startLocation.x, y: location.y - startLocation.y)
            onEnded?(CGSize(width: t.x, height: t.y))
        }
    }

    /// Whether the touch started on a sideways scroller inside the row (a feed
    /// gallery) that can still move the way the finger goes. That pan pages the
    /// gallery; only one pulling past its first or last image belongs to the row
    /// (Reborn #1271).
    private func startsOnScrollableCarousel(towards dx: CGFloat) -> Bool {
        var current = touchedView
        while let candidate = current, candidate !== view {
            if let scroll = candidate as? UIScrollView,
               scroll.contentSize.width > scroll.bounds.width + 1 {
                let maxOffset = scroll.contentSize.width - scroll.bounds.width
                return dx < 0 ? scroll.contentOffset.x < maxOffset - 0.5 : scroll.contentOffset.x > 0.5
            }
            current = candidate.superview
        }
        return false
    }

    /// Declines to begin once the pan's initial direction is vertical-dominant,
    /// so the List's own pan never has to compete. Also declines inside the
    /// navigation edge insets (`PushPopGesturePolicy` leading/trailing), as
    /// Apollo's push/pop pan does.
    private func computeShouldBegin(t: CGPoint, v: CGPoint) -> Bool {
        // Checked on every sample: a momentary horizontal blip during a messy
        // vertical scroll still needs distance AND ratio at the same sample.
        guard abs(t.x) >= Self.minimumHorizontalDistance else { return false }
        guard !startsOnScrollableCarousel(towards: t.x) else { return false }
        // Translation OR velocity, not both, matching UIKit's own scroll views:
        // requiring both rejects a slow deliberate drag or a fast flick with wobble.
        guard PushPopGesturePolicy.rowSwipeShouldBegin(
            translationX: Double(t.x), translationY: Double(t.y),
            velocityX: Double(v.x), velocityY: Double(v.y),
            minimumDistance: Double(Self.minimumHorizontalDistance)
        ) else { return false }
        guard let view else { return true }
        // Measured against the window, since the navigation insets are
        // relative to the screen edges.
        let screenWidth = view.window?.bounds.width ?? UIScreen.main.bounds.width
        let screenHeight = view.window?.bounds.height ?? UIScreen.main.bounds.height
        let startInWindow = view.convert(startLocation, to: nil)
        // Real Apollo's row swipe never lives near the bottom edge; see
        // `bottomSystemGestureInset`'s own doc comment.
        guard !PushPopGesturePolicy.startedInBottomSystemGestureZone(
            startY: Double(startInWindow.y),
            viewHeight: Double(screenHeight)
        ) else { return false }
        // A page swipe already running owns this touch outright: the geometric
        // test predicts which gesture wants it, but they sample on different
        // schedules, so a prediction alone could let both begin.
        guard !PageSwipeController.isActive else { return false }
        return !PushPopGesturePolicy.navigationClaimsRowTouch(
            startX: Double(startInWindow.x),
            translationX: Double(t.x), translationY: Double(t.y),
            velocityX: Double(v.x), velocityY: Double(v.y),
            viewWidth: Double(screenWidth),
            canGoBack: PageSwipeController.canGoBack,
            canGoForward: ForwardNavigationStore.shared.canGoForward
        )
    }

    override func reset() {
        super.reset()
        SwipeGestureArbiter.rowSwipeActive = false
        scrollLock.release()
        trackedTouch = nil
        touchedView = nil
        startLocation = .zero
        previousLocation = .zero
        previousTimestamp = 0
        currentVelocity = .zero
        verticallyDisqualified = false
    }
}

/// Which of the two competing horizontal gestures - a row swipe or a
/// page (back/forward) swipe - currently owns the touch, so the other
/// refuses to begin.
///
/// Real Apollo's row swipe and push/pop pan share one delegate; here they
/// are separate recognizers on different views, so they need an explicit
/// shared flag. The page side is `PageSwipeController.isActive`; this is
/// the row side.
@MainActor
enum SwipeGestureArbiter {
    /// Set when a row swipe begins, cleared when its recognizer resets
    /// (UIKit calls `reset()` after every terminal state).
    static var rowSwipeActive = false
}

/// Own delegate object, separate from the recognizer since it is a raw
/// `UIGestureRecognizer` subclass rather than a `UIPanGestureRecognizer`
/// acting as its own delegate.
private final class ApolloSwipeRecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
    /// Real Apollo's swipe reveal stays live alongside a long-press context
    /// menu or double-tap-to-collapse on the same row; only the List's own
    /// scroll is excluded, via the `.possible`-state direction gate.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Attaches `ApolloSwipePanRecognizer` to a real UIKit ancestor of the
/// row's own content, rather than to an `.overlay`'s own (sibling) view.
/// Touches are only delivered to a recognizer whose view is hit-tested or
/// a real ancestor, never a sibling, so attaching to an overlay sibling
/// would eat every `.onTapGesture` on the row.
///
/// Discovery of the target ancestor is deferred by one
/// `DispatchQueue.main.async` tick past `didMoveToSuperview()`, since that
/// callback fires before SwiftUI finishes attaching this representable's
/// host-wrapper chain to the real window hierarchy.
private final class AncestorAttachingView: UIView {
    var onAttach: ((UIView) -> Void)?
    /// Called when this view leaves the hierarchy, so the recognizer
    /// can be taken off the ancestor it was added to.
    var onDetach: ((UIView) -> Void)?
    private var attached = false
    /// The ancestor the recognizer was actually added to, kept so the
    /// exact same view can be cleaned up later.
    private weak var attachedAncestor: UIView?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // Detach when this view is removed. A `List` recycles cells, so one
        // shared cell content view is handed to a different row while
        // scrolling; without detaching, a recycled ancestor would accumulate
        // one recognizer per row that ever used it.
        if superview == nil {
            if let ancestor = attachedAncestor {
                onDetach?(ancestor)
            }
            attachedAncestor = nil
            attached = false
            return
        }
        guard !attached else { return }
        DispatchQueue.main.async { [weak self] in
            self?.attachIfPossible()
        }
    }

    private func attachIfPossible() {
        guard !attached else { return }
        // Walk upward searching for `_UICollectionViewListCellContentView`
        // by class name: different screens wrap the row in different numbers
        // of SwiftUI containers, so a fixed hop count could land short. This
        // class is a genuine ancestor of every row's content, and is also
        // the view SwiftUI's internal row tap recognizer lives on, which is
        // why this recognizer attaches one level above it.
        var candidate: UIView? = superview
        var cellContentView: UIView?
        // Defensive backstop: fail safe (never attach) rather than walking
        // indefinitely if SwiftUI internals ever change.
        var hopsRemaining = 12
        while let view = candidate, hopsRemaining > 0 {
            if NSStringFromClass(type(of: view)).contains("UICollectionViewListCellContentView") {
                cellContentView = view
                break
            }
            candidate = view.superview
            hopsRemaining -= 1
        }
        guard let cellContentView else {
            return
        }
        attached = true
        attachedAncestor = cellContentView
        onAttach?(cellContentView)
    }
}

private struct SwipeGestureHostingView: UIViewRepresentable {
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize) -> Void
    let onCancelled: () -> Void
    let onBeganInCell: (CGRect) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = AncestorAttachingView()
        view.backgroundColor = .clear
        // Disabled at creation, before insertion into the hierarchy:
        // leaving it enabled until `attachIfPossible()` runs would let a tap
        // hit-test to this view instead of the row's content, since it is
        // frontmost until reparented. Combined with `.background(...)`
        // placement (behind content in the z-stack), this keeps tapping,
        // scrolling, and swipe-reveal all working together.
        view.isUserInteractionEnabled = false
        let recognizer = ApolloSwipePanRecognizer(target: nil, action: nil)
        recognizer.onChanged = onChanged
        recognizer.onEnded = onEnded
        recognizer.onCancelled = onCancelled
        recognizer.onBeganInCell = onBeganInCell
        recognizer.delegate = context.coordinator.delegate
        context.coordinator.recognizer = recognizer
        view.onAttach = { ancestor in
            // Defensive: never add the same recognizer twice.
            if recognizer.view !== ancestor {
                ancestor.addGestureRecognizer(recognizer)
            }
        }
        view.onDetach = { ancestor in
            // Remove OUR recognizer specifically, so a recycled cell does not
            // carry it into the next comment.
            if recognizer.view === ancestor {
                ancestor.removeGestureRecognizer(recognizer)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.recognizer?.onChanged = onChanged
        context.coordinator.recognizer?.onEnded = onEnded
        context.coordinator.recognizer?.onCancelled = onCancelled
        context.coordinator.recognizer?.onBeganInCell = onBeganInCell
    }

    final class Coordinator {
        var recognizer: ApolloSwipePanRecognizer?
        /// Held here so it outlives the recognizer's own weak
        /// `delegate` reference.
        var delegate: ApolloSwipeRecognizerDelegate!

        init() {
            delegate = ApolloSwipeRecognizerDelegate()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
}

/// Progressive, breakpoint-driven swipe gesture, reimplementing
/// Apollo's per-row swipe interaction ("Long Swipe Trigger Point"
/// setting): as you drag, the revealed action icon/color morphs from the
/// short-swipe to the long-swipe action once you cross a threshold, with a
/// haptic tick at the crossover, and releasing past that point commits the
/// long-swipe action immediately.
///
/// SwiftUI's `.swipeActions()` and `UITableView`'s own swipe actions can't
/// express this morph-as-you-drag behavior or a full reversal from one
/// edge's actions into the other within a single touch, which is why this
/// reimplements the gesture with a custom pan.
struct ProgressiveSwipeRowModifier: ViewModifier {
    let settings: SwipeActionSettings
    /// What the row's actions would undo, for their icons.
    let subject: SwipeSubject?
    let onAction: (SwipeAction) -> Void
    @ObservedObject private var votes = VoteStateStore.shared

    init(settings: SwipeActionSettings, subject: SwipeSubject?, onAction: @escaping (SwipeAction) -> Void) {
        self.settings = settings
        self.subject = subject
        self.onAction = onAction
    }

    /// Distance (in points) at which the short-swipe action's icon
    /// starts becoming visible.
    private let revealThreshold: CGFloat = 40
    /// Distance at which the revealed action morphs from short-swipe to
    /// long-swipe. Exposed as the user-tunable "Long Swipe Trigger Point"
    /// setting; must sit beyond `commitThreshold` or every commit would
    /// already have crossed the long threshold.
    ///
    /// Measured against the raw drag distance, not the damped offset (the
    /// offset is damped to 25% past `commitThreshold`).
    private var longSwipeThreshold: CGFloat {
        CGFloat(SwipeCommitPolicy.longThreshold(
            fraction: NavigationGestureSettingsStore.load().longSwipeTriggerPoint.fraction,
            width: Double(UIScreen.main.bounds.width)
        ))
    }
    /// Apollo's "Navigation Gestures" "Disable Right/Left Swipes". "Left"/"Right"
    /// name the slots (the revealed side), not the finger's travel: Left is a
    /// rightward drag, which back-anywhere then takes. Only disables the row-level
    /// reveal; the page-swipe half is `PushPopGesturePolicy.backAnywhere`/
    /// `forwardAnywhere`. Loaded fresh per check so a Gestures screen change
    /// applies immediately.
    private var navGestureSettings: NavigationGestureSettings {
        NavigationGestureSettingsStore.load()
    }
    /// Distance at which releasing commits the short action (Apollo's
    /// measured 60pt). See `SwipeCommitPolicy.shortThreshold`.
    private var commitThreshold: CGFloat {
        CGFloat(SwipeCommitPolicy.commitThreshold(width: Double(UIScreen.main.bounds.width)))
    }
    /// Once a direction locks in, translation must return within this many
    /// points of the start before the opposite direction can engage. Wide
    /// enough to require a decisive return, while still allowing a
    /// direction swap within one continuous touch.
    private let centerResetZone: CGFloat = 56
    /// How far the touch must move before a direction locks in. Small: the
    /// recognizer already decided this is a swipe and rebased translation
    /// to zero, so it should track from very near the start.
    private let directionEngageZone: CGFloat = 1

    @State private var dragOffset: CGFloat = 0
    @State private var crossedLongSwipe = false
    @State private var crossedCommit = false
    /// -1 = left-revealed (dragging leftward, trailing actions), 1 =
    /// right-revealed (leading actions), 0 = neutral/centered.
    @State private var lockedDirection: Int = 0
    /// Bumped on every threshold crossing to play the icon's pop.
    @State private var iconPop = 0
    /// The whole list cell's frame in window space, captured when the swipe
    /// begins, so the revealed panel can span the full row rather than just
    /// this modifier's own content.
    @State private var cellFrame: CGRect = .null

    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .background {
                if dragOffset != 0 {
                    // Pinned to the screen edge, not the row's own bounds:
                    // real Apollo slides the whole cell, margins included.
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .global)
                        let screenWidth = UIScreen.main.bounds.width
                        let width = abs(dragOffset)
                        let leading = dragOffset > 0
                            ? -frame.minX
                            : screenWidth - frame.minX - width
                        // Full cell height, not just this content's; falls
                        // back to content height if never measured.
                        let hasCell = !cellFrame.isNull && cellFrame.height >= proxy.size.height
                        let top = hasCell ? cellFrame.minY - frame.minY : 0
                        let height = hasCell ? cellFrame.height : proxy.size.height
                        actionBackground
                            .frame(width: width, height: height)
                            .offset(x: leading, y: top)
                    }
                }
            }
            .background(
                SwipeGestureHostingView(
                    onChanged: { handleChanged($0) },
                    onEnded: { handleEnded($0) },
                    onCancelled: { resetDrag() },
                    onBeganInCell: { cellFrame = $0 }
                )
            )
    }

    private func handleChanged(_ translation: CGSize) {
        let raw = translation.width

        switch lockedDirection {
        case 0:
            if abs(raw) > directionEngageZone {
                lockedDirection = raw > 0 ? 1 : -1
            }
        default:
            let rawSign = raw == 0 ? 0 : (raw > 0 ? 1 : -1)
            if rawSign != lockedDirection && abs(raw) <= centerResetZone {
                // Passed back through center: fully reset, including
                // haptic-tracking flags, so continuing the same touch in the
                // new direction starts fresh rather than inheriting
                // "already crossed long-swipe" state from the original one.
                // Only requires a genuine return toward center, not a full
                // lift-and-restart.
                lockedDirection = 0
                dragOffset = 0
                crossedLongSwipe = false
                crossedCommit = false
                return
            }
        }

        guard lockedDirection != 0 else {
            dragOffset = 0
            return
        }

        let navGestures = navGestureSettings
        // A rightward drag runs the Left slots, so Disable Left Swipes
        // frees it for swipe-anywhere back (and Right for forward).
        let allowedRight = (settings.leftShort != .none || settings.leftLong != .none) && !navGestures.disableLeftSwipeGestureActions
        let allowedLeft = (settings.rightShort != .none || settings.rightLong != .none) && !navGestures.disableRightSwipeGestureActions
        if lockedDirection > 0 && !allowedRight { return }
        if lockedDirection < 0 && !allowedLeft { return }

        // 1:1 with the finger: real Apollo tracks it directly with no damping.
        let magnitude = abs(raw)
        dragOffset = lockedDirection < 0 ? -magnitude : magnitude

        let long = magnitude >= longSwipeThreshold
        if long != crossedLongSwipe {
            crossedLongSwipe = long
            iconPop &+= 1
            Haptics.selection()
        }
        let committed = magnitude >= commitThreshold
        if committed != crossedCommit {
            crossedCommit = committed
            iconPop &+= 1
            Haptics.medium()
        }
    }

    private func handleEnded(_ translation: CGSize) {
        // Already committing: the post-commit timer owns the reset, so
        // this must not interfere with it.
        guard lockedDirection != 0 else {
            resetDrag()
            return
        }
        // The RAW distance decides both questions, matching `handleChanged`;
        // the damped value only limits how far the row visually slides.
        let magnitude = abs(translation.width)
        let isRight = lockedDirection > 0
        let short = isRight ? settings.leftShort : settings.rightShort
        let long = isRight ? settings.leftLong : settings.rightLong

        if magnitude >= commitThreshold {
            let action = crossedLongSwipe ? long : short
            commit(action, direction: isRight ? 1 : -1)
        } else {
            // Released without reaching the full-swipe commit point: snaps
            // back without performing an action (real Apollo has no "stay
            // open" state, unlike SwiftUI's native `.swipeActions()`).
            resetDrag(animated: true)
        }
    }

    private func resetDrag(animated: Bool = false) {
        if animated {
            // Critically damped so the row settles back without
            // swinging past centre, matching real Apollo.
            withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                dragOffset = 0
            }
        } else {
            dragOffset = 0
        }
        crossedLongSwipe = false
        crossedCommit = false
        lockedDirection = 0
    }

    private func commit(_ action: SwipeAction, direction: Int) {
        guard action != .none else {
            resetDrag(animated: true)
            return
        }
        Haptics.medium()
        // The row springs back and the action fires; it does not fly off-screen
        // first, since `resetDrag` completes synchronously.
        resetDrag(animated: true)
        onAction(action)
    }

    /// The colored background + icon revealed behind the row as it's
    /// dragged, morphing from short-swipe to long-swipe action once
    /// `longSwipeThreshold` is crossed. Sized to `abs(dragOffset)` and
    /// pinned to the correct edge, matching real Apollo's gesture.
    ///
    /// Real Apollo's layout, matched here:
    ///  - The icon rides with the row's moving edge, its centre `iconInset`
    ///    (30pt) inside it, meeting its resting place at the 60pt
    ///    short-action point.
    ///  - It fades in linearly with the drag until then, pops (~1.25x) on
    ///    every threshold crossing, and the colour swaps outright at the
    ///    long point (no cross-fade).
    @ViewBuilder
    private var actionBackground: some View {
        let isRight = dragOffset > 0
        let width = abs(dragOffset)
        let short = isRight ? settings.leftShort : settings.rightShort
        let long = isRight ? settings.leftLong : settings.rightLong
        let action = crossedLongSwipe ? long : short
        if action != .none {
            let inset = Self.iconInset
            let centre = min(width, commitThreshold) - inset
            Self.color(for: action)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .overlay {
                    GeometryReader { proxy in
                        icon(for: action)
                            .phaseAnimator([1.0, 1.25, 1.0], trigger: iconPop) { icon, scale in
                                icon.scaleEffect(scale)
                            } animation: { _ in .easeOut(duration: 0.07) }
                            .opacity(min(1, Double(width / commitThreshold)))
                            .position(
                                x: isRight ? centre : width - centre,
                                y: proxy.size.height / 2
                            )
                    }
                }
                .clipped()
        }
    }

    /// Distance of the icon's centre from the row's moving edge, ~30pt
    /// matching real Apollo.
    static let iconInset: CGFloat = 30

    /// Apollo's own `slide-*` glyphs: thin outlines, except Reply's,
    /// which is solid. An action that would undo something shows the
    /// undo glyph, as Apollo does: un-upvote on an upvoted post, unsave
    /// on a saved one, mark unread on a read message.
    @ViewBuilder
    private func icon(for action: SwipeAction) -> some View {
        let name = Self.iconName(for: action, subject: subject, votes: votes)
        // The glyphs added with stock's full action list ship as PNGs.
        if Self.pngIcons.contains(name) {
            StockPNG.image(name).foregroundStyle(.white)
        } else {
            StockIcon(name).foregroundStyle(.white)
        }
    }

    static let pngIcons: Set<String> = ["slide-hide-above-hollow", "slide-parent-comment-hollow", "slide-author-hollow",
                                        "slide-subreddit-hollow", "slide-select-mode-hollow", "slide-collapse-root-hollow"]

    static func iconName(for action: SwipeAction, subject: SwipeSubject?, votes: VoteStateStore) -> String {
        let vote = subject.flatMap { votes.vote(for: $0.fullname, serverValue: $0.likes) }
        let saved = subject.map { votes.isSaved($0.fullname, serverValue: $0.saved) } ?? false
        switch action {
        case .upvote: return vote == true ? "slide-unupvote-hollow" : "slide-upvote-hollow"
        case .downvote: return vote == false ? "slide-undownvote-hollow" : "slide-downvote-hollow"
        case .save: return saved ? "slide-unsave-hollow" : "slide-save-hollow"
        case .reply: return "slide-reply-solid"
        case .share: return "slide-share-hollow"
        case .hide: return "slide-hide-hollow"
        case .collapseTop: return "slide-collapse-root-hollow"
        case .collapse: return "slide-collapse-hollow"
        case .markRead: return subject?.unread == false ? "slide-unread-hollow" : "slide-read-hollow"
        case .hidePostsAbove: return "slide-hide-above-hollow"
        case .parentComment: return "slide-parent-comment-hollow"
        case .author: return "slide-author-hollow"
        case .subreddit: return "slide-subreddit-hollow"
        case .selectText: return "slide-select-mode-hollow"
        case .none: return action.systemImage
        }
    }

    /// Real Apollo's swipe colours: Upvote FF5F00, Downvote 4D53DE,
    /// Collapse 0076F7, Reply 1FABFF. Actions without a dedicated
    /// colour here keep their system colours.
    static func color(for action: SwipeAction) -> Color {
        switch action {
        case .upvote: return Color(hex: "FF5F00")
        case .downvote: return Color(hex: "4D53DE")
        case .collapseTop, .collapse: return Color(hex: "0076F7")
        case .reply: return Color(hex: "1FABFF")
        default:
            switch action.tintColor {
            case "orange": return .orange
            case "blue": return .blue
            case "green": return .green
            case "purple": return .purple
            case "red": return .red
            default: return .gray
            }
        }
    }
}

private extension CGFloat {
    var clampedToZero: CGFloat { Swift.max(0, self) }
}

extension View {
    /// Reimplements Apollo's real progressive, breakpoint-driven swipe
    /// gesture (see `ProgressiveSwipeRowModifier`'s doc comment).
    public func apolloSwipeActions(
        settings: SwipeActionSettings,
        subject: SwipeSubject? = nil,
        onAction: @escaping (SwipeAction) -> Void
    ) -> some View {
        modifier(ProgressiveSwipeRowModifier(settings: settings, subject: subject, onAction: onAction))
    }
}

/// The post, comment or message a row's swipe actions apply to, so
/// each action can show whether it would do or undo.
public struct SwipeSubject {
    let fullname: String
    let likes: Bool?
    let saved: Bool
    /// Nil for anything that isn't an inbox message.
    let unread: Bool?

    public init(fullname: String, likes: Bool? = nil, saved: Bool = false, unread: Bool? = nil) {
        self.fullname = fullname
        self.likes = likes
        self.saved = saved
        self.unread = unread
    }

    public init(post: RedditPost) {
        self.init(fullname: post.name, likes: post.likes, saved: post.saved)
    }

    public init(comment: RedditComment) {
        self.init(fullname: comment.name, likes: comment.likes, saved: comment.saved)
    }
}
