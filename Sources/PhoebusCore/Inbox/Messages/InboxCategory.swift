import Foundation

/// The Inbox tab's top-level "Boxes" menu of message categories (Apollo's),
/// each pushing an inbox screen for one category: inbox, unread messages,
/// comment replies, post replies, username mentions, messages, moderator
/// mail.
///
/// `apiPath` values are Reddit's `/message/<where>` listings, the same
/// tabs old Reddit's inbox has: `inbox` (all), `unread`, `messages`
/// (private messages only), `comments` (comment replies), `selfreply`
/// (post replies) and `mentions`.
public enum InboxCategory: String, CaseIterable, Sendable, Identifiable {
    case inbox
    case unreadMessages
    case commentReplies
    case postReplies
    case usernameMentions
    case messages
    case moderatorMail

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .unreadMessages: return "Unread"
        case .commentReplies: return "Comment Replies"
        case .postReplies: return "Post Replies"
        case .usernameMentions: return "Mentions"
        case .messages: return "Messages"
        case .moderatorMail: return "Moderator Mail"
        }
    }

    /// The Reddit `/message/<where>` path segment this category fetches from.
    public var apiPath: String {
        switch self {
        case .inbox:
            return "inbox"
        case .unreadMessages:
            return "unread"
        case .commentReplies:
            return "comments"
        case .postReplies:
            return "selfreply"
        case .usernameMentions:
            return "mentions"
        case .messages:
            return "messages"
        case .moderatorMail:
            // With `UnifyModmailInInbox`, modmail lives in the Inbox tab; this case
            // completes the Boxes menu and routes to the modmail fetch rather than a
            // message listing.
            return "inbox"
        }
    }
}
