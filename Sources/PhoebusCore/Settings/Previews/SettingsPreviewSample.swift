import Foundation

/// The sample post and comment thread the settings previews draw with the
/// app's own rows (Phoebus-only; neither Apollo nor Reborn previews posts or
/// comments).
///
/// Both are built from Reddit-shaped JSON and decoded by the code that decodes
/// live listings, so a preview row sees the same model a feed row does. Names,
/// scores and text are fixed; ages are offsets from `now`, so "3h" stays "3h".
public enum SettingsPreviewSample {
    // MARK: - Post

    public static let postID = "phebuspreview"
    public static let postFullname = "t3_phebuspreview"
    public static let subreddit = "Bread"
    public static let postAuthor = "sample_poster"
    /// Key of the sample image in the post's `media_metadata`; the body names it
    /// the way a real text post does.
    private static let imageKey = "previewimage"

    /// A self post with an embedded picture (its thumbnail), flairs, awards and
    /// a small poll, so one post shows every Posts setting. `imageURL` is a
    /// local file: a preview never fetches anything.
    public static func post(imageURL: URL, now: Date = Date()) -> RedditPost {
        let image: [String: Any] = [
            "status": "valid", "e": "Image", "m": "image/png",
            "s": ["u": imageURL.absoluteString, "x": 640, "y": 480] as [String: Any],
        ]
        let poll: [String: Any] = [
            "options": [["id": "1", "text": "Rye"], ["id": "2", "text": "Sourdough"]],
            "total_vote_count": 124,
            "voting_end_timestamp": now.addingTimeInterval(2 * 86_400).timeIntervalSince1970 * 1000,
        ]
        let json: [String: Any] = [
            "id": postID, "name": postFullname, "subreddit_id": "t5_phebuspreview",
            "title": "Found this loaf at the market this morning, can anyone tell what kind of bread it is?",
            "author": postAuthor, "subreddit": subreddit,
            "selftext": "![img](\(imageKey))",
            "permalink": "/r/\(subreddit)/comments/\(postID)/sample/",
            "score": 842, "upvote_ratio": 0.96, "num_comments": 87,
            "created_utc": now.addingTimeInterval(-3 * 3600).timeIntervalSince1970,
            "is_self": true, "over_18": false, "spoiler": false, "stickied": false, "saved": false,
            "thumbnail": "self",
            "link_flair_text": "Question", "link_flair_background_color": "#0079D3", "link_flair_text_color": "#FFFFFF",
            "author_flair_text": "Baker", "author_flair_background_color": "#7E53C1", "author_flair_text_color": "#FFFFFF",
            "total_awards_received": 3,
            "media_metadata": [imageKey: image],
            "poll_data": poll,
        ]
        return decode(RedditPost.self, from: json)
    }

    // MARK: - Thread

    /// The signed-in user the thread's own comment stands in for.
    public static let ownUsername = "sample_you"
    /// The followed user whose reply is highlighted. Lowercased, as
    /// `FollowedUsernames` holds them.
    public static let followedUsernames: Set<String> = ["sample_pal"]
    public static let newAccountUsername = "sample_new"
    /// The comment drawn as new since the last visit.
    public static let newCommentIDs: Set<String> = ["phebuspvc2"]
    /// The removed comment's fullname, which `archivedComments` holds a copy of.
    public static let removedCommentFullname = "t1_phebuspvc5"

    /// What an account lookup would answer for the sample commenters: the new
    /// account is days old, the others years.
    public static func accountCreated(for username: String, now: Date = Date()) -> Date {
        now.addingTimeInterval(username == newAccountUsername ? -3 * 86_400 : -900 * 86_400)
    }

    /// The archive's copy of the removed comment, as Deleted Comments would
    /// recover it.
    public static let archivedComments: [String: ArchivedComment] = [
        removedCommentFullname: ArchivedComment(
            fullname: removedCommentFullname, author: "sample_baker",
            body: "It's a seeded rye, you can smell the caraway.", score: 5, reason: .moderatorRemoved),
    ]

