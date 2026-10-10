import SwiftUI
import PhoebusCore

extension AuthorHighlight {
    /// The name's colour: your own name in the theme accent, followed users
    /// in orange (themes have no second accent to use). `plain` is what the
    /// call site draws otherwise.
    func color(plain: Color) -> Color {
        switch self {
        case .moderator: return Color(hex: ApolloPalette.moderatorGreenHex)
        case .admin: return .red
        case .own: return .apolloAccent
        case .followed: return .orange
        case .none: return plain
        }
    }
}

/// Bumps when a Follow/Unfollow changes `FollowedUsernames`, so rows that
/// observe it redraw their author colour without waiting for a reload.
@MainActor
final class FollowedUsernamesRevision: ObservableObject {
    static let shared = FollowedUsernamesRevision()
    @Published private(set) var revision = 0
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: FollowedUsernames.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.revision += 1 }
            }
    }
}

extension View {
    /// Tints a post author's name for your own name or a followed user,
    /// keeping the inherited colour otherwise. Post bylines have no
    /// moderator/admin colour, so a distinguished post keeps that too.
    @ViewBuilder
    func authorHighlight(_ highlight: AuthorHighlight) -> some View {
        switch highlight {
        case .own, .followed: foregroundStyle(highlight.color(plain: .primary))
        case .none, .moderator, .admin: self
        }
    }
}
