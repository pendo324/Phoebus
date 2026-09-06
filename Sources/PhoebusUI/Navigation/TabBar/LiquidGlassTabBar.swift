import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// The app's five-tab bar. A real system `TabView`, which on iOS 26 is
/// Apollo-Reborn's "Liquid Glass Tab Bar"; "Hide Bars on Scroll" maps to
/// UIKit's own minimize behaviour (`tabBarMinimizeBehavior`), with
/// Reborn's Left/Right/Fade/Down hide styles on top.
public struct LiquidGlassTabBar: View {
    public struct Tab: Identifiable {
        public let id: Int
        public let title: String
        public let systemImage: String
        /// Reborn "Profile Picture Tab Icon" (`useProfileAvatarTabIcon`):
        /// the signed-in user's avatar drawn in place of the symbol.
        /// The native bar only takes images, so this is a pre-rendered,
        /// original-colour bitmap (`ProfileTabAvatar`). `nil` for every
        /// other tab, and until the avatar has loaded.
        public let customIcon: UIImage?
        /// Apollo's own tab glyph (`tab-bar-*` in `StockIcons`), drawn
        /// in place of the SF Symbol when present.
        public let stockIcon: String?
        /// Badge on the tab (the Inbox's unread count).
        public let badge: String?
        public let content: () -> AnyView

        var nativeSystemImage: String { systemImage }

        public init<Content: View>(id: Int, title: String, systemImage: String, stockIcon: String? = nil, customIcon: UIImage? = nil, badge: String? = nil, @ViewBuilder content: @escaping () -> Content) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.stockIcon = stockIcon
            self.badge = badge
            self.customIcon = customIcon
            self.content = { AnyView(content()) }
        }
    }

    let tabs: [Tab]
    @Binding var selection: Int
    /// Collapses the pill to a small circular icon while the active
    /// tab's content is scrolling down.
    let hideBarsOnScroll: Bool
    /// Reborn "Hide Header on Scroll" (`HideTopBarOnScroll`). Only
    /// meaningful while `hideBarsOnScroll` is on.
    let hideTopBarOnScroll: Bool
    /// Reborn "Scroll Behavior" (`classicTabBarScrollBehavior`):
    /// Two-Gesture hides the bar on the second downward gesture,
    /// Classic hides it on the first. `false` = Two-Gesture (default).
    var classicScrollBehavior: Bool = false
    /// Reborn "Icon-Only Tab Bar": hides every tab's text label.
    var iconOnly: Bool = false
    /// Reborn "Hide Style": 0 Left, 1 Right, 2 Fade, 3 Down.
    var hideStyle: Int = 0

    public init(tabs: [Tab], selection: Binding<Int>, hideBarsOnScroll: Bool, hideTopBarOnScroll: Bool = false, classicScrollBehavior: Bool = false, iconOnly: Bool = false, hideStyle: Int = 0) {
        self.hideStyle = hideStyle
        self.tabs = tabs
        self._selection = selection
        self.hideBarsOnScroll = hideBarsOnScroll
        self.hideTopBarOnScroll = hideTopBarOnScroll
        self.classicScrollBehavior = classicScrollBehavior
        self.iconOnly = iconOnly
    }

    /// Owned here, not by the screen, because the search field replaces
    /// this pill rather than stacking above it. See
    /// `GlassSearchCoordinator`.
    @StateObject private var search = GlassSearchCoordinator()
    @StateObject private var scrollPolicy = TabBarScrollPolicy()

    public var body: some View {
        // A real system tab bar: iOS 26's `tabBarMinimizeBehavior` gives
        // scroll-edge blur, the minimize morph and safe-area insets for free.
        nativeTabView
            .environment(\.glassSearchCoordinator, LiquidGlass.isEnabled ? search : nil)
    }

    /// Selection binding that makes re-tapping the current tab
    /// observable. SwiftUI only writes the binding when the value
    /// changes, so a re-tap is otherwise silent; this setter posts
    /// `.apolloTabReselected` when the value is unchanged, so Settings
    /// still pops to root on a re-tap.
    private var selectionProxy: Binding<Int> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == selection {
                    NotificationCenter.default.post(
                        name: .apolloTabReselected,
                        object: nil,
                        userInfo: ["tab": newValue])
                } else {
                    selection = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var nativeTabView: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: selectionProxy) {
                // Written out one `Tab` per tab, not `ForEach(tabs)`:
                // `TabView`'s builder resolves `Tab` declarations statically,
                // and a `ForEach` installs a `UITabBar` with no item views.
                // `SwiftUI.Tab` is spelled out fully since it is not a `View`
                // and this type's own nested `Tab` shadows it.
                SwiftUI.Tab(value: tabs[0].id) { tabs[0].content() }
                    label: { tabLabel(for: tabs[0]) }
                    .badge(tabs[0].badge.map { Text($0) })
                SwiftUI.Tab(value: tabs[1].id) { tabs[1].content() }
                    label: { tabLabel(for: tabs[1]) }
                    .badge(tabs[1].badge.map { Text($0) })
                SwiftUI.Tab(value: tabs[2].id) { tabs[2].content() }
                    label: { tabLabel(for: tabs[2]) }
                    .badge(tabs[2].badge.map { Text($0) })
                SwiftUI.Tab(value: tabs[3].id) { tabs[3].content() }
                    label: { tabLabel(for: tabs[3]) }
                    .badge(tabs[3].badge.map { Text($0) })
                SwiftUI.Tab(value: tabs[4].id) { tabs[4].content() }
                    label: { tabLabel(for: tabs[4]) }
                    .badge(tabs[4].badge.map { Text($0) })
            }
            // UIKit's own minimize-on-scroll, matching Apollo's
            // default. `.onScrollDown`; `.never` when Hide Bars on
            // Scroll is off. Left/Right use UIKit's own minimize;
            // Fade/Down keep it off and animate the whole bar instead.
            .tabBarMinimizeBehavior(hideBarsOnScroll && hideStyle <= 1 && !scrollPolicy.holdExpanded
                                    ? .onScrollDown : .never)
            .onAppear { scrollPolicy.classic = classicScrollBehavior }
            // Turned off while collapsed: bring everything back now.
            .onChange(of: hideBarsOnScroll) { _, on in
                if !on { NotificationCenter.default.post(name: .apolloBarsShouldShow, object: nil) }
            }
            .onChange(of: classicScrollBehavior) { _, classic in scrollPolicy.classic = classic }
            .background(TabBarHideStyleProbe(style: hideBarsOnScroll ? hideStyle : 0)
                .frame(width: 0, height: 0))
        } else {
            // Pre-iOS-26: the same tabs through the classic API. No
            // minimize behaviour to set there.
            TabView(selection: selectionProxy) {
                ForEach(tabs) { tab in
                    tab.content()
                        .tag(tab.id)
                        .tabItem { tabLabel(for: tab) }
                        .badge(tab.badge.map { Text($0) })
                }
            }
        }
    }

    /// One tab's label. Only `Text` + `Image` survive into a real
    /// `UITabBarItem`, so the profile avatar arrives as a pre-sized
    /// bitmap rather than a live `AvatarView`.
    @ViewBuilder
    private func tabLabel(for tab: Tab) -> some View {
        // Icon-only: an empty title still reserves the label's line,
        // matching the system bar's own icon-only layout.
        let title = iconOnly ? "" : tab.title
        if let avatar = tab.customIcon {
            Label { Text(title) } icon: {
                Image(uiImage: avatar).renderingMode(.original)
            }
        } else if let name = tab.stockIcon,
                  let glyph = StockIcon.image(named: name, size: StockIcon.intrinsicSize(name)) {
            Label { Text(title) } icon: { Image(uiImage: glyph).renderingMode(.template) }
        } else {
            Label(title, systemImage: tab.nativeSystemImage)
        }
    }
}



