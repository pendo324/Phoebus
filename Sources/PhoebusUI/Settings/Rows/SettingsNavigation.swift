import SwiftUI
import PhoebusCore

/// Path-driven navigation for a tab's stack, so a pop is seen as a
/// path change and a forward swipe can re-push it (see
/// `ForwardNavigationStore`). Every row pushes through `SettingsLink`,
/// which appends to the path.
@MainActor
public final class SettingsNavigationModel: ObservableObject {
    @Published public var path: [SettingsRoute] = [] {
        didSet {
            // A back swipe that starts on a link (App Icon's pack cards) can fire that
            // link as the finger lifts on iOS 27, popping the screen the link just
            // pushed. No push while a back swipe is in progress.
            if path.count > oldValue.count, PageSwipeController.isActive, PageSwipeController.activeIsBack {
                path = oldValue
                return
            }
            pathChanged(from: oldValue)
        }
    }

    /// The tab this stack lives in.
    public let tab: Int

    public init(tab: Int) {
        self.tab = tab
    }

    private func pathChanged(from old: [SettingsRoute]) {
        if path.count == old.count + 1 {
            ForwardNavigationStore.shared.recordPush()
        } else if path.count == old.count - 1, let popped = old.last {
            // A single pop (back button or back swipe): swiping forward
            // re-pushes exactly that screen.
            ForwardNavigationStore.shared.recordPop(isLive: { [weak self] in self != nil }) { [weak self] in
                self?.path.append(popped)
            }
        } else if path.count < old.count {
            // Pop-to-root (tab re-tap) - nothing sensible to go forward
            // to, and nothing left underneath.
            ForwardNavigationStore.shared.clearCurrentTab()
        }
    }
}

/// One pushed settings screen. Identity is per push, so pushing the same
/// screen twice gives two distinct entries.
public struct SettingsRoute: Hashable {
    let id = UUID()
    let view: AnyView

    public init(view: AnyView) { self.view = view }

    public static func == (lhs: SettingsRoute, rhs: SettingsRoute) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct SettingsNavigationKey: EnvironmentKey {
    static let defaultValue: SettingsNavigationModel? = nil
}

extension EnvironmentValues {
    var settingsNavigation: SettingsNavigationModel? {
        get { self[SettingsNavigationKey.self] }
        set { self[SettingsNavigationKey.self] = newValue }
    }
}

public extension View {
    /// Hosts a path-driven Settings stack: registers the one
    /// destination for `SettingsRoute` and gives every screen in it
    /// Apollo's page swipes.
    func apolloSettingsNavigation(_ model: SettingsNavigationModel) -> some View {
        self
            .apolloForwardSwipe()
            .navigationDestination(for: SettingsRoute.self) { route in
                route.view
                    .apolloForwardSwipe()
                    // Re-injected per destination: with the environment only on the root,
                    // pushed screens would not see the model and their `SettingsLink`s would
                    // fall back to untracked pushes with no back snapshot.
                    .environment(\.settingsNavigation, model)
            }
            .environment(\.settingsNavigation, model)
    }
}

/// Drop-in for `NavigationLink` on settings screens.
///
/// Inside the Settings tab it is a VALUE link, so the push lands in
/// `SettingsNavigationModel.path` (keeping the row's native disclosure
/// chevron and highlight). Anywhere else (a settings screen reached from
/// another tab, a preview) it falls back to a plain destination link, so
/// it can never silently do nothing.
public struct SettingsLink<Label: View, Destination: View>: View {
    @Environment(\.settingsNavigation) private var navigation
    private let destination: () -> Destination
    private let label: Label

    public init(@ViewBuilder destination: @escaping () -> Destination,
                @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    public var body: some View {
        if navigation != nil {
            NavigationLink(value: SettingsRoute(view: AnyView(destination()))) { label }
        } else {
            NavigationLink(destination: destination) { label }
        }
    }
}

public extension SettingsLink where Label == Text {
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(destination: destination) { Text(title) }
    }
}

public extension View {
    /// `navigationDestination(isPresented:)` for settings screens: inside
    /// the Settings tab the push goes through the path (so the page
    /// swipes see it), and the flag is reset once pushed; elsewhere it
    /// is the plain modifier.
    func settingsDestination<D: View>(
        isPresented: Binding<Bool>, @ViewBuilder destination: @escaping () -> D
    ) -> some View {
        modifier(SettingsDestinationModifier(isPresented: isPresented, destination: destination))
    }
}

private struct SettingsDestinationModifier<D: View>: ViewModifier {
    @Binding var isPresented: Bool
    let destination: () -> D
    @Environment(\.settingsNavigation) private var navigation

    func body(content: Content) -> some View {
        if let navigation {
            content.onChange(of: isPresented) { _, shown in
                guard shown else { return }
                navigation.path.append(SettingsRoute(view: AnyView(destination())))
                isPresented = false
            }
        } else {
            content.navigationDestination(isPresented: $isPresented, destination: destination)
        }
    }
}
