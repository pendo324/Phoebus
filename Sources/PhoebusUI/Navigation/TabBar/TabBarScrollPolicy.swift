import SwiftUI
import Combine
import PhoebusCore

/// Reborn's "Scroll Behavior" for Hide Bars on Scroll: Classic collapses on
/// the very next downward gesture; Two-Gesture, after the bars reappear, lets
/// the first downward gesture go by and collapses on the second. Both
/// re-expand after 30 seconds without scrolling.
///
/// It turns the raw direction samples into `.apolloBarsShouldHide` / `Show`
/// (for the Fade/Down styles and Hide Header on Scroll) and, for the native
/// Left/Right minimize, holds the tab bar expanded with `.never` while a
/// gesture is being let go by, as Reborn does: switching that policy also
/// makes UIKit expand the bar.
@MainActor
final class TabBarScrollPolicy: ObservableObject {
    static let idleRevealDelay: TimeInterval = 30

    /// While true the native minimize behavior is `.never`.
    @Published private(set) var holdExpanded = false
    var classic = false

    private(set) var hidden = false
    /// After a Two-Gesture reveal: the next downward gesture is let go by.
    private var consumeNext = false
    private var gestureConsumed = false
    private var gestureWentDown = false
    private var gestureActive = false
    private var holdAfterGesture = false
    private var idleTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ action: @escaping @MainActor (TabBarScrollPolicy) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { action(self) } }
            })
        }
        observe(.apolloScrollGestureBegan) { $0.gestureBegan() }
        observe(.apolloScrollGestureEnded) { $0.gestureEnded() }
        observe(.apolloScrollDidScrollDown) { $0.scrolledDown() }
        observe(.apolloScrollDidScrollUp) { $0.scrolledUp() }
    }

    func gestureBegan() {
        gestureActive = true
        idleTimer?.invalidate()
        gestureConsumed = !classic && consumeNext
        gestureWentDown = false
        // A gesture that may collapse runs under the normal policy.
        if !gestureConsumed, holdExpanded { holdExpanded = false }
    }

    func gestureEnded() {
        gestureActive = false
        if gestureConsumed, gestureWentDown { consumeNext = false }
        if holdAfterGesture {
            holdAfterGesture = false
            holdExpanded = true
        }
        scheduleIdleReveal()
    }

    func scrolledDown() {
        gestureWentDown = true
        guard !gestureConsumed, !hidden else { return }
        hidden = true
        NotificationCenter.default.post(name: .apolloBarsShouldHide, object: nil)
        if !gestureActive { scheduleIdleReveal() }
    }

    func scrolledUp() {
        guard hidden else { return }
        reveal()
        // UIKit is already expanding the bar; the hold goes on once the
        // gesture ends, so the switch doesn't snap mid-animation.
        if !classic { holdAfterGesture = true }
    }

    private func reveal() {
        hidden = false
        idleTimer?.invalidate()
        if !classic { consumeNext = true }
        NotificationCenter.default.post(name: .apolloBarsShouldShow, object: nil)
    }

    private func scheduleIdleReveal() {
        idleTimer?.invalidate()
        guard hidden else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleRevealDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.idleReveal() }
        }
    }

    private func idleReveal() {
        guard hidden, !gestureActive else { return }
        reveal()
        // `.never` is the only public way to expand UIKit's minimized bar.
        holdExpanded = true
        if classic {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !self.hidden, self.classic else { return }
                self.holdExpanded = false
            }
        }
    }
}

extension Notification.Name {
    /// A finger started / stopped dragging a participating scroll view.
    static let apolloScrollGestureBegan = Notification.Name("ApolloScrollGestureBegan")
    static let apolloScrollGestureEnded = Notification.Name("ApolloScrollGestureEnded")
    /// `TabBarScrollPolicy`'s decisions, for the bars it doesn't drive natively.
    static let apolloBarsShouldHide = Notification.Name("ApolloBarsShouldHide")
    static let apolloBarsShouldShow = Notification.Name("ApolloBarsShouldShow")
}
