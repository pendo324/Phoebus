import SwiftUI
import PhoebusCore

/// Reborn's collapsed navigation action pill (`CollapseNavigationActions`).
///
/// A screen with two or more trailing actions shows one "•••" that expands
/// them in place; they re-collapse on scroll, on a back-swipe, or when the
/// app resigns active. Behavior and constants live in
/// `NavigationActionsPolicy`. Used as a single `ToolbarItem` in place of
/// several.
public struct NavigationActionsPill: View {
    /// One trailing action, in the order it appeared in the toolbar.
    public struct Action: Identifiable {
        public let id: String
        let systemImage: String
        let label: String
        let perform: () -> Void

        public init(id: String, systemImage: String, label: String, perform: @escaping () -> Void) {
            self.id = id
            self.systemImage = systemImage
            self.label = label
            self.perform = perform
        }
    }

    private let actions: [Action]
    /// The screen's own overflow menu content.
    ///
    /// Like Reborn, the pill reuses the screen's existing More button instead of
    /// adding a second "...": while collapsed its menu is swapped for an expand
    /// action, and once expanded the real menu is back.
    private let menuContent: AnyView?
    @State private var expanded: Bool

    /// Reborn makes collapsing opt-in (`CollapseNavigationActions`, off by
    /// default).
    ///
    /// Read once at init to seed `expanded`. See
    /// `GeneralSettings.collapseNavigationActions`.
    private let collapsePreference: Bool

    public init(actions: [Action]) {
        self.actions = actions
        self.menuContent = nil
        let collapses = GeneralSettingsStore.load().collapseNavigationActions
        self.collapsePreference = collapses
        _expanded = State(initialValue: !collapses)
    }

    public init<Menu: View>(actions: [Action], @ViewBuilder menu: () -> Menu) {
        self.actions = actions
        self.menuContent = AnyView(menu())
        let collapses = GeneralSettingsStore.load().collapseNavigationActions
        self.collapsePreference = collapses
        _expanded = State(initialValue: !collapses)
    }

    public var body: some View {
        HStack(spacing: 14) {
            if expanded {
                ForEach(actions) { action in
                    Button {
                        action.perform()
                        // Choosing an action settles the group back to collapsed.
                        collapse(reason: .actionTapped)
                    } label: {
                        Image(systemName: action.systemImage)
                    }
                    .accessibilityLabel(action.label)
                    .accessibilityIdentifier("nav.action.\(action.id)")
                }
            }
            // The More glyph stays drawn while expanded, so it lives outside the `if`.
            // Its behaviour changes with state: collapsed, it expands the group;
            // expanded, it opens the real overflow menu (a second tap does not
            // re-collapse).
            if expanded, let menuContent {
                // Expanded: More behaves as the screen's real overflow
                // menu again.
                Menu {
                    menuContent
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More Options")
                .accessibilityIdentifier("nav.actions.more")
            } else {
                // Collapsed (or no menu on this screen): More reveals
                // the group.
                Button {
                    withAnimation(springAnimation) { expanded = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Show Actions")
                .accessibilityIdentifier("nav.actions.more")
            }
        }
        // Collapse triggers; `.apolloNavigationActionsCollapse` is posted by the
        // scroll/back-gesture/resign observers below.
        .onReceive(NotificationCenter.default.publisher(for: .apolloNavigationActionsCollapse)) { note in
            let reason = note.object as? NavigationActionsPolicy.CollapseReason ?? .scrolled
            collapse(reason: reason)
        }
    }

    private var springAnimation: Animation {
        .interpolatingSpring(
            mass: NavigationActionsPolicy.springMass,
            stiffness: NavigationActionsPolicy.springStiffness,
            damping: NavigationActionsPolicy.springDamping
        )
    }

    private func collapse(reason: NavigationActionsPolicy.CollapseReason) {
        // With the preference off the strip is forced back to expanded even if
        // something else collapsed it, so off means "never collapsed". Skipping the
        // triggers entirely reaches the same state without fighting the animation.
        guard collapsePreference else { return }
        guard expanded else { return }
        if NavigationActionsPolicy.animatesCollapse(for: reason) {
            withAnimation(springAnimation) { expanded = false }
        } else {
            expanded = false
        }
    }
}


// The scroll collapse is posted from `ScrollToTopDelegateProxy`
// (`ScrollToTopRestore.swift`), already the List's UIScrollView delegate. A
// SwiftUI `DragGesture` doesn't work since the List's own pan consumes it.
