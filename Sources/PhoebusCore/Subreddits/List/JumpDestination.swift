import Foundation

/// A single "jump to subreddit or user" navigation target, one enum per
/// screen instead of separate `jumpTarget: String?` / `jumpUser: String?`.
///
/// SwiftUI's `navigationDestination(item:)` dispatches by the value's type,
/// not by which binding was passed. Two `String?` bindings would register
/// two handlers for the same type on one `NavigationStack`; the one applied
/// later in the modifier chain silently wins and the other does nothing.
/// One `JumpDestination?` with one `.navigationDestination(item:)` avoids
/// the collision.
public enum JumpDestination: Identifiable, Hashable, Sendable {
    case subreddit(String)
    case user(String)

    public var id: String {
        switch self {
        case .subreddit(let name): return "subreddit:\(name)"
        case .user(let name): return "user:\(name)"
        }
    }
}
