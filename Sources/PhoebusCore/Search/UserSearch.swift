import Foundation

/// One account from a user search (`search?type=user`), or the exact
/// lookup (`/user/<name>/about`). Suspended accounts come back with
/// only a name, so every other field is optional.
public struct UserSearchResult: Decodable, Sendable, Equatable, Identifiable {
    public let name: String
    public let iconURL: URL?
    public let linkKarma: Int
    public let commentKarma: Int
    public let created: Date?
    public let isSuspended: Bool

    public var id: String { name.lowercased() }
    public var karma: Int { linkKarma + commentKarma }

    public init(name: String, iconURL: URL? = nil, linkKarma: Int = 0, commentKarma: Int = 0,
                created: Date? = nil, isSuspended: Bool = false) {
        self.name = name
        self.iconURL = iconURL
        self.linkKarma = linkKarma
        self.commentKarma = commentKarma
        self.created = created
        self.isSuspended = isSuspended
    }

    enum CodingKeys: String, CodingKey {
        case name
        case iconImage = "icon_img"
        case snoovatarImage = "snoovatar_img"
        case linkKarma = "link_karma"
        case commentKarma = "comment_karma"
        case created = "created_utc"
        case isSuspended = "is_suspended"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        func url(_ key: CodingKeys) -> URL? {
            let raw = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
            guard let raw, !raw.isEmpty else { return nil }
            return URL(string: raw.replacingOccurrences(of: "&amp;", with: "&"))
        }
        iconURL = url(.iconImage) ?? url(.snoovatarImage)
        linkKarma = (try? c.decodeIfPresent(Int.self, forKey: .linkKarma)) ?? 0
        commentKarma = (try? c.decodeIfPresent(Int.self, forKey: .commentKarma)) ?? 0
        created = ((try? c.decodeIfPresent(Double.self, forKey: .created)) ?? nil)
            .map { Date(timeIntervalSince1970: $0) }
        isSuspended = (try? c.decodeIfPresent(Bool.self, forKey: .isSuspended)) ?? false
    }
}

/// Phoebus addition: the Search tab's Users section. Neither Apollo nor
/// Reborn searches accounts.
public enum UserSearch {
    private struct Thing: Decodable {
        let kind: String?
        let data: UserSearchResult?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decodeIfPresent(String.self, forKey: .kind)
            data = try? c.decodeIfPresent(UserSearchResult.self, forKey: .data)
        }

        enum CodingKeys: String, CodingKey { case kind, data }
    }

    private struct Listing: Decodable {
        struct Page: Decodable { let children: [Thing] }
        let data: Page?
    }

    /// The `t2` accounts of a user-search listing, in Reddit's order.
    /// Reddit answers an empty search with `{}`, which parses as none.
    public static func parse(_ data: Data) throws -> [UserSearchResult] {
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        return (listing.data?.children ?? []).compactMap { $0.kind == "t2" ? $0.data : nil }
    }

    /// One `t2` thing, as `/user/<name>/about` returns it.
    public static func parseAccount(_ data: Data) -> UserSearchResult? {
        guard let thing = try? JSONDecoder().decode(Thing.self, from: data), thing.kind == "t2" else { return nil }
        return thing.data
    }

    /// What was typed, without a leading `u/` or `/u/`.
    public static func normalizedQuery(_ text: String) -> String {
        var query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/u/", "u/", "/user/", "user/"] where query.lowercased().hasPrefix(prefix) {
            query.removeFirst(prefix.count)
            break
        }
        return query
    }

    /// Whether `text` could be a username (3-20 letters, digits, `_`
    /// or `-`), so an exact lookup is worth a request.
    public static func isPossibleUsername(_ text: String) -> Bool {
        (3...20).contains(text.count)
            && text.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "_" || $0 == "-" }
    }

    /// Search often misses an exact name, so the exact account goes
    /// first, replacing its copy further down.
    public static func merging(exact: UserSearchResult?, into results: [UserSearchResult]) -> [UserSearchResult] {
        guard let exact else { return results }
        return [exact] + results.filter { $0.id != exact.id }
    }

    /// Drops the account's blocked users.
    public static func visible(_ results: [UserSearchResult], blocked: Set<String>) -> [UserSearchResult] {
        results.filter { !blocked.contains($0.id) }
    }

    /// "12.3k karma · 15y", or "Suspended".
    public static func subtitle(for user: UserSearchResult, now: Date = Date()) -> String {
        guard !user.isSuspended else { return "Suspended" }
        var parts = ["\(GoogleSearchRedditInfo.compactCount(user.karma)) karma"]
        if let created = user.created {
            parts.append(GoogleSearchRedditInfo.compactAge(created, now: now))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
