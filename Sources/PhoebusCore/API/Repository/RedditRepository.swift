import Foundation

/// Errors surfaced by `RedditRepository` beyond raw networking/decoding
/// failures (those propagate from `RedditAPIClient` unchanged).
public enum RedditRepositoryError: Error, Sendable {
    /// `fetchPost` found no t3 child in the comments-endpoint response
    /// (e.g. the post was deleted or the ID/subreddit no longer match).
    case postNotFound
}

/// High-level feed/post operations covering the feed, voting, and
/// subscribe surface.
public actor RedditRepository {
    let client: RedditAPIClient

    /// `/r/<sub>/comments/<id>`, or `/comments/<id>` when the subreddit
    /// is unknown (a `reddit.com/comments/<id>` share link); Reddit
    /// resolves both.
    static func commentsPath(subreddit: String, postID: String) -> String {
        subreddit.isEmpty ? "/comments/\(postID)" : "/r/\(subreddit)/comments/\(postID)"
    }

    public init(client: RedditAPIClient) {
        self.client = client
    }

    /// Fetch a subreddit (or /r/all, /r/popular, multi) listing.
    /// `timeframe` only applies to "top"/"controversial" sorts,
    /// matching Reddit's `t=` query parameter.
    public func fetchListing(subreddit: String, sort: String = "hot", timeframe: String? = nil, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        let path = subreddit.isEmpty ? "/\(sort)" : "/r/\(subreddit)/\(sort)"
        var parameters: [String: String] = [:]
        if let timeframe, sort == "top" || sort == "controversial" {
            parameters["t"] = timeframe
        }
        return try await client.getListing(path: path, parameters: parameters, after: after, limit: limit)
    }

    /// Fetch a random subreddit's name via Reddit's own `/random`
    /// endpoint. Unlike a browser hitting `reddit.com/r/random` (a
    /// redirect), the OAuth API returns the picked subreddit's hot
    /// listing directly, so the name is read off the first post.
    public func fetchRandomSubredditName() async throws -> String {
        let listing = try await client.getListing(path: "/random", after: nil, limit: 1)
        guard let child = listing.data.children.first else {
            throw RedditRepositoryError.postNotFound
        }
        let plain = JSONValue.object(child.data.raw).plain
        guard let subredditValue = plain as? [String: Any], let subreddit = subredditValue["subreddit"] as? String else {
            throw RedditRepositoryError.postNotFound
        }
        return subreddit
    }

    /// Fetch a random NSFW subreddit's name via Reddit's own
    /// `/randnsfw` endpoint. Same mechanism as
    /// `fetchRandomSubredditName`, different endpoint.
    public func fetchRandomNSFWSubredditName() async throws -> String {
        let listing = try await client.getListing(path: "/randnsfw", after: nil, limit: 1)
        guard let child = listing.data.children.first else {
            throw RedditRepositoryError.postNotFound
        }
        let plain = JSONValue.object(child.data.raw).plain
        guard let subredditValue = plain as? [String: Any], let subreddit = subredditValue["subreddit"] as? String else {
            throw RedditRepositoryError.postNotFound
        }
        return subreddit
    }

    /// Fetch a post's comment tree. Reddit returns a 2-element array:
    /// [0] = the post listing (single item), [1] = comment listing.
    public func fetchComments(subreddit: String, postID: String, sort: String = "confidence") async throws -> Data {
        try await client.get(path: Self.commentsPath(subreddit: subreddit, postID: postID), parameters: ["sort": sort])
    }

    /// Re-fetches a post's comment tree rooted at one comment.
    ///
    /// This is how Reddit's "continue this thread" is actually
    /// resolved: its `more` object (`id: "_"`, no children) has no ids
    /// to hand to `/api/morechildren`, so the tree must be requested
    /// again with `comment=<id>`, which returns that comment and the
    /// next depth-limit's worth of its replies.
    ///
    /// Apollo shows these as "Continue thread\u{2026}". The
    /// response shape is identical to `fetchComments`, so the same
    /// builder consumes it.
    public func fetchCommentThread(subreddit: String, postID: String, commentID: String, sort: String = "confidence") async throws -> Data {
        try await client.get(
            path: Self.commentsPath(subreddit: subreddit, postID: postID),
            parameters: ["sort": sort, "comment": commentID, "context": "0"]
        )
    }

    /// Resolves a Reddit "more comments" continuation stub via
    /// `/api/morechildren`, returning the raw `things` array (each a
    /// `{kind: "t1", data: {...}}` object) ready to feed into
    /// `CommentTreeBuilder` the same way a normal comments response
    /// is.
    public func fetchMoreChildren(linkFullname: String, childIDs: [String], sort: String = "confidence") async throws -> [JSONValue] {
        // POST, not GET: the child-id list can exceed a GET query
        // string's length. The `.json` suffix matters: over the
        // cookie transport this endpoint otherwise returns legacy
        // HTML-embedded payload instead of JSON.
        let data = try await client.post(path: "/api/morechildren.json", parameters: [
            "link_id": linkFullname,
            "children": childIDs.joined(separator: ","),
            "sort": sort,
            "api_type": "json",
        ])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let json = root["json"] as? [String: Any],
              let jsonData = json["data"] as? [String: Any],
              let things = jsonData["things"] as? [Any] else {
            return []
        }
        let thingsData = try JSONSerialization.data(withJSONObject: things)
        return try JSONDecoder.reddit.decode([JSONValue].self, from: thingsData)
    }

    /// Fetch just the post itself, for call sites that only have a
    /// fullname/permalink and need the full post (e.g. Recently Read
    /// Posts, which stores only a lightweight snapshot locally).
    public func fetchPost(subreddit: String, postID: String) async throws -> RedditPost {
        let data = try await client.get(path: Self.commentsPath(subreddit: subreddit, postID: postID), parameters: [:])
        let listings = try JSONDecoder.reddit.decode([RedditListing].self, from: data)
        guard let child = listings.first?.data.children.first, child.kind == "t3" else {
            throw RedditRepositoryError.postNotFound
        }
        let plain = JSONValue.object(child.data.raw).plain
        let postData = try JSONSerialization.data(withJSONObject: plain)
        return try JSONDecoder.reddit.decode(RedditPost.self, from: postData)
    }

    /// A subreddit-wide feed of the most recent comments across all
    /// posts (distinct from a single post's comment tree), matching
    /// Reddit's own `/r/<sub>/comments` listing.
    public func fetchRecentComments(subreddit: String, after: String? = nil, limit: Int = 25) async throws -> [RedditComment] {
        let data = try await client.get(path: "/r/\(subreddit)/comments", parameters: after.map { ["after": $0, "limit": String(limit)] } ?? ["limit": String(limit)])
        let response = try JSONDecoder.reddit.decode(RedditListing.self, from: data)
        return response.data.children.compactMap { child -> RedditComment? in
            guard child.kind == "t1" else { return nil }
            let plain = JSONValue.object(child.data.raw).plain
            guard let payload = try? JSONSerialization.data(withJSONObject: plain) else { return nil }
            return try? JSONDecoder.reddit.decode(RedditComment.self, from: payload)
        }
    }

    /// direction: 1 = up, -1 = down, 0 = unvote.
    public func vote(fullname: String, direction: Int) async throws {
        try await client.post(path: "/api/vote", parameters: ["id": fullname, "dir": String(direction)])
    }

    public func save(fullname: String) async throws {
        try await client.post(path: "/api/save", parameters: ["id": fullname])
    }

    public func unsave(fullname: String) async throws {
        try await client.post(path: "/api/unsave", parameters: ["id": fullname])
    }

    /// The "hide" swipe action - removes a post from the user's
    /// default feed view.
    public func hide(fullname: String) async throws {
        try await client.post(path: "/api/hide", parameters: ["id": fullname])
    }

    /// Hides many posts at once: `/api/hide` takes a comma-separated
    /// list of fullnames, sent here in batches of 50 (Apollo's own
    /// batch size, every id included).
    public func hide(fullnames: [String]) async throws {
        for start in stride(from: 0, to: fullnames.count, by: 50) {
            let batch = fullnames[start..<min(start + 50, fullnames.count)]
            try await client.post(path: "/api/hide", parameters: ["id": batch.joined(separator: ",")])
        }
    }

    public func unhide(fullname: String) async throws {
        try await client.post(path: "/api/unhide", parameters: ["id": fullname])
    }

    /// Reports a post, comment, or user to the subreddit's moderators
    /// (or Reddit admins, for site-wide rule violations). `reason`
    /// matches one of the subreddit's configured report reasons (or a
    /// free-text "other" reason).
    public func report(fullname: String, reason: String) async throws {
        try await postChecked("/api/report", [
            "thing_id": fullname,
            "reason": reason,
        ])
    }

    /// Edits your own post selftext or comment body. Submit and edit
    /// share the same endpoint, distinguished by whether `thing_id`
    /// already exists.
    public func editUserText(fullname: String, text: String) async throws {
        try await postChecked("/api/editusertext", [
            "thing_id": fullname,
            "text": text,
        ])
    }

    /// Deletes your own post or comment.
    public func delete(fullname: String) async throws {
        try await client.post(path: "/api/del", parameters: ["id": fullname])
    }

    /// Blocks a user account-wide, hiding their posts/comments and
    /// preventing them from messaging you (distinct from
    /// subreddit-level muting, which is moderator-only and scoped to
    /// one subreddit).
    public func blockUser(fullname: String) async throws {
        try await client.post(path: "/api/block_user", parameters: ["account_id": fullname])
        _ = try? await fetchBlockedUsers()
    }

    /// The same, by username (`/api/block_user` takes `name` too), for a
    /// post menu, which has the author's name but not their `t2_` id.
    public func blockUser(username: String) async throws {
        try await client.post(path: "/api/block_user", parameters: ["name": username])
        BlockedUsersStore.add(username)
    }

    public func unblockUser(username: String, containerFullname: String) async throws {
        try await client.post(path: "/api/unfriend", parameters: [
            "name": username,
            "type": "enemy",
            "container": containerFullname,
        ])
        BlockedUsersStore.remove(username)
    }

    /// Unblocks from the block list, where the container is the signed-in
    /// account itself.
    public func unblockUser(username: String) async throws {
        let me = try await fetchIdentity()
        try await unblockUser(username: username, containerFullname: "t2_\(me.id)")
    }

    /// The account's Reddit block list, refreshing `BlockedUsersStore`.
    @discardableResult
    public func fetchBlockedUsers() async throws -> [RedditBlockedUser] {
        let users = try BlockedUsersStore.parse(try await client.get(path: "/prefs/blocked"))
        BlockedUsersStore.replace(with: users.map(\.name))
        return users
    }

    /// The "Follow" action, distinct from `blockUser`: Reddit's
    /// "friend" relationship, following a user to see them in a
    /// Friends feed. Uses the legacy `/api/friend` endpoint shared by
    /// every ban/mute/approve call in this file, differentiated by `type`.
    public func followUser(username: String) async throws {
        try await client.post(path: "/api/friend", parameters: ["name": username, "type": "friend"])
    }

    public func unfollowUser(username: String) async throws {
        try await client.post(path: "/api/unfriend", parameters: ["name": username, "type": "friend"])
    }

    /// Subscribes or unsubscribes from a subreddit.
    public func subscribe(subredditFullname: String, subscribe: Bool) async throws {
        try await client.post(path: "/api/subscribe", parameters: [
            "sr": subredditFullname,
            "action": subscribe ? "sub" : "unsub",
        ])
    }

    /// Same endpoint as `subscribe(subredditFullname:)` but keyed by
    /// display name (`sr_name`) instead of fullname (`sr`) - both are
    /// parameter names Reddit's API accepts. Used where only the
    /// plain subreddit name is on hand (no fullname fetch needed).
    public func subscribe(subredditName: String, subscribe: Bool) async throws {
        try await client.post(path: "/api/subscribe", parameters: [
            "sr_name": subredditName,
            "action": subscribe ? "sub" : "unsub",
        ])
    }

    /// Fetches a multireddit's combined feed. Path format matches
    /// Reddit's API: /user/<username>/m/<multiname>.
    public func fetchMultiredditListing(path: String, sort: String = "hot", after: String? = nil) async throws -> RedditListing {
        try await client.getListing(path: "\(path)/\(sort)", after: after)
    }
    /// Under a cookie-authed web session `/api/v1/me` is rewritten to
    /// `www.reddit.com` and answers `{}` (it is OAuth-only), while
    /// `/api/me.json` honors cookie auth and returns the full t2 blob
    /// including `pref_no_profanity`. Web-session accounts use that endpoint,
    /// decoding its `{kind: "t2", data: {...}}` wrapper instead of the bare
    /// object `/api/v1/me` returns.
    public func fetchIdentity() async throws -> RedditUser {
        let user: RedditUser
        if await client.isUsingWebSession {
            let data = try await client.get(path: "/api/me.json")
            user = try JSONDecoder.reddit.decode(RedditThing<RedditUser>.self, from: data).data
        } else {
            let data = try await client.get(path: "/api/v1/me")
            user = try JSONDecoder.reddit.decode(RedditUser.self, from: data)
        }
        return user
    }

    public func fetchSubredditInfo(name: String) async throws -> RedditSubreddit {
        let data = try await client.get(path: "/r/\(name)/about")
        let thing = try JSONDecoder.reddit.decode(RedditThing<RedditSubreddit>.self, from: data)
        return thing.data
    }

    /// Submits a new post that crossposts an existing one into a
    /// different subreddit. `flairID` lets the user pick a flair in
    /// the destination subreddit for the new crosspost, same as a
    /// normal submission.
    @discardableResult
    public func crosspost(originalFullname: String, toSubreddit: String, title: String, flairID: String? = nil) async throws -> Data {
        var parameters = [
            "sr": toSubreddit,
            "kind": "crosspost",
            "crosspost_fullname": originalFullname,
            "title": title,
            "api_type": "json",
        ]
        if let flairID {
            parameters["flair_id"] = flairID
        }
        return try await postChecked("/api/submit", parameters)
    }

    /// `/subreddits/mine/subscriber`, backing the Subreddits root screen: the
    /// signed-in user's full alphabetized subscription list. Reddit paginates
    /// this at 100 per page; this fetches all pages.
    public func fetchSubscribedSubreddits() async throws -> [RedditSubreddit] {
        try await fetchAllSubreddits(path: "/subreddits/mine/subscriber")
    }

    /// Every page of a subreddit listing. Bounded: Reddit caps these
    /// lists far below 10 pages of 100, and an empty `{}` response
    /// decodes as an empty listing, so a malformed cursor must not be
    /// able to spin here forever.
    private func fetchAllSubreddits(path: String) async throws -> [RedditSubreddit] {
        var all: [RedditSubreddit] = []
        var after: String?
        var pages = 0
        repeat {
            let listing = try await client.getListing(path: path, after: after, limit: 100)
            pages += 1
            all += listing.decodedChildren(RedditSubreddit.self)
            after = listing.data.after
        } while after != nil && pages < 10
        return all
    }

    /// The Subreddits root screen's MODERATOR section: subreddits the
    /// signed-in user moderates. A separate listing from
    /// `fetchSubscribedSubreddits()`, since `/subreddits/mine/subscriber`
    /// doesn't reliably carry `user_is_moderator`.
    public func fetchModeratedSubreddits() async throws -> [RedditSubreddit] {
        try await fetchAllSubreddits(path: "/subreddits/mine/moderator")
    }
    /// Raw authenticated GET for `HiddenContentFinder`, which reads the
    /// live listing and `/api/info` as plain JSON (it needs fields such
    /// as `removed_by_category` and `link_id` that the typed models do
    /// not keep).
    public func rawGET(path: String, parameters: [String: String]) async throws -> Data {
        try await client.get(path: path, parameters: parameters)
    }
    /// The signed-in user's saved posts/comments (only accessible for
    /// your own account).
    public func fetchSavedItems(username: String, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        try await client.getListing(path: "/user/\(username)/saved", after: after, limit: limit)
    }
    /// Many users' names and pictures in one request, keyed by `t2_` id
    /// (`/api/user_data_by_account_ids`, what Apollo itself asks for every
    /// comment author). Up to 100 ids.
    public func fetchUserData(accountIDs: [String]) async throws -> [String: (name: String, profileImage: String?)] {
        let data = try await client.get(path: "/api/user_data_by_account_ids",
                                        parameters: ["ids": accountIDs.prefix(100).joined(separator: ",")])
        return Self.parseUserData(data)
    }

    public static func parseUserData(_ data: Data) -> [String: (name: String, profileImage: String?)] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: (name: String, profileImage: String?)] = [:]
        for (id, value) in root {
            guard let record = value as? [String: Any], let name = record["name"] as? String else { continue }
            let image = (record["profile_img"] as? String).map { $0.replacingOccurrences(of: "&amp;", with: "&") }
            result[id] = (name, image?.isEmpty == false ? image : nil)
        }
        return result
    }
    public func fetchUserProfile(username: String) async throws -> RedditUser {
        let data = try await client.get(path: "/user/\(username)/about")
        let thing = try JSONDecoder.reddit.decode(RedditThing<RedditUser>.self, from: data)
        return thing.data
    }

    /// A write that reports refusals in-band. With `api_type=json` Reddit
    /// answers a rejected submit, edit, message or report with HTTP 200 and
    /// `json.errors` (rate limit, flair required, no such user); the check
    /// keeps a rejected post from closing the composer as if it had posted.
    @discardableResult
    func postChecked(_ path: String, _ parameters: [String: String]) async throws -> Data {
        var parameters = parameters
        parameters["api_type"] = "json"
        let data = try await client.post(path: path, parameters: parameters)
        try PostedCommentResponse.throwIfRejected(data)
        return data
    }
}
