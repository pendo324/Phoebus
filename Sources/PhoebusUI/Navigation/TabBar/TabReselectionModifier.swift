import SwiftUI
import ObjectiveC
import PhoebusCore

/// Clears one item-driven `navigationDestination` when its tab is
/// re-tapped, so the tab pops all the way back to its root.
///
/// Stacks here are several independent `navigationDestination(item:)`
/// bindings rather than one `NavigationPath`, so every pushed screen clears
/// its own destination on the same notification, unwinding leaf to root.
private struct TabReselectionClearsDestination<Item>: ViewModifier {
    let tab: Int
    @Binding var item: Item?

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .apolloTabReselected)
        ) { note in
            guard note.userInfo?["tab"] as? Int == tab else { return }
            // The Posts tab (0) goes back ONE page per re-tap, driven
            // by `TabReselectionScrollsThenPops` (Reborn #1153), so
            // item-driven screens there must not also clear themselves.
            guard tab != 0 else { return }
            item = nil
        }
    }
}

private struct TabReselectionClearsFlag: ViewModifier {
    let tab: Int
    @Binding var flag: Bool

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .apolloTabReselected)
        ) { note in
            guard note.userInfo?["tab"] as? Int == tab else { return }
            guard tab != 0 else { return }
            flag = false
        }
    }
}

/// Empties a `NavigationStack`'s path when its tab is re-tapped, for
/// stacks driven by plain `NavigationLink`s (Settings, Inbox, Profile)
/// which own no `navigationDestination(item:)` binding to clear.
private struct TabReselectionClearsPath: ViewModifier {
    let tab: Int
    @Binding var path: NavigationPath

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .apolloTabReselected)
        ) { note in
            guard note.userInfo?["tab"] as? Int == tab else { return }
            guard !path.isEmpty else { return }
            path = NavigationPath()
        }
    }
}

/// Pops the real `UINavigationController` when its tab is re-tapped
/// (e.g. Settings). A `NavigationPath` only pops what was pushed
/// through it via `NavigationLink(value:)`; plain `NavigationLink {
/// destination }` pushes stay outside the path, so reaching the
/// underlying `UINavigationController` is required instead.
private struct TabReselectionPopsNavigationController: UIViewRepresentable {
    let tab: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.observe(view: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }

    @MainActor
    final class Coordinator {
        let tab: Int
        private weak var host: UIView?
        private var token: NSObjectProtocol?

        nonisolated init(tab: Int) { self.tab = tab }

        func observe(view: UIView) {
            host = view
            guard token == nil else { return }
            let tab = self.tab
            token = NotificationCenter.default.addObserver(
                forName: .apolloTabReselected, object: nil, queue: .main
            ) { [weak self] note in
                guard note.userInfo?["tab"] as? Int == tab else { return }
                // The observer block is nonisolated but this queue IS
                // the main one, so the hop is an assertion rather than
                // a dispatch.
                MainActor.assumeIsolated {
                    guard let controller = self?.host?.owningViewController()?.navigationController,
                          controller.viewControllers.count > 1 else { return }
                    controller.popToRootViewController(animated: true)
                }
            }
        }

        // No `deinit` teardown: the observer captures `self` weakly
        // and the block no-ops once the view is gone, so an orphaned
        // registration is harmless. A `deinit` cannot touch `token`
        // here anyway - it is nonisolated while the property is
        // main-actor-isolated.
    }
}

