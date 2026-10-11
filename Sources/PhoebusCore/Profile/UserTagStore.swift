import Foundation

/// A short label and colour the user puts on another Reddit user, shown as
/// a pill after their name. Phoebus-only (neither Apollo nor Reborn has
/// user tags); local to this device, never sent to Reddit.
public struct UserTag: Codable, Equatable, Sendable, Identifiable {
    /// The name as it was first tagged, for display.
    public var username: String
    public var text: String
    public var color: UserTagColor

    public var id: String { UserTags.key(for: username) }

    public init(username: String, text: String, color: UserTagColor) {
        self.username = username
        self.text = text
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        text = try container.decode(String.self, forKey: .text)
        // A colour this build doesn't know (a newer backup) keeps the tag.
        color = (try? container.decode(UserTagColor.self, forKey: .color)) ?? .blue
    }
}

/// The tag palette: system tints that read on light, dark and themed
/// backgrounds with white text.
public enum UserTagColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case red, orange, green, teal, blue, indigo, purple, gray

    public var id: String { rawValue }

    public var displayName: String { rawValue.capitalized }

    public var hex: String {
        switch self {
        case .red: return "E5484D"
        case .orange: return "E8730C"
        case .green: return "2E9E4F"
        case .teal: return "1F8FA6"
        case .blue: return "2F7BEA"
        case .indigo: return "5856D6"
        case .purple: return "9B4DCA"
        case .gray: return "7A7C82"
        }
    }
}

/// Every tag, keyed by lowercased username: Reddit usernames are
/// case-insensitive and the API doesn't always return the same casing.
public struct UserTags: StoredSettingsModel {
    public var byUser: [String: UserTag] = [:]

    /// Longest tag text kept; the pill stays one short line in a byline.
    public static let maxLength = 24

    public init() {}

    public static let store = SettingsStore<UserTags>(key: "com.pendo324.Phoebus.userTags") { UserTags() }

    static func key(for username: String) -> String {
        normalizedUsername(username).lowercased()
    }

    /// Strips whitespace and a typed `u/` or `/u/` prefix.
    public static func normalizedUsername(_ username: String) -> String {
        var name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/u/", "u/"] where name.lowercased().hasPrefix(prefix) {
            name.removeFirst(prefix.count)
            break
        }
        return name
    }

    /// Trimmed and clipped to `maxLength` characters.
    public static func normalizedText(_ text: String) -> String {
        let collapsed = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    public func tag(for username: String) -> UserTag? {
        byUser.isEmpty ? nil : byUser[Self.key(for: username)]
    }

    /// Sets or replaces a user's tag; empty text removes it. A retag keeps
    /// the casing the user was first tagged with.
    public mutating func setTag(_ text: String, color: UserTagColor, for username: String) {
        let name = Self.normalizedUsername(username)
        let label = Self.normalizedText(text)
        let key = Self.key(for: name)
        guard !name.isEmpty, name != "[deleted]" else { return }
        guard !label.isEmpty else {
            byUser.removeValue(forKey: key)
            return
        }
        byUser[key] = UserTag(username: byUser[key]?.username ?? name, text: label, color: color)
    }

    public mutating func removeTag(for username: String) {
        byUser.removeValue(forKey: Self.key(for: username))
    }

    /// For the settings list: alphabetical by username, case-insensitively.
    public var sorted: [UserTag] {
        byUser.values.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }
}

/// Entry points for non-view code; views read `@Setting(UserTags.self)`,
/// whose shared in-memory copy makes a row's lookup one dictionary read and
/// refreshes visible rows when a tag changes. The key carries the app's
/// own prefix, so settings backups include it.
public enum UserTagStore {
    public static var storage: SettingsStore<UserTags> { UserTags.store }

    public static func load() -> UserTags { storage.load() }

    public static func tag(for username: String) -> UserTag? { load().tag(for: username) }

    public static func setTag(_ text: String, color: UserTagColor, for username: String) {
        storage.update { $0.setTag(text, color: color, for: username) }
    }

    public static func removeTag(for username: String) {
        storage.update { $0.removeTag(for: username) }
    }
}