/// Re-fires `.onAppear` for a tab whose content is kept alive but
/// hidden (see the call site). SwiftUI only sends `onAppear` when a
/// view enters the hierarchy, which in this tab bar happens once ever.
private struct TabReappearNotifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.onChange(of: isSelected) { _, nowSelected in
            guard nowSelected else { return }
            NotificationCenter.default.post(name: .apolloTabDidReappear, object: nil)
        }
    }
}


/// Hides the navigation bar in step with the tab bar for Apollo-Reborn's
/// "Hide Header on Scroll" (#1079, `HideTopBarOnScroll`, default OFF).
///
/// Applied inside a screen's own `NavigationStack` rather than on the tab
/// container: `.toolbar(_:for: .navigationBar)` only reaches the bar of
/// the stack it is inside.
public struct HideHeaderOnScrollModifier: ViewModifier {
    @State private var isHidden = false
    @Environment(\.apolloTheme) private var apolloTheme
    /// Observed, so turning either switch on or off applies at once.
    @Setting(GeneralSettingsStore.storage) private var settings

    public init() {}

    public func body(content: Content) -> some View {
        // Only while Hide Bars on Scroll is also on; the remembered
        // choice is kept when it is off, only the row hides.
        let enabled = settings.hideBarsOnScroll && settings.hideTopBarOnScroll
        return content
            .toolbar(enabled && isHidden ? .hidden : .visible, for: .navigationBar)
            // Without the nav bar nothing covers the status bar, so titles and scores
            // would scroll under the clock. A window-level scrim covers it; an
            // `.overlay` can't, since a view already under the status bar has no
            // safe-area inset left to grow into.
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHidden)
            .onReceive(NotificationCenter.default.publisher(for: .apolloBarsShouldHide)) { _ in
                guard enabled else { return }
                isHidden = true
                StatusBarScrim.setVisible(true, color: apolloTheme.color(.barBackground))
            }
            .onReceive(NotificationCenter.default.publisher(for: .apolloBarsShouldShow)) { _ in
                isHidden = false
                StatusBarScrim.setVisible(false, color: nil)
            }
            .onChange(of: enabled) { _, on in
                guard !on, isHidden else { return }
                isHidden = false
                StatusBarScrim.setVisible(false, color: nil)
            }
            .onDisappear {
                // Leaving the feed (push to a post, tab switch) must
                // not strand the scrim on top of a screen whose bar is
                // visible.
                StatusBarScrim.setVisible(false, color: nil)
            }
    }
}

