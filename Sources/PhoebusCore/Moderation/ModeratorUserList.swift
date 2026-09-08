import Foundation

/// The three moderator user lists (banned, muted, approved submitters).
/// Apollo gives each its own screen from its own menu case rather than one
/// screen with a segmented switcher.
public enum ModeratorUserList: String, CaseIterable, Sendable {
    case banned = "Banned"
    case muted = "Muted"
    case approved = "Approved"

    /// Navigation-title wording.
    public var title: String {
        switch self {
        case .banned: return "Banned Users"
        case .muted: return "Muted Users"
        case .approved: return "Approved Submitters"
        }
    }

    /// Apollo's icon name for the menu row that opens it.
    public var apolloIconName: String {
        switch self {
        case .banned: return "option-ban"
        case .muted: return "option-mute-notifications"
        case .approved: return "option-approved-submitters"
        }
    }
}
