import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
import OSLog

/// Apollo's back and forward page swipes, as a real interactive
/// transition of the navigation controller under a SwiftUI
/// `NavigationStack`.
///
/// Apollo uses its own pan instead of UIKit's pop gesture (see
/// `PushPopGesturePolicy` for its start zones and thresholds). This pan pops
/// (or, going forward, re-pushes the last popped screen through SwiftUI) with
/// `animated: true`; the navigation controller's delegate supplies Apollo's
/// slide as the animation and the finger as its progress. Both screens stay
/// live views, the navigation bar animates with them, and a cancelled swipe
/// is UIKit's own cancelled transition.
///
/// SwiftUI is the navigation controller's delegate and relies on its
/// callbacks, so this stands in front of it only for the length of a swipe
/// and forwards everything it does not handle.
@MainActor
final class PageSwipeController: NSObject, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    private weak var navigationController: UINavigationController?
    private let pan = UIPanGestureRecognizer()

    /// The swipe currently driving a transition, app-wide.
    private(set) static weak var active: PageSwipeController?

    /// A page swipe owns the screen, from its first movement until the
    /// navigation has settled.
    static var isActive: Bool { active != nil }
    static var activeIsBack: Bool { active?.isBack ?? false }

    private var isBack = true
    private var lastMovement: (x: Double, time: CFTimeInterval) = (0, 0)
    private var interaction: PageSwipeInteraction?
    private var animator: PageSwipeAnimator?
    private weak var forwardedDelegate: UINavigationControllerDelegate?
    private let scrollLock = ScrollLock()
    /// Ends a swipe whose transition never started (a forward entry
    /// that turned out not to push anything).
    private var watchdog: DispatchWorkItem?

    private static var key: UInt8 = 0

    /// Gives a navigation controller Apollo's page swipes, once.
    static func install(on navigationController: UINavigationController) {
        TransitionStallMonitor.start()
        navigationController.apolloDisableSystemPopGestures()
        guard objc_getAssociatedObject(navigationController, &key) == nil else { return }
        let controller = PageSwipeController(navigationController: navigationController)
        objc_setAssociatedObject(navigationController, &key, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        super.init()
        pan.addTarget(self, action: #selector(panned(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        // A page swipe takes the touch from whatever is under it, so a
        // row or link under the finger cannot fire as it lifts.
        pan.cancelsTouchesInView = true
        navigationController.view.addGestureRecognizer(pan)
    }

    // MARK: - What can happen

    /// Whether the visible stack has a screen to go back to.
    static var canGoBack: Bool {
        (UIKitTree.keyWindow?.rootViewController?.apolloTopNavigationController()?.viewControllers.count ?? 0) > 1
    }

    /// The controller for the stack on screen, for a swipe that starts
    /// outside it (the tab bar).
    static var forVisibleStack: PageSwipeController? {
        guard let navigation = UIKitTree.keyWindow?.rootViewController?.apolloTopNavigationController() else { return nil }
        install(on: navigation)
        return objc_getAssociatedObject(navigation, &key) as? PageSwipeController
    }

    static var isSwipeActive: Bool { active != nil }

    func canBegin(back: Bool) -> Bool {
        guard let navigationController, Self.active == nil,
              navigationController.transitionCoordinator == nil,
              NavigationGestureSettingsStore.load().pushPopSwipeGesturesEnabled,
              !InfoRowHoldRecognizer.isHolding else { return false }
        return back ? navigationController.viewControllers.count > 1 : ForwardNavigationStore.shared.canGoForward
    }

    // MARK: - The pan

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, let view = navigationController?.view else { return false }
        let velocity = pan.velocity(in: view)
        let translation = pan.translation(in: view)
        let start = CGPoint(x: pan.location(in: view).x - translation.x, y: pan.location(in: view).y - translation.y)
        let startInWindow = view.convert(start, to: nil)
        guard !PushPopGesturePolicy.verticallyCommitted(translationX: Double(translation.x),
                                                        translationY: Double(translation.y)),
              !ScrollGestureExclusivity.isScrolling(atWindowPoint: startInWindow),
              !Self.startsOnSlider(startInWindow, in: view.window),
              Self.innermostNavigationController(at: startInWindow, in: view.window) === navigationController
        else { return false }
        if PushPopGesturePolicy.shouldBeginBack(velocityX: Double(velocity.x), velocityY: Double(velocity.y),
                                                locationX: Double(start.x)), canBegin(back: true) {
            isBack = true
            return true
        }
        if PushPopGesturePolicy.shouldBeginForward(velocityX: Double(velocity.x), velocityY: Double(velocity.y),
                                                   locationX: Double(start.x), viewWidth: Double(view.bounds.width)),
           canBegin(back: false) {
            isBack = false
            return true
        }
        return false
    }

    /// Lists and rows keep their own recognizers; the arbiter and the
    /// scroll lock decide who moves.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let width = Double(pan.view?.bounds.width ?? UIScreen.main.bounds.width)
        let dx = Double(pan.translation(in: pan.view).x)
        switch pan.state {
        case .began:
            lastMovement = (dx, CACurrentMediaTime())
            begin(back: isBack)
        case .changed:
            if dx != lastMovement.x { lastMovement = (dx, CACurrentMediaTime()) }
            update(translationX: dx, width: width)
        case .ended:
            // A finger that stopped before lifting has no velocity, even
            // though the recognizer still reports its last movement's.
            let resting = CACurrentMediaTime() - lastMovement.time > 0.1
            end(translationX: dx, velocityX: resting ? 0 : Double(pan.velocity(in: pan.view).x), width: width)
        default:
            end(complete: false)
        }
    }

    // MARK: - Driving the transition (also used by the tab bar's swipe)

    /// The drag must actually travel, so a twitch at the edge doesn't
    /// navigate.
    private static let minimumTravel: Double = 40

    func begin(back: Bool) {
        guard let navigationController else { return }
        pageSwipeLog.notice("begin \(back ? "back" : "forward", privacy: .public) depth=\(navigationController.viewControllers.count)")
        isBack = back
        Self.active = self
        if navigationController.delegate !== self {
            forwardedDelegate = navigationController.delegate
            navigationController.delegate = self
        }
        interaction = PageSwipeInteraction()
        animator = PageSwipeAnimator(isBack: back)
        // Nothing scrolls under a page swipe.
        scrollLock.lock(UIKitTree.scrollViews(in: navigationController.view))
        if back {
            navigationController.popViewController(animated: true)
        } else {
            // Re-applies the popped destination through SwiftUI, which
            // pushes it animated; the delegate below makes that push
            // interactive.
            ForwardNavigationStore.shared.goForward()
        }
    }

    func update(translationX: Double, width: Double) {
        // Only travel in the swipe's own direction opens the page: a
        // finger dragged back past where it started holds it closed
        // rather than opening it again.
        let travel = max(0, isBack ? translationX : -translationX)
        interaction?.setProgress(CGFloat(PushPopGesturePolicy.transitionProgress(translationX: travel,
                                                                               viewWidth: width)))
    }

    func end(translationX: Double, velocityX: Double, width: Double) {
        let complete = PushPopGesturePolicy.shouldComplete(translationX: translationX, velocityX: velocityX,
                                                           viewWidth: width, isForward: !isBack)
            && (isBack ? translationX > Self.minimumTravel : translationX < -Self.minimumTravel)
        end(complete: complete)
    }

    func end(complete: Bool) {
        guard let interaction else { return }
        pageSwipeLog.notice("end complete=\(complete) started=\(interaction.hasStarted)")
        interaction.end(complete: complete)
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.interaction === interaction else { return }
            if !interaction.hasStarted {
                // The push or pop never came.
                pageSwipeLog.notice("swipe ended without a transition; releasing")
                self.finished()
            } else if let animator = self.animator, animator.isStillRunning {
                // UIKit started the transition but it never finished: left
                // like this, the stack ignores every push and pop after it
                // while the screen still looks alive.
                pageSwipeLog.error("transition stuck after the finger lifted; forcing it to \(complete ? "finish" : "cancel", privacy: .public)")
                animator.forceEnd(complete: complete)
            }
        }
        self.watchdog?.cancel()
        self.watchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: watchdog)
    }

    private func finished() {
        pageSwipeLog.notice("finished")
        watchdog?.cancel()
        watchdog = nil
        scrollLock.release()
        interaction = nil
        animator = nil
        if let navigationController, navigationController.delegate === self {
            navigationController.delegate = forwardedDelegate
        }
        forwardedDelegate = nil
        if Self.active === self { Self.active = nil }
    }

    // MARK: - UINavigationControllerDelegate

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController,
                              to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if let animator, operation == (isBack ? .pop : .push) {
            animator.onComplete = { [weak self] in self?.finished() }
            return animator
        }
        return forwardedDelegate?.navigationController?(navigationController, animationControllerFor: operation,
                                                        from: fromVC, to: toVC)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning)
        -> UIViewControllerInteractiveTransitioning? {
        if animationController === animator { return interaction }
        return forwardedDelegate?.navigationController?(navigationController,
                                                        interactionControllerFor: animationController)
    }

    func navigationController(_ navigationController: UINavigationController,
                              willShow viewController: UIViewController, animated: Bool) {
        forwardedDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
    }

    func navigationController(_ navigationController: UINavigationController,
                              didShow viewController: UIViewController, animated: Bool) {
        forwardedDelegate?.navigationController?(navigationController, didShow: viewController, animated: animated)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (forwardedDelegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if let forwardedDelegate, forwardedDelegate.responds(to: selector) { return forwardedDelegate }
        return super.forwardingTarget(for: selector)
    }

    // MARK: - Hit testing

    /// A drag that starts on a slider belongs to the slider.
    private static func startsOnSlider(_ point: CGPoint, in window: UIWindow?) -> Bool {
        var view = window?.hitTest(point, with: nil)
        while let current = view {
            if current is UISlider { return true }
            view = current.superview
        }
        return false
    }

    /// The stack whose screen is under the finger: a stack nested in
    /// another's screen swipes on its own, not its parent's.
    private static func innermostNavigationController(at point: CGPoint, in window: UIWindow?) -> UINavigationController? {
        var view = window?.hitTest(point, with: nil)
        while let current = view {
            if let navigation = (current.next as? UIViewController)?.navigationController
                ?? (current.next as? UINavigationController) {
                return navigation
            }
            view = current.superview
        }
        return nil
    }
}