/// The window-level status bar cover used by `HideHeaderOnScrollModifier`.
@MainActor
enum StatusBarScrim {
    private static let tag = 0x5ADE_5C21

    static func setVisible(_ visible: Bool, color: Color?) {
        guard let window = UIKitTree.keyWindow else { return }
        let existing = window.subviews.first { $0.tag == tag }
        guard visible else {
            guard let existing else { return }
            UIView.animate(withDuration: 0.25, animations: { existing.alpha = 0 }) { _ in
                existing.removeFromSuperview()
            }
            return
        }
        // Height comes from the scene's status bar frame so it stays
        // correct across devices and while the in-call bar is doubled.
        let height = (window.windowScene?.statusBarManager?.statusBarFrame.height)
            ?? window.safeAreaInsets.top
        guard height > 0 else { return }
        let frame = CGRect(x: 0, y: 0, width: window.bounds.width, height: height)
        let fill = color.map { UIColor($0) } ?? .systemBackground
        if let existing {
            existing.frame = frame
            existing.backgroundColor = fill
            window.bringSubviewToFront(existing)
            return
        }
        let view = UIView(frame: frame)
        view.tag = tag
        view.backgroundColor = fill
        view.isUserInteractionEnabled = false
        view.autoresizingMask = [.flexibleWidth]
        view.alpha = 0
        window.addSubview(view)
        UIView.animate(withDuration: 0.25) { view.alpha = 1 }
    }
}

public extension View {
    /// See `HideHeaderOnScrollModifier`.
    func apolloHidesHeaderOnScroll() -> some View {
        modifier(HideHeaderOnScrollModifier())
    }
}

#if canImport(UIKit)
import UIKit

/// Press-and-hold on one tab bar item (Reborn: holding the Settings tab
/// opens the Settings Shortcuts menu).
///
/// SwiftUI's `TabView` exposes no gesture on its items, so a probe finds
/// the real `UITabBar` and adds a long-press recognizer scoped to the
/// target item's slot.
public struct TabItemLongPressProbe: UIViewRepresentable {
    let index: Int
    let count: Int
    let action: () -> Void

    public init(index: Int, count: Int, action: @escaping () -> Void) {
        self.index = index; self.count = count; self.action = action
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        return v
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.index = index
        context.coordinator.count = count
        context.coordinator.action = action
        DispatchQueue.main.async {
            guard let tabBar = uiView.window.flatMap(Self.findTabBar) else { return }
            context.coordinator.attach(to: tabBar)
        }
    }

    static func findTabBar(in view: UIView) -> UITabBar? {
        UIKitTree.firstDescendant(of: UITabBar.self, in: view)
    }

    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var index = 0
        var count = 1
        var action: () -> Void = {}
        private weak var attachedBar: UITabBar?

        func attach(to bar: UITabBar) {
            guard attachedBar !== bar else { return }
            attachedBar = bar
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            press.minimumPressDuration = 0.45
            press.delegate = self
            bar.addGestureRecognizer(press)
        }

        public func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let bar = recognizer.view, count > 0 else { return false }
            let x = recognizer.location(in: bar).x
            let slot = bar.bounds.width / CGFloat(count)
            return Int(x / slot) == index
        }

        public func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            // Matches the account switcher's medium impact for
            // deliberate menu actions.
            Haptics.medium()
            action()
        }
    }
}
#endif

