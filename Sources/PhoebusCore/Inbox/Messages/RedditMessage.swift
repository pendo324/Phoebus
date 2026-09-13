import Foundation

/// A private message or comment-reply notification.
public struct RedditMessage: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let author: String
    public let subject: String
    public let body: String
    public let created: Date
    public let new: Bool
    public let wasComment: Bool
    public let subreddit: String?
    public let parentID: String?
    /// Reddit's `link_title` - the post title a comment-reply
    /// message refers to.
    public let linkTitle: String?
    /// Reddit's `context` - permalink for the comment a reply message
    /// is about (already includes `?context=N`).
    public let context: String?
    /// Replies to this message, oldest first. Reddit sends this as either
    /// a nested Listing object or an empty string when there are none.
    public let replies: [RedditMessage]
    /// `data.first_message_name`: fullname of the thread's root message.
    /// Present on replies, nil on the root, used to group a flat inbox
    /// listing back into threads.
    public let firstMessageName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, author, subject, body, new, subreddit, context, replies
        case created = "created_utc"
        case createdLocal = "created"
        case wasComment = "was_comment"
        case parentID = "parent_id"
        case linkTitle = "link_title"
        case firstMessageName = "first_message_name"
    }

    /// Custom decode for two reasons. Reddit returns `"replies": ""` for a
    /// message with none and a nested
    /// `{"kind":"Listing","data":{"children":[...]}}` when it has some,
    /// which synthesised decoding handles neither of. And every field but the
    /// ids is read leniently, so one oddly-typed field (a chat room or system
    /// notice) doesn't drop the whole message from the inbox.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        func text(_ key: CodingKeys) -> String? { (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil }
        author = text(.author) ?? ""
        subject = text(.subject) ?? ""
        body = text(.body) ?? ""
        created = ((try? container.decodeIfPresent(Date.self, forKey: .created)) ?? nil)
            ?? ((try? container.decodeIfPresent(Date.self, forKey: .createdLocal)) ?? nil)
            ?? Date(timeIntervalSince1970: 0)
        new = ((try? container.decodeIfPresent(Bool.self, forKey: .new)) ?? nil) ?? false
        wasComment = ((try? container.decodeIfPresent(Bool.self, forKey: .wasComment)) ?? nil) ?? false
        subreddit = text(.subreddit)
        parentID = text(.parentID)
        linkTitle = text(.linkTitle)
        context = text(.context)
        firstMessageName = text(.firstMessageName)
        replies = (try? container.decode(RepliesListing.self, forKey: .replies))?.messages ?? []
    }

    public init(
        id: String,
        name: String,
        author: String,
        subject: String,
        body: String,
        created: Date,
        new: Bool = false,
        wasComment: Bool = false,
        subreddit: String? = nil,
        parentID: String? = nil,
        linkTitle: String? = nil,
        context: String? = nil,
        replies: [RedditMessage] = [],
        firstMessageName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.subject = subject
        self.body = body
        self.created = created
        self.new = new
        self.wasComment = wasComment
        self.subreddit = subreddit
        self.parentID = parentID
        self.linkTitle = linkTitle
        self.context = context
        self.replies = replies
        self.firstMessageName = firstMessageName
    }

    /// The whole conversation, root first, flattened depth-first.
    ///
    /// Reddit nests replies arbitrarily deep, but a PM thread reads as a
    /// linear conversation, so the nesting is flattened rather than indented.
    public var thread: [RedditMessage] {
        [self] + replies.flatMap(\.thread)
    }

    /// Wraps Reddit's nested `Listing` of replies.
    private struct RepliesListing: Decodable {
        let messages: [RedditMessage]

        private struct Wrapper: Decodable {
            let data: Child?
            struct Child: Decodable {
                let children: [Kinded]?
            }
            struct Kinded: Decodable {
                let data: RedditMessage?
            }
        }

        init(from decoder: Decoder) throws {
            let wrapper = try Wrapper(from: decoder)
            messages = wrapper.data?.children?.compactMap(\.data) ?? []
        }
    }

    /// The post and comment IDs a comment-reply message points at,
    /// parsed from `context`.
    ///
    /// Returns nil for a plain private message (no context) or a
    /// context that is not a comment permalink.
    public var commentTarget: (subreddit: String, postID: String, commentID: String)? {
        guard let context, let url = URL(string: "https://www.reddit.com" + context) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        // /r/<sub>/comments/<postID>/<slug>/<commentID>
        //   r+0  r+1    r+2      r+3      r+4      r+5
        // The slug is always present in Reddit's own context links, so the
        // comment id is the component AFTER it.
        guard let r = parts.firstIndex(of: "r"), parts.count > r + 5,
              parts[r + 2] == "comments" else { return nil }
        return (parts[r + 1], parts[r + 3], parts[r + 5])
    }
}
