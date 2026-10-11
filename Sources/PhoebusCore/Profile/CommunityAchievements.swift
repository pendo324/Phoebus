import Foundation

/// A user's per-community achievements (e.g. "Elder" in r/pics), read from
/// Shreddit's `UserCommunityAchievements` GraphQL operation.
public struct CommunityAchievements: Sendable, Equatable {
    public struct Trophy: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var imageURL: URL?
        /// GraphQL `__typename`; varies by trophy kind and is only kept for display logic.
        public var typename: String?

        public init(id: String, name: String, imageURL: URL? = nil, typename: String? = nil) {
            self.id = id
            self.name = name
            self.imageURL = imageURL
            self.typename = typename
        }

        /// The Badge Book catalog entry sharing this trophy's id, if any.
        public var catalogEntry: AchievementDefinition? {
            AchievementCatalog.all.first { $0.id == id }
        }
    }

    public var totalUnlocked: Int
    public var trophies: [Trophy]

    public init(totalUnlocked: Int = 0, trophies: [Trophy] = []) {
        self.totalUnlocked = totalUnlocked
        self.trophies = trophies
    }

    public static let empty = CommunityAchievements()
}

public enum CommunityAchievementsService {
    public static let operationName = "UserCommunityAchievements"

    public static func variables(username: String, subredditID: String, imageMaxWidth: Int = 100) -> [String: Any] {
        ["username": username, "subredditId": normalizedSubredditID(subredditID), "imageMaxWidth": imageMaxWidth]
    }

    /// Shreddit wants the `t5_` fullname; the REST `subreddit_id` already has it.
    public static func normalizedSubredditID(_ raw: String) -> String {
        raw.hasPrefix("t5_") ? raw : "t5_" + raw
    }

    public static func referer(subreddit: String?) -> String {
        guard let subreddit, !subreddit.isEmpty else { return "https://www.reddit.com/" }
        return "https://www.reddit.com/r/\(subreddit)/"
    }

    /// Tolerant of trophy kinds this code has never seen: any entry with an id
    /// and name is kept, anything else is skipped. A null `redditorInfoByName`
    /// (unknown user, anonymous caller) reads as "no achievements".
    public static func parse(_ json: [String: Any]) -> CommunityAchievements {
        let data = json["data"] as? [String: Any]
        let redditor = data?["redditorInfoByName"] as? [String: Any]
        guard let trophyCase = redditor?["trophyCase"] as? [String: Any] else { return .empty }
        let entries = trophyCase["trophiesBySubredditId"] as? [[String: Any]] ?? []
        let trophies: [CommunityAchievements.Trophy] = entries.compactMap { entry in
            guard let id = entry["id"] as? String, !id.isEmpty,
                  let name = entry["name"] as? String, !name.isEmpty else { return nil }
            let urlString = (entry["gridImage"] as? [String: Any])?["url"] as? String
            let imageURL = urlString.flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) }
            return CommunityAchievements.Trophy(id: id, name: name, imageURL: imageURL,
                                                typename: entry["__typename"] as? String)
        }
        return CommunityAchievements(totalUnlocked: trophyCase["totalUnlocked"] as? Int ?? 0, trophies: trophies)
    }

    public static func parse(_ data: Data) -> CommunityAchievements {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .empty }
        return parse(json)
    }

    /// One request per (username, subreddit) for the life of the process.
    public static func fetch(username: String, subredditID: String, subreddit: String?,
                             session: WebSessionCredential) async throws -> CommunityAchievements {
        let key = CommunityAchievementsCache.key(username: username, subredditID: subredditID)
        if let cached = await CommunityAchievementsCache.shared.value(for: key) { return cached }
        let json = try await ModmailWebService.perform(
            operation: operationName,
            variables: variables(username: username, subredditID: subredditID),
            session: session,
            referer: referer(subreddit: subreddit))
        let result = parse(json)
        await CommunityAchievementsCache.shared.store(result, for: key)
        return result
    }
}

public actor CommunityAchievementsCache {
    public static let shared = CommunityAchievementsCache()
    private var entries: [String: CommunityAchievements] = [:]

    public static func key(username: String, subredditID: String) -> String {
        username.lowercased() + "|" + CommunityAchievementsService.normalizedSubredditID(subredditID).lowercased()
    }

    public func value(for key: String) -> CommunityAchievements? { entries[key] }
    public func store(_ value: CommunityAchievements, for key: String) { entries[key] = value }
}