/// Reborn #1153, "Fix Posts tab to scroll before navigating back":
/// re-tapping Posts first scrolls the visible screen's content list to
/// the top; only a re-tap while already at the top goes back, one page.
private struct TabReselectionScrollsThenPops: UIViewRepresentable {
    let tab: Int
    /// Search tab (Reborn #1190): at the root, a re-tap scrolls to
    /// the top and the next re-tap focuses the search field instead of popping.
    var focusesSearchAtRoot = false

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.observe(view: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab, focusesSearchAtRoot: focusesSearchAtRoot) }

    @MainActor
    final class Coordinator {
        let tab: Int
        let focusesSearchAtRoot: Bool
        private weak var host: UIView?
        private var token: NSObjectProtocol?

        nonisolated init(tab: Int, focusesSearchAtRoot: Bool = false) {
            self.tab = tab
            self.focusesSearchAtRoot = focusesSearchAtRoot
        }

        func observe(view: UIView) {
            host = view
            guard token == nil else { return }
            let tab = self.tab
            token = NotificationCenter.default.addObserver(
                forName: .apolloTabReselected, object: nil, queue: .main
            ) { [weak self] note in
                guard note.userInfo?["tab"] as? Int == tab else { return }
                MainActor.assumeIsolated { self?.handle() }
            }
            // Install the veto as soon as the bar exists, so even the
            // first re-tap cannot pop to root.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let window = self.host?.window,
                      let tabs = Self.tabBarController(in: window.rootViewController) else { return }
                ReselectVeto.install(on: tabs, tab: tab, rootOnly: self.focusesSearchAtRoot)
            }
        }

        private func handle() {
            // Resolved from the app's key window, not this probe's own
            // responder chain: the probe sits on the stack's root
            // screen, which a push removes from the window.
            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
            guard let window = host?.window ?? keyWindow,
                  let tabs = Self.tabBarController(in: window.rootViewController),
                  // Installing here is too late to stop UIKit's own
                  // pop-to-root for THIS tap; it takes effect next tap.
                  ReselectVeto.install(on: tabs, tab: tab, rootOnly: focusesSearchAtRoot),
                  let selected = tabs.selectedViewController,
                  let nav = Self.stackNavigationController(under: selected) ?? (selected as? UINavigationController),
                  nav.presentedViewController == nil, tabs.presentedViewController == nil,
                  let top = nav.topViewController, let content = top.viewIfLoaded, content.window != nil else { return }
            // Search with a feed pushed: UIKit pops to root (not vetoed).
            if focusesSearchAtRoot && nav.viewControllers.count > 1 { return }
            let viewport = content.convert(content.bounds, to: nil)
            if let scroll = Self.contentScrollView(in: content, viewport: viewport) {
                let topOffset = -scroll.adjustedContentInset.top
                if scroll.contentOffset.y > topOffset + 1 {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: topOffset),
                                            animated: !UIAccessibility.isReduceMotionEnabled)
                    // A lazy SwiftUI List re-estimates row heights as
                    // rows scroll in, which can leave one animated
                    // scroll short of the top. Settle once it ends.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak scroll] in
                        guard let scroll, !scroll.isDragging else { return }
                        let settledTop = -scroll.adjustedContentInset.top
                        if scroll.contentOffset.y > settledTop + 1 {
                            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: settledTop), animated: false)
                        }
                    }
                    return
                }
            }
            if nav.viewControllers.count > 1 {
                nav.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
            } else if focusesSearchAtRoot, let field = Self.searchField(in: nav.view) {
                // Already at the top of the Search root: focus the
                // field, matching Reborn #1190.
                field.becomeFirstResponder()
            }
        }

        /// The navigation bar's search field (`.searchable`'s
        /// `UISearchTextField`), searched breadth-first under the stack.
        static func searchField(in root: UIView) -> UISearchTextField? {
            UIKitTree.firstDescendant(of: UISearchTextField.self, in: root) { $0.window != nil && !$0.isHidden }
        }

        /// Vetoes `UITabBarController`'s own pop-to-root on re-tap by
        /// returning NO from `shouldSelectViewController`, matching
        /// Reborn. Wraps SwiftUI's own delegate, forwarding everything
        /// else untouched.
        final class ReselectVeto: NSObject, UITabBarControllerDelegate {
            weak var inner: UITabBarControllerDelegate?
            /// Every tab whose re-tap this app handles itself (Posts,
            /// and Search for #1190).
            var tabs: Set<Int>
            var rootOnlyTabs: Set<Int> = []
            init(inner: UITabBarControllerDelegate?, tab: Int) { self.inner = inner; self.tabs = [tab] }

            nonisolated(unsafe) static var key: UInt8 = 0

            @discardableResult
            static func install(on tabs: UITabBarController, tab: Int, rootOnly: Bool = false) -> Bool {
                if let existing = tabs.delegate as? ReselectVeto {
                    existing.tabs.insert(tab)
                    if rootOnly { existing.rootOnlyTabs.insert(tab) }
                    return true
                }
                let veto = ReselectVeto(inner: tabs.delegate, tab: tab)
                if rootOnly { veto.rootOnlyTabs.insert(tab) }
                objc_setAssociatedObject(tabs, &key, veto, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                tabs.delegate = veto
                return true
            }

            func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
                if viewController === tabBarController.selectedViewController,
                   tabs.contains(tabBarController.selectedIndex),
                   // Search (#1190) only takes over at its ROOT; a
                   // pushed feed still pops to root the stock way (the
                   // SwiftUI clear-destination modifiers handle it).
                   !(rootOnlyTabs.contains(tabBarController.selectedIndex)
                     && (Coordinator.stackNavigationController(under: viewController)
                         ?? (viewController as? UINavigationController))
                        .map { $0.viewControllers.count > 1 } ?? false) {
                    // SwiftUI never learns of a vetoed tap, so post the
                    // re-selection ourselves.
                    NotificationCenter.default.post(name: .apolloTabReselected, object: nil,
                                                    userInfo: ["tab": tabBarController.selectedIndex])
                    return false
                }
                return inner?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
            }

            override func responds(to aSelector: Selector!) -> Bool {
                super.responds(to: aSelector) || (inner?.responds(to: aSelector) ?? false)
            }

            override func forwardingTarget(for aSelector: Selector!) -> Any? {
                inner?.responds(to: aSelector) == true ? inner : nil
            }
        }

        static func tabBarController(in root: UIViewController?) -> UITabBarController? {
            guard let root else { return nil }
            if let tabs = root as? UITabBarController { return tabs }
            for child in root.children {
                if let found = tabBarController(in: child) { return found }
            }
            return nil
        }

        /// The deepest on-screen navigation controller below `root`.
        static func stackNavigationController(under root: UIViewController) -> UINavigationController? {
            for child in root.children {
                if let found = stackNavigationController(under: child) { return found }
            }
            if let nav = root as? UINavigationController, nav.viewIfLoaded?.window != nil { return nav }
            return nil
        }

        /// The Posts tab's content scroll view: the largest visible, vertically
        /// scrollable list, ignoring horizontal carousels and stopping at the outer
        /// list so an embedded view cannot win.
        static func contentScrollView(in view: UIView, viewport: CGRect) -> UIScrollView? {
            guard !view.isHidden, view.alpha >= 0.01, view.window != nil else { return nil }
            let visible = view.convert(view.bounds, to: nil).intersection(viewport)
            guard !visible.isNull, !visible.isEmpty else { return nil }
            if let scroll = view as? UIScrollView {
                let isList = scroll is UITableView || scroll is UICollectionView
                let vertical = scroll.contentSize.height + scroll.adjustedContentInset.top
                    + scroll.adjustedContentInset.bottom > scroll.bounds.height + 1
                if scroll.isScrollEnabled && (vertical || (isList && scroll.alwaysBounceVertical)) { return scroll }
            }
            var best: UIScrollView?
            var bestArea: CGFloat = 0
            for child in view.subviews {
                guard let candidate = contentScrollView(in: child, viewport: viewport) else { continue }
                let frame = candidate.convert(candidate.bounds, to: nil).intersection(viewport)
                let area = frame.width * frame.height
                if area > bestArea { best = candidate; bestArea = area }
            }
            return best
        }
    }
}

