import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit

/// Browser-style forward navigation, as in Apollo: a pop is remembered,
/// and a forward swipe re-pushes it.
///
/// SwiftUI's `NavigationStack` keeps its destinations in bindings, not
/// view controllers that could be re-pushed, so every pushed screen is
/// driven by a binding (`navigationDestination(item:)` or a path); a
/// pop is that binding going non-nil to nil, which is recorded here and
/// re-applied by a forward swipe.
@MainActor
public final class ForwardNavigationStore: ObservableObject {
    public static let shared = ForwardNavigationStore()

    /// The most recently popped destination, newest first. Bounded, since
    /// holding navigation state forever is not free.
    /// `isLive` is false once the screen that owns the binding is gone:
    /// a pop through several levels destroys the intermediate screens,
    /// and a later forward swipe re-creates them fresh, so an entry
    /// restoring a deeper page would write into the dead instance's
    /// state and push nothing.
    private struct Entry {
        let isLive: () -> Bool
        let restore: () -> Void
    }
    /// Per tab: each tab has its own stack, and switching tabs and back
    /// keeps where you could go forward to.
    private var entriesByTab: [Int: [Entry]] = [:]
    private var entries: [Entry] {
        get { entriesByTab[currentTab] ?? [] }
        set { entriesByTab[currentTab] = newValue }
    }
    private static let maximumEntries = 10

    private init() {}

    public var canGoForward: Bool {
        guard let next = entries.first else { return false }
        if next.isLive() { return true }
        // The rest are deeper still, and just as unreachable.
        entries.removeAll()
        return false
    }

    /// The selected tab, set by the tab bar.
    public var currentTab = 0

    /// Records a pop. `restore` re-applies the destination that was
    /// just cleared.
    public func recordPop(isLive: @escaping () -> Bool = { true }, _ restore: @escaping () -> Void) {
        entries.insert(Entry(isLive: isLive, restore: restore), at: 0)
        if entries.count > Self.maximumEntries {
            entries.removeLast(entries.count - Self.maximumEntries)
        }
    }

    /// Invalidated by a new push.
    public func recordPush() {
        guard !isConsuming else { return }
        entries.removeAll()
    }

    /// Drops the current tab's forward stack (a pop to its root).
    public func clearCurrentTab() {
        entries.removeAll()
    }

    private var isConsuming = false

    /// Re-applies the most recently popped destination. SwiftUI pushes it
    /// animated, which the page swipe makes interactive.
    public func goForward() {
        guard canGoForward else { return }
        let restore = entries.removeFirst().restore
        isConsuming = true
        restore()
        // Cleared on the next runloop turn, after the resulting push
        // has been recorded, so consuming a forward entry does not wipe
        // the rest of the history.
        DispatchQueue.main.async { self.isConsuming = false }
    }
}

/// Tracks one `navigationDestination(item:)` binding and feeds the
/// forward stack.
private struct ForwardNavigationTracker<Item: Equatable>: ViewModifier {
    @Binding var item: Item?
    @State private var previous: Item?
    /// Lives exactly as long as this screen's state, so a forward entry
    /// knows when the screen that would re-push it is gone.
    private final class Token {}
    @State private var token = Token()

    func body(content: Content) -> some View {
        content
        .onChange(of: item) { _, newValue in
            // Nothing pushes while a back swipe is taking this screen
            // away (a link under the finger as it lifts, on iOS 27).
            if newValue != nil, previous == nil, PageSwipeController.isActive,
               PageSwipeController.activeIsBack {
                item = nil
                return
            }
            if let cleared = previous, newValue == nil {
                // non-nil -> nil is a pop.
                ForwardNavigationStore.shared.recordPop(isLive: { [weak token] in token != nil }) { item = cleared }
            } else if newValue != nil, previous == nil {
                ForwardNavigationStore.shared.recordPush()
            }
            previous = newValue
        }
    }
}

public extension View {
    /// Feeds a `navigationDestination(item:)` binding into the
    /// browser-style forward stack, so swiping back from the pushed
    /// screen can be undone by a forward swipe.
    func apolloTracksForwardNavigation<Item: Equatable>(_ item: Binding<Item?>) -> some View {
        modifier(ForwardNavigationTracker(item: item))
    }

    /// The same for a `navigationDestination(isPresented:)` flag.
    func apolloTracksForwardNavigation(_ isPresented: Binding<Bool>) -> some View {
        apolloTracksForwardNavigation(Binding<Bool?>(
            get: { isPresented.wrappedValue ? true : nil },
            set: { isPresented.wrappedValue = $0 == true }
        ))
    }

    /// Apollo's back and forward page swipes on the stack this screen is
    /// in. See `PageSwipeController`.
    func apolloForwardSwipe() -> some View {
        background(PageSwipeInstaller().frame(width: 0, height: 0))
    }
}

#else
public extension View {
    func apolloTracksForwardNavigation<Item: Equatable>(_ item: Binding<Item?>) -> some View { self }
    func apolloTracksForwardNavigation(_ isPresented: Binding<Bool>) -> some View { self }
    func apolloForwardSwipe() -> some View { self }
}
#endif
