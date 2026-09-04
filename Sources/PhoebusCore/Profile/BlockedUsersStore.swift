import Foundation

/// The signed-in account's repository, for screens built without one
/// (settings). Set by the account manager on every switch.
public enum ActiveRedditRepository {
    public nonisolated(unsafe) static var provider: () -> RedditRepository? = { nil }
}

/// A user on the account's Reddit block list (`/prefs/blocked`).
public struct RedditBlockedUser: Decodable, Sendable, Equatable, Identifiable {
    public let name: String
    public let id: String?
    public let date: Double?
}

/// The signed-in account's Reddit block list, which Apollo's "Blocked
/// Users" shows and "Blocked Users: Collapse / Hide" applies to comments.
/// Kept per account so a switch never shows another account's blocks.
public enum BlockedUsersStore {
    /// Lowercased username → that account's blocked usernames.
    public static let storage = SettingsStore<[String: [String]]>(
        key: "com.pendo324.Phoebus.redditBlockedUsers") { [:] }

    private static var account: String? {
        FavoriteSubredditsAccountContext.currentUsernameProvider()?.lowercased()
    }

    /// The active account's blocked usernames, as Reddit spells them.
    public static func names() -> [String] {
        guard let account else { return [] }
        return storage.load()[account] ?? []
    }

    public static func lowercasedNames() -> Set<String> {
        Set(names().map { $0.lowercased() })
    }

    public static func replace(with names: [String]) {
        guard let account else { return }
        var all = storage.load()
        all[account] = names
        storage.save(all)
    }

    public static func add(_ name: String) {
        var list = names()
        guard !list.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        list.append(name)
        replace(with: list)
    }

    public static func remove(_ name: String) {
        replace(with: names().filter { $0.caseInsensitiveCompare(name) != .orderedSame })
    }

    /// `/prefs/blocked`: `{"kind": "UserList", "data": {"children": [...]}}`.
    public static func parse(_ data: Data) throws -> [RedditBlockedUser] {
        struct Response: Decodable {
            struct List: Decodable { let children: [RedditBlockedUser] }
            let data: List
        }
        return try JSONDecoder().decode(Response.self, from: data).data.children
    }
}