#if canImport(UIKit)
/// Reborn "Swipe Tab Bar to Navigate" (#1075): swipe right along the tab
/// bar to go back, left to go forward, given priority over iOS 26's
/// "Liquid Lens" drag-to-switch-tab gesture. Wired once per launch; the
/// setting asks for a relaunch.
///
/// Drives the visible stack's page swipe, as an edge swipe does.
public struct TabBarSwipeNavigationProbe: UIViewRepresentable {
    public init() {}

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        return v
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let bar = uiView.window.flatMap(TabItemLongPressProbe.findTabBar) else { return }
            context.coordinator.attach(to: bar)
        }
    }

    @MainActor
    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var bar: UITabBar?
        private var isBack = true

        func attach(to tabBar: UITabBar) {
            guard bar !== tabBar else { return }
            bar = tabBar
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.delegate = self
            tabBar.addGestureRecognizer(pan)
            if let lens = tabBar.gestureRecognizers?.first(where: {
                NSStringFromClass(type(of: $0)) == "_UIContinuousSelectionGestureRecognizer"
            }) {
                lens.require(toFail: pan)
            }
        }

        /// Only a decisively horizontal drag with somewhere to go.
        public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let v = pan.velocity(in: view)
            guard abs(v.x) >= abs(v.y) * PushPopGesturePolicy.horizontalDominance else { return false }
            isBack = v.x > 0
            guard let controller = PageSwipeController.forVisibleStack, controller.canBegin(back: isBack) else { return false }
            self.controller = controller
            return true
        }

        private var controller: PageSwipeController?

        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            let width = Double(UIScreen.main.bounds.width)
            let dx = Double(pan.translation(in: pan.view).x)
            switch pan.state {
            case .began:
                controller?.begin(back: isBack)
            case .changed:
                controller?.update(translationX: dx, width: width)
            case .ended:
                controller?.end(translationX: dx, velocityX: Double(pan.velocity(in: pan.view).x), width: width)
                controller = nil
            default:
                controller?.end(complete: false)
                controller = nil
            }
        }
    }
}
#endif


#if canImport(UIKit)
/// Reborn "Hide Style".
///
/// - Left: UIKit's native minimize docks the collapsed pill leading, no-op.
/// - Right: after every `UITabBar` layout pass, mirror the collapsed
///   platter across the bar's midline when it sits on the other side,
///   since UIKit exposes no placement API for that pill. Idempotent,
///   so it runs on every pass, including mid-morph.
/// - Fade / Down: native minimize off; a scroll down fades the whole bar
///   to 0 or slides it below the screen, a scroll up brings it back.
struct TabBarHideStyleProbe: UIViewRepresentable {
    let style: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.style = style
        DispatchQueue.main.async {
            guard let bar = uiView.window.flatMap(TabItemLongPressProbe.findTabBar) else { return }
            context.coordinator.attach(to: bar)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var style = 0 {
            didSet {
                guard oldValue != style else { return }
                updateMirrorLink()
                show(animated: false)
                bar?.setNeedsLayout()
            }
        }
        private weak var bar: UITabBar?
        private var displayLink: CADisplayLink?
        private var observers: [NSObjectProtocol] = []

        func attach(to tabBar: UITabBar) {
            guard bar !== tabBar else { return }
            bar = tabBar
            updateMirrorLink()
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .apolloBarsShouldHide, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            })
            observers.append(center.addObserver(forName: .apolloBarsShouldShow, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.show(animated: true) }
            })
        }

        /// Mirror pass for Right: a display link, since there is no public
        /// post-layout hook on UITabBar without swizzling. Runs only while
        /// the Right style is selected.
        private func updateMirrorLink() {
            if style == 1, bar != nil {
                guard displayLink == nil else { return }
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else {
                displayLink?.invalidate()
                displayLink = nil
            }
        }

        @objc private func tick() {
            guard style == 1, let bar else { return }
            Self.mirrorCollapsedPlatter(in: bar)
        }

        static func mirrorCollapsedPlatter(in bar: UITabBar) {
            // Ivar reads, never KVC: `value(forKey:)` on a missing private
            // key throws an ObjC exception.
            guard let provider = ivar(bar, "_visualProvider"),
                  let platter = ivar(provider, "collapsePlatterView") as? UIView,
                  let host = platter.superview, host.bounds.width > 0 else { return }
            var center = platter.center
            let onRight = center.x > host.bounds.width / 2
            guard !onRight else { return }
            center.x = host.bounds.width - center.x
            platter.center = center
        }

        static func ivar(_ object: AnyObject, _ name: String) -> AnyObject? {
            var cls: AnyClass? = object_getClass(object)
            while let c = cls {
                if let iv = class_getInstanceVariable(c, name) {
                    return object_getIvar(object, iv) as AnyObject?
                }
                cls = class_getSuperclass(c)
            }
            return nil
        }

        private func hide() {
            guard let bar, style >= 2 else { return }
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                if self.style == 2 {
                    bar.alpha = 0
                } else {
                    let drop = bar.bounds.height + bar.safeAreaInsets.bottom + 20
                    bar.transform = CGAffineTransform(translationX: 0, y: drop)
                }
            }
        }

        private func show(animated: Bool) {
            guard let bar else { return }
            let work = {
                bar.alpha = 1
                bar.transform = .identity
            }
            if animated {
                UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: work)
            } else {
                work()
            }
        }
    }
}
#endif
