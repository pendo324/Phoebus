import Foundation

/// The Filters tester's typed-in values, turned into the models the filters
/// run on. The card owns one of these in `@State`, so nothing typed is ever
/// saved or sent; the fields mirror what the filter kinds can test.
///
/// The post and comment fields are separate so switching the card's Post /
/// Comment control does not clear the other.
public struct FilterTesterInput: Equatable, Sendable {
    // Post fields.
    public var title = ""
    public var subreddit = ""
    public var author = ""
    public var link = ""
    public var flair = ""
    public var score: Int?
    public var comments: Int?
    public var awards: Int?
    public var nsfw = false
    public var spoiler = false

    // Comment fields.
    public var commentText = ""
    public var commentAuthor = ""
    public var commentSubreddit = ""
    public var commentScore: Int?

    public init() {}

    /// Whether a post test has anything to run on. Numbers and tags count: an
    /// NSFW-only input is exactly what a Tag Filter test needs.
    public var hasPostInput: Bool {
        !title.isEmpty || !subreddit.isEmpty || !author.isEmpty || !link.isEmpty || !flair.isEmpty
            || score != nil || comments != nil || awards != nil || nsfw || spoiler
    }

    /// Whether a comment test has anything to run on.
    public var hasCommentInput: Bool {
        !commentText.isEmpty || !commentAuthor.isEmpty || !commentSubreddit.isEmpty || commentScore != nil
    }

    /// The post numbers left blank. A blank field is "not entered", not 0, so
    /// Post Rules bounding it are skipped rather than run against a made-up value.
    public var untestedPostFields: Set<PostRuleField> {
        var fields: Set<PostRuleField> = []
        if score == nil { fields.insert(.score) }
        if comments == nil { fields.insert(.comments) }
        if awards == nil { fields.insert(.awards) }
        return fields
    }

    /// Whether the comment's Score was entered; Comment Rules' score ranges
    /// only run when it was.
    public var commentScoreEntered: Bool { commentScore != nil }

    /// The typed link as a URL: a bare domain gets `https://` and a trailing
    /// slash, so the domain filter and Post Filters' link keywords can match it.
    public var linkURL: String? {
        let raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.contains("://") { return raw }
        return "https://" + raw + (raw.hasSuffix("/") ? "" : "/")
    }

    /// The post the filters see, decoded the way the API decodes one so the
    /// same optional fields and defaults apply.
    public func post() -> RedditPost {
        var json: [String: Any] = [
            "id": "tester", "name": "t3_tester", "title": title, "author": author,
            "subreddit": subreddit, "permalink": "/r/\(subreddit)/comments/tester/",
            "score": score ?? 0, "num_comments": comments ?? 0,
            "created_utc": 0, "is_self": linkURL == nil,
            "over_18": nsfw, "spoiler": spoiler, "stickied": false, "saved": false,
        ]
        if let url = linkURL { json["url"] = url }
        if !flair.isEmpty { json["link_flair_text"] = flair }
        if let awards { json["total_awards_received"] = awards }
        return decode(json, as: RedditPost.self)
    }

    /// The comment the filters see; its subreddit scope comes from
    /// `commentSubreddit`, which the caller passes to the explanation.
    public func comment() -> RedditComment {
        decode([
            "id": "tester", "name": "t1_tester", "author": commentAuthor, "body": commentText,
            "score": commentScore ?? 0, "created_utc": 0, "parent_id": "t3_tester",
            "link_id": "t3_tester", "saved": false, "score_hidden": false, "stickied": false,
        ], as: RedditComment.self)
    }

    private func decode<T: Decodable>(_ json: [String: Any], as type: T.Type) -> T {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder.reddit.decode(T.self, from: data)
    }
}
