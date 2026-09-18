import SwiftUI
import PhoebusCore
import Combine

/// Reborn's "Floating Post Tabs" manager (see `FloatingPostTabsSettings`).
/// Holds up to 5 kept-open posts as an observable array that
/// `FloatingPostTabsOverlay` reads to draw the bubbles.
///
/// A single app-wide instance lives on `MainTabView` so bubbles persist
/// and float above every tab.
@MainActor
public final class FloatingPostTabsManager: ObservableObject {
    /// Cap on kept-open posts.
    public static let maxKeptPosts = 5

    @Published public private(set) var keptPosts: [RedditPost] = []

    public init() {}

    /// Adds a post to the floating stack, moving it to the front if
    /// already present (most-recently-kept bubble reads first) and
    /// evicting the oldest once past `maxKeptPosts`.
    public func add(post: RedditPost) {
        keptPosts.removeAll { $0.id == post.id }
        keptPosts.insert(post, at: 0)
        if keptPosts.count > Self.maxKeptPosts {
            keptPosts.removeLast(keptPosts.count - Self.maxKeptPosts)
        }
    }

    public func remove(post: RedditPost) {
        keptPosts.removeAll { $0.id == post.id }
    }

    public func isKept(_ post: RedditPost) -> Bool {
        keptPosts.contains { $0.id == post.id }
    }
}

/// Optional environment plumbing for `FloatingPostTabsManager` -
/// deliberately `Environment` (not `EnvironmentObject`) so screens like
/// `PostDetailScreen` that read it can still be constructed/previewed
/// standalone (the key's default is `nil`) without every existing call
/// site needing a new required parameter. `MainTabView` installs the
/// real app-wide instance via `.environment(\.floatingPostTabsManager, manager)`.
private struct FloatingPostTabsManagerKey: EnvironmentKey {
    static let defaultValue: FloatingPostTabsManager? = nil
}

public extension EnvironmentValues {
    var floatingPostTabsManager: FloatingPostTabsManager? {
        get { self[FloatingPostTabsManagerKey.self] }
        set { self[FloatingPostTabsManagerKey.self] = newValue }
    }
}