    /// Five comments down one chain of replies, built by the tree builder the
    /// comments screen uses, so Auto Collapse Child Comments, Collapse
    /// AutoModerator and Collapse Pinned Comments fold the same rows they do
    /// in a thread:
    ///
    /// 1. a pinned AutoModerator comment
    /// 2. a new comment from a new account (the roots end here)
    /// 3. its reply, from a followed user, edited and flaired
    /// 4. a reply from the signed-in user
    /// 5. a removed comment
    public static func thread(autoCollapseChildren: Bool = false, collapsePinned: Bool = false,
                              collapseAutoModerator: Bool = false, now: Date = Date()) -> [CommentTreeNode] {
        func ago(_ minutes: Double) -> Double { now.addingTimeInterval(-minutes * 60).timeIntervalSince1970 }
        func comment(_ number: Int, parent: String, author: String, body: String, score: Int, minutesAgo: Double,
                     replies: [[String: Any]] = [], extra: [String: Any] = [:]) -> [String: Any] {
            let nested: Any = replies.isEmpty ? "" : ["kind": "Listing", "data": ["children": replies]]
            var data: [String: Any] = [
                "id": "phebuspvc\(number)", "name": "t1_phebuspvc\(number)", "author": author, "body": body,
                "score": score, "created_utc": ago(minutesAgo), "parent_id": parent, "link_id": postFullname,
                "saved": false, "score_hidden": false, "stickied": false, "subreddit": subreddit,
                "replies": nested,
            ]
            for (key, value) in extra { data[key] = value }
            return ["kind": "t1", "data": data]
        }
        let removed = comment(5, parent: "t1_phebuspvc4", author: "[deleted]", body: "[removed]", score: 3, minutesAgo: 6)
        let own = comment(4, parent: "t1_phebuspvc3", author: ownUsername, body: "Thanks, I'll stop by tomorrow.",
                          score: 7, minutesAgo: 12, replies: [removed])
        let followed = comment(3, parent: "t1_phebuspvc2", author: "sample_pal", body: "Same bakery, they bake it on Fridays.",
                               score: 12, minutesAgo: 25, replies: [own],
                               extra: ["edited": ago(20), "author_flair_text": "Fan",
                                       "author_flair_background_color": "#7E53C1", "author_flair_text_color": "#FFFFFF"])
        let newcomer = comment(2, parent: postFullname, author: newAccountUsername,
                               body: "Looks like a rye to me, check the crust.", score: 48, minutesAgo: 40, replies: [followed])
        let pinned = comment(1, parent: postFullname, author: "AutoModerator", body: "Please keep replies civil.",
                             score: 1, minutesAgo: 175, extra: ["stickied": true])
        let data = try! JSONSerialization.data(withJSONObject: [pinned, newcomer])
        let values = try! JSONDecoder().decode([JSONValue].self, from: data)
        return CommentTreeBuilder.build(from: values, autoCollapse: autoCollapseChildren,
                                        autoCollapsePinned: collapsePinned, autoCollapseAutoModerator: collapseAutoModerator,
                                        parentID: postFullname)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: [String: Any]) -> T {
        // The inputs are literals in this file; a failure here is a bug in the sample.
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder.reddit.decode(T.self, from: data)
    }
}

extension AuthorHighlight {
    /// `current` for the settings previews: the sample thread's own and followed
    /// users stand in for the signed-in account's, which a preview must not read.
    public static func sample(author: String, distinguished: String?, settings: GeneralSettings) -> AuthorHighlight {
        resolve(author: author, distinguished: distinguished,
                ownUsername: SettingsPreviewSample.ownUsername,
                followedUsernames: SettingsPreviewSample.followedUsernames,
                highlightOwn: settings.highlightOwnUsername,
                highlightFollowed: settings.highlightFollowedUsers)
    }
}
