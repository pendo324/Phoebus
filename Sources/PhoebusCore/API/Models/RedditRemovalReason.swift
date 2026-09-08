import Foundation

/// One of a subreddit's moderator-defined "removal reasons": a canned
/// template moderators can apply when removing a post/comment,
/// optionally sent to the removed user as a message. Apollo has a
/// dedicated screen for managing these, and applies one via
/// `api/v1/modactions/removal_reasons` when removing content.
public struct RedditRemovalReason: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let message: String

    public init(id: String, title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case message
    }

    /// Reddit's `api/v1/{subreddit}/removal_reasons` GET response shape is
    /// `{"order": [id, ...], "data": {id: {id, title, message}}}` rather than
    /// a flat array, so it is decoded manually from the raw JSON object.
    public static func parseList(from json: [String: JSONValue]) -> [RedditRemovalReason] {
        guard case .array(let order)? = json["order"],
              case .object(let data)? = json["data"] else { return [] }
        return order.compactMap { entry -> RedditRemovalReason? in
            guard case .string(let reasonID) = entry,
                  case .object(let entryData)? = data[reasonID],
                  case .string(let title)? = entryData["title"] else { return nil }
            var message = ""
            if case .string(let msg)? = entryData["message"] {
                message = msg
            }
            return RedditRemovalReason(id: reasonID, title: title, message: message)
        }
    }
}

/// Apollo's "Notify user via…" choices for a logged removal reason.
/// Raw values are Reddit's `type` on `removal_link_message` /
/// `removal_comment_message`.
public enum RemovalNotifyKind: String, CaseIterable, Sendable {
    /// Reddit posts the stickied reply as the moderator.
    case publicReply = "public"
    /// Reborn #515: Reddit posts the stickied reply as u/<Sub>-ModTeam.
    case publicAsSubreddit = "public_as_subreddit"
    case modmailFromSubreddit = "private"
    case modmailFromYou = "private_exposed"

    /// Menu title, as Apollo words it ("Public Sticky" on a post,
    /// "Public Reply" on a comment).
    public func title(forComment isComment: Bool) -> String {
        switch self {
        case .publicReply: return isComment ? "Public Reply" : "Public Sticky"
        case .publicAsSubreddit: return isComment ? "Public Reply from Subreddit" : "Public Sticky from Subreddit"
        case .modmailFromSubreddit: return "Mod Mail from Subreddit"
        case .modmailFromYou: return "Mod Mail from You"
        }
    }
}
