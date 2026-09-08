import Foundation

/// A single entry in a subreddit's banned/muted/approved-submitter list
/// — Reddit's /about/banned, /about/muted, /about/contributors
/// endpoints all return this shape.
public struct ModeratorListedUser: Decodable, Sendable, Identifiable {
    public let name: String
    public let note: String?
    public let banReason: String?
    public let daysLeft: Int?

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, note
        case banReason = "ban_reason"
        case daysLeft = "days_left"
    }
}

struct ModeratorUserListResponse: Decodable {
    let data: ListData
    struct ListData: Decodable {
        let children: [ModeratorListedUser]
    }
}
