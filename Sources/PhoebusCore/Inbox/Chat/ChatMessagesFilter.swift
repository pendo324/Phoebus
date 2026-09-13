import Foundation

/// The chat inbox's "Show in Messages" filter (Reborn 3.7.0, keys
/// `ChatMessagesFilter` and `ChatMessagesUnreadOnly`), as Reborn's filter menu
/// on the chat hub's bar button:
///
///   - an inline group of three mutually exclusive chat types, titled
///     "Direct Chats", "Group Chats", "All Chats"
///   - a second inline group holding one toggle, "Unread Only", with
///     the `envelope.badge` symbol
///   - the whole menu titled "Show in Messages", symbol
///     `line.3.horizontal.decrease.circle`
///
/// The stored values are the strings `group` and `all`, and Direct is the
/// default: the fall-through for an unset or unrecognised value.
///
/// Reborn's chat inbox is Reddit's web view, so it drives the page's filter
/// checkboxes with injected JavaScript. The chat list here is a native SwiftUI
/// list over `ChatRoom` values, so the same semantics apply directly to the
/// model.
public enum ChatMessagesFilter: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Fall-through default.
    case direct
    case group
    case all

    public var id: String { rawValue }

    /// Menu titles.
    public var displayName: String {
        switch self {
        case .direct: return "Direct Chats"
        case .group: return "Group Chats"
        case .all: return "All Chats"
        }
    }

    /// Whether a room passes this filter.
    ///
    /// "All" admits everything: an unfiltered list is Reddit's default.
    ///
    /// Direct-vs-group is decided by Reddit's `com.reddit.chat.type.type` room
    /// field, which `ChatRoom.chatType` carries ("direct" for a one-to-one room).
    /// A room with no type recorded counts as group, as "not direct" is what the
    /// web UI's group box selects.
    public func admits(chatType: String?) -> Bool {
        switch self {
        case .all: return true
        case .direct: return chatType?.lowercased() == "direct"
        case .group: return chatType?.lowercased() != "direct"
        }
    }
}

/// Persistence for both keys.
public enum ChatMessagesFilterStore {
    /// Reborn's key names, so a defaults import lines up.
    private static let filterKey = "ChatMessagesFilter"
    private static let unreadOnlyKey = "ChatMessagesUnreadOnly"

    public static let filterStorage = CustomSettingsSource<ChatMessagesFilter>(
        key: filterKey, load: { _ in loadFilter() }, save: { filter, defaults in defaults.set(filter.rawValue, forKey: filterKey) })
    public static let unreadOnlyStorage = DefaultsKey<Bool>(unreadOnlyKey, default: false)

    public static func loadFilter() -> ChatMessagesFilter {
        // Unset or unrecognised falls through to Direct.
        guard let raw = UserDefaults.standard.string(forKey: filterKey),
              let filter = ChatMessagesFilter(rawValue: raw) else {
            return .direct
        }
        return filter
    }

    public static func saveFilter(_ filter: ChatMessagesFilter) { filterStorage.save(filter) }

    public static func loadUnreadOnly() -> Bool {
        UserDefaults.standard.bool(forKey: unreadOnlyKey)
    }

    public static func saveUnreadOnly(_ unreadOnly: Bool) { unreadOnlyStorage.save(unreadOnly) }

    /// Applies both settings to a room list. Pure, so the rules are checkable.
    public static func apply(
        filter: ChatMessagesFilter,
        unreadOnly: Bool,
        to rooms: [ChatRoom]
    ) -> [ChatRoom] {
        rooms.filter { room in
            guard filter.admits(chatType: room.chatType) else { return false }
            // `notificationCount` is Reddit's unread count for the room.
            guard !unreadOnly || room.notificationCount > 0 else { return false }
            return true
        }
    }
}