extension View {
    /// Pops this tab's whole stack on re-tap, whatever pushed it.
    /// Zero-sized and non-interactive; only exists to reach the UIKit
    /// hierarchy. Attach inside the `NavigationStack`, on its root
    /// content, not on the stack itself, or there is no navigationController
    /// to pop. Reborn #1153: scroll to top first, then back one page.
    public func apolloScrollsThenPopsOnTabReselection(tab: Int, focusesSearchAtRoot: Bool = false) -> some View {
        background(
            TabReselectionScrollsThenPops(tab: tab, focusesSearchAtRoot: focusesSearchAtRoot)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true))
    }

    public func apolloPopsToRootOnTabReselection(tab: Int) -> some View {
        background(
            TabReselectionPopsNavigationController(tab: tab)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true))
    }

    /// Pops this tab's whole `NavigationStack` when `tab` is re-tapped.
    public func apolloPopsOnTabReselection(
        tab: Int, path: Binding<NavigationPath>
    ) -> some View {
        modifier(TabReselectionClearsPath(tab: tab, path: path))
    }

    /// Pops this screen when `tab` is re-tapped, by clearing the
    /// `navigationDestination(item:)` binding that pushed whatever sits
    /// above it.
    public func apolloPopsOnTabReselection<Item>(
        tab: Int = 0, item: Binding<Item?>
    ) -> some View {
        modifier(TabReselectionClearsDestination(tab: tab, item: item))
    }

    /// `isPresented:`-driven variant of the above.
    public func apolloPopsOnTabReselection(
        tab: Int = 0, isPresented: Binding<Bool>
    ) -> some View {
        modifier(TabReselectionClearsFlag(tab: tab, flag: isPresented))
    }
}
