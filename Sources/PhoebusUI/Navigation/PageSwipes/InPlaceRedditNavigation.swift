import SwiftUI
import PhoebusCore

/// Opens a Reddit target (a post, subreddit, user…) as a push on top of
/// the screen the user is on, instead of appending it to the tab's
/// root path.
///
/// Appending to a tab's `NavigationStack` path drops every screen pushed
/// above it with `navigationDestination(item:)` (how feeds, threads and
/// profiles push), which would discard the back/forward swipe history.
/// Each such screen registers here while it's on top; the app's
/// `RedditLinkNavigator` handler asks the topmost one first.
@MainActor
public final class InPlaceRedditNavigation {
    public static let shared = InPlaceRedditNavigation()

    /// The pushed screen for a target, supplied by the app (its loaders
    /// live there).
    public var destination: ((RedditURLTarget) -> AnyView)?

    private var handlers: [(id: UUID, tab: Int?, open: (RedditURLTarget) -> Void)] = []

    /// Opens on the topmost registered screen of `tab`; false when it has
    /// none, and the caller falls back to the tab's path.
    public func open(_ target: RedditURLTarget, inTab tab: Int) -> Bool {
        guard let handler = handlers.last(where: { $0.tab == nil || $0.tab == tab }) else { return false }
        handler.open(target)
        return true
    }

    func register(_ id: UUID, tab: Int?, _ open: @escaping (RedditURLTarget) -> Void) {
        handlers.removeAll { $0.id == id }
        handlers.append((id, tab, open))
    }

    func unregister(_ id: UUID) {
        handlers.removeAll { $0.id == id }
    }
}

/// A target as a pushable item.
struct PushedRedditTarget: Identifiable, Hashable {
    let target: RedditURLTarget
    var id: String { String(describing: target) }
}

private struct OpensRedditTargetsHere: ViewModifier {
    @Environment(\.isContextMenuPreview) private var isPreview
    @Environment(\.settingsNavigation) private var navigation
    @State private var id = UUID()
    @State private var pushed: PushedRedditTarget?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isPreview else { return }
                InPlaceRedditNavigation.shared.register(id, tab: navigation?.tab) { pushed = PushedRedditTarget(target: $0) }
            }
            .onDisappear { InPlaceRedditNavigation.shared.unregister(id) }
            .navigationDestination(item: $pushed) { item in
                InPlaceRedditNavigation.shared.destination?(item.target) ?? AnyView(EmptyView())
            }
            .apolloTracksForwardNavigation($pushed)
    }
}

private struct IsContextMenuPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Inside a long-press preview, which must not take navigation.
    var isContextMenuPreview: Bool {
        get { self[IsContextMenuPreviewKey.self] }
        set { self[IsContextMenuPreviewKey.self] = newValue }
    }
}

public extension View {
    /// Reddit targets opened while this screen is on top push from here.
    func apolloOpensRedditTargetsHere() -> some View {
        modifier(OpensRedditTargetsHere())
    }
}