let pageSwipeLog = Logger(subsystem: "com.pendo324.Phoebus", category: "PageSwipe")

/// Records a navigation transition that never ends, which leaves the app
/// looking alive while every push and pop is ignored. For Export Debug Logs.
@MainActor
private enum TransitionStallMonitor {
    private static var timer: Timer?
    private static var stalledTicks = 0

    static func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
    }

    private static func tick() {
        guard let navigation = UIKitTree.keyWindow?.rootViewController?.apolloTopNavigationController(),
              navigation.transitionCoordinator != nil else {
            stalledTicks = 0
            return
        }
        stalledTicks += 1
        if stalledTicks == 3 {
            let stack = navigation.viewControllers.map { String(describing: type(of: $0)) }.joined(separator: " > ")
            pageSwipeLog.error("navigation transition running for 3 s (swipe active: \(PageSwipeController.isSwipeActive)); stack: \(stack, privacy: .public)")
        }
    }
}

/// The finger's progress, buffered until UIKit starts the transition: a
/// forward swipe's push reaches UIKit on SwiftUI's next update, after
/// the drag has already moved.
private final class PageSwipeInteraction: UIPercentDrivenInteractiveTransition {
    private(set) var hasStarted = false
    private var progress: CGFloat = 0
    private var pendingEnd: Bool?

