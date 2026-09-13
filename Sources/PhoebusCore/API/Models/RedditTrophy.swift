import Foundation

/// A trophy awarded to a Reddit account (e.g. "Verified
/// Email", "One-Year Club", subreddit-specific trophies).
public struct RedditTrophy: Decodable, Sendable, Identifiable {
    public let name: String
    public let description: String?
    public let iconURL: String?
    public let awardID: String?

    public var id: String { awardID ?? name }

    enum CodingKeys: String, CodingKey {
        case name = "name"
        case description = "description"
        case iconURL = "icon_70"
        case awardID = "award_id"
    }
}

struct TrophyListResponse: Decodable {
    let data: TrophyData
    struct TrophyData: Decodable {
        let trophies: [RedditThing<RedditTrophy>]
    }
}

/// A subreddit's rules.
public struct SubredditRule: Decodable, Sendable, Identifiable, Hashable {
    public let shortName: String
    public let description: String
    public let violationReason: String

    public var id: String { shortName }

    enum CodingKeys: String, CodingKey {
        case shortName = "short_name"
        case description
        case violationReason = "violation_reason"
    }
}
