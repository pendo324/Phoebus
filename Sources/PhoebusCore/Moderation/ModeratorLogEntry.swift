import Foundation

/// An entry in a subreddit's moderation action log (e.g. "Removed Comment",
/// "Approved Post", "Marked Post Spoiler", using Apollo's action-type
/// strings).
public struct ModeratorLogEntry: Decodable, Sendable, Identifiable {
    public let id: String
    public let mod: String
    public let action: String
    public let details: String?
    public let targetAuthor: String?
    public let created: Date

    enum CodingKeys: String, CodingKey {
        case id, mod, action, details
        case targetAuthor = "target_author"
        case created = "created_utc"
    }
}

struct ModeratorLogResponse: Decodable {
    let data: ListData
    struct ListData: Decodable {
        let children: [RedditThing<ModeratorLogEntry>]
        /// The pagination cursor; without it `fetchModeratorLog` could not fetch
        /// page 2 and would truncate a log to its first ~25 entries.
        let after: String?
    }
}