    override init() {
        super.init()
        completionCurve = .easeOut
    }

    override func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        super.startInteractiveTransition(transitionContext)
        hasStarted = true
        update(progress)
        if let complete = pendingEnd { complete ? finish() : cancel() }
    }

    func setProgress(_ value: CGFloat) {
        // Kept just inside the ends: UIKit does not apply an update to exactly 0,
        // which would leave the page partly open.
        progress = min(max(value, 0.001), 0.999)
        if hasStarted, pendingEnd == nil { update(progress) }
    }

    func end(complete: Bool) {
        guard pendingEnd == nil else { return }
        pendingEnd = complete
        if hasStarted { complete ? finish() : cancel() }
    }
}

/// Apollo's page slide: the page on top travels the full width with a
/// soft shadow on its leading edge, the page under it sits a third of a
/// screen behind and catches up.
private final class PageSwipeAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isBack: Bool
    var onComplete: (() -> Void)?

    private static let parallax: CGFloat = 0.3

    init(isBack: Bool) {
        self.isBack = isBack
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.35
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: transitionContext).startAnimation()
    }

    private var propertyAnimator: UIViewPropertyAnimator?
    private var context: UIViewControllerContextTransitioning?

    /// The transition started and hasn't completed.
    var isStillRunning: Bool { propertyAnimator != nil }

    /// Ends a transition UIKit left hanging, to the side the finger chose.
    func forceEnd(complete: Bool) {
        guard let propertyAnimator, let context else { return }
        if complete { context.finishInteractiveTransition() } else { context.cancelInteractiveTransition() }
        if propertyAnimator.state == .active { propertyAnimator.stopAnimation(false) }
        if propertyAnimator.state == .stopped {
            propertyAnimator.finishAnimation(at: complete ? .end : .start)
        }
    }

    /// A property animator rather than a plain `UIView.animate`: the
    /// percent-driven interaction scrubs it by `fractionComplete`, and UIKit adds
    /// the navigation bar's own transition (title and buttons fading across) to
    /// the same animator, so the bar follows the finger too.
    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning)
        -> UIViewImplicitlyAnimating {
        if let propertyAnimator { return propertyAnimator }
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), curve: .linear)
        propertyAnimator = animator
        context = transitionContext
        guard let fromVC = transitionContext.viewController(forKey: .from),
              let toVC = transitionContext.viewController(forKey: .to),
              let fromView = transitionContext.view(forKey: .from) ?? fromVC.view,
              let toView = transitionContext.view(forKey: .to) ?? toVC.view else {
            animator.addCompletion { _ in transitionContext.completeTransition(false) }
            return animator
        }
        let container = transitionContext.containerView
        let width = container.bounds.width
        toView.frame = transitionContext.finalFrame(for: toVC)
        let top: UIView
        if isBack {
            container.insertSubview(toView, belowSubview: fromView)
            toView.transform = CGAffineTransform(translationX: -width * Self.parallax, y: 0)
            top = fromView
        } else {
            container.addSubview(toView)
            toView.transform = CGAffineTransform(translationX: width, y: 0)
            top = toView
        }
        let savedShadow = (top.layer.shadowOpacity, top.layer.shadowRadius, top.layer.shadowOffset, top.layer.shadowColor)
        top.layer.shadowColor = UIColor.black.cgColor
        top.layer.shadowOpacity = 0.35
        top.layer.shadowRadius = 8
        top.layer.shadowOffset = CGSize(width: -4, height: 0)

        let isBack = self.isBack
        animator.addAnimations {
            if isBack {
                fromView.transform = CGAffineTransform(translationX: width, y: 0)
                toView.transform = .identity
            } else {
                toView.transform = .identity
                fromView.transform = CGAffineTransform(translationX: -width * Self.parallax, y: 0)
            }
        }
        animator.addCompletion { [weak self] _ in
            fromView.transform = .identity
            toView.transform = .identity
            (top.layer.shadowOpacity, top.layer.shadowRadius, top.layer.shadowOffset, top.layer.shadowColor) = savedShadow
            let cancelled = transitionContext.transitionWasCancelled
            if cancelled { toView.removeFromSuperview() }
            transitionContext.completeTransition(!cancelled)
            self?.propertyAnimator = nil
            self?.context = nil
            self?.onComplete?()
        }
        return animator
    }

    func animationEnded(_ transitionCompleted: Bool) {
        propertyAnimator = nil
        context = nil
    }
}

extension UIViewController {
    /// The navigation controller actually presenting content, found by
    /// descending through tab bars and presented controllers rather
    /// than assuming the root is one.
    func apolloTopNavigationController() -> UINavigationController? {
        if let presented = presentedViewController {
            return presented.apolloTopNavigationController()
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.apolloTopNavigationController()
        }
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.apolloTopNavigationController() ?? navigation
        }
        for child in children {
            if let found = child.apolloTopNavigationController() { return found }
        }
        return nil
    }
}

/// Installs the page swipes on whatever navigation controller the view
/// sits in, and keeps UIKit's own pop gestures off there.
struct PageSwipeInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        probe.isHidden = true
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Deferred: the probe is not yet in its final place in the UIKit
        // hierarchy at `updateUIView` time.
        DispatchQueue.main.async {
            guard let navigation = uiView.owningViewController()?.navigationController else { return }
            PageSwipeController.install(on: navigation)
        }
    }
}
#endif
