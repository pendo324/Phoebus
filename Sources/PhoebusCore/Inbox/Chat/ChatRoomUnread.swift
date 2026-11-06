import Foundation

/// Which chat rooms read as unread and which of those feed the badges.
///
/// Reddit keeps a muted room out of its global chat counter
/// (`is_counted_in_global_navigation_counter` false) but not out of the
/// room's own `notification_count`, so "unread" and "counts toward the
/// badge" are two questions. A muted room with unread messages shows the
/// dot and bold title; only a room that counts toward the badge feeds the
/// Inbox tab badge, the app icon badge and the Bark pushes.
public enum ChatRoomUnread {
    /// Shows the unread dot and bold title, and passes the Unread Only filter.
    /// A request is answered on its own screen, not marked unread.
    public static func isUnread(_ room: ChatRoom) -> Bool {
        !room.isInvite && room.notificationCount > 0
    }

    /// Unread and not muted: the rooms the badges and pushes are made of.
    public static func countsTowardBadge(_ room: ChatRoom) -> Bool {
        isUnread(room) && room.countsTowardGlobalBadge
    }

    /// Unread but silenced by the account; drawn in grey rather than the accent.
    public static func isMutedUnread(_ room: ChatRoom) -> Bool {
        isUnread(room) && !room.countsTowardGlobalBadge
    }

    /// The badge total derived from the rooms when Reddit sends no counter.
    public static func badgeTotal(of rooms: [ChatRoom]) -> Int {
        rooms.filter(countsTowardBadge).reduce(0) { $0 + $1.notificationCount }
    }
}
