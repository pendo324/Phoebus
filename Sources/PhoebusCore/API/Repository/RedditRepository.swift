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
        await Self.announce(SubscriptionChange(fullname: subredditFullname, subscribed: subscribe))
    }

    /// Every surface showing subscription state hears about it, and the
    /// All/Popular membership cache stops being stale.
    public static func announce(_ change: SubscriptionChange) async {
        await SubscribedSubredditsCache.shared.invalidate()
        await MainActor.run { SubscriptionChange.post(change) }
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
        await Self.announce(SubscriptionChange(name: subredditName, subscribed: subscribe))
    }

    @discardableResult
    public func submitComment(parentFullname: String, text: String) async throws -> Data {
        let data = try await client.post(path: "/api/comment", parameters: [
            "parent": parentFullname,
            "text": text,
            "api_type": "json",
        ])
        try PostedCommentResponse.throwIfRejected(data)
        return data
    }

    /// Reborn "Prefer Native Images": whether `subreddit` allows
    /// uploaded images in comments, from `/about`'s
    /// `allowed_media_in_comments`. nil when unknown.
    public func subredditAllowsImageComments(_ subreddit: String) async -> Bool? {
        guard let data = try? await client.get(path: "/r/\(subreddit)/about"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let about = root["data"] as? [String: Any] else { return nil }
        return NativeCommentImages.allowsImageComments(aboutData: about)
    }

    /// Uploads an image through Reddit's own media pipeline for use in
    /// a comment and returns its asset id and `i.redd.it` URL.
    public func uploadCommentImage(fileData: Data, filename: String, mimeType: String) async throws -> (assetID: String, url: String) {
        let lease = try await RedditMediaUploadClient.requestUploadLease(kind: .image, filename: filename, mimeType: mimeType, client: client)
        try await RedditMediaUploadClient.upload(fileData: fileData, filename: filename, mimeType: mimeType, lease: lease)
        guard let assetID = lease.assetID, !assetID.isEmpty else { throw RedditMediaUploadClient.ClientError.invalidLeaseResponse }
        let ext = (filename as NSString).pathExtension.lowercased()
        return (assetID, NativeCommentImages.mediaURL(assetID: assetID, fileExtension: ext == "jpg" ? "jpeg" : ext))
    }

    /// Submits a comment whose natively uploaded images ride in a
    /// `richtext_json` document, keeping a markdown body for clients
    /// that ignore RTJSON.
    @discardableResult
    public func submitComment(parentFullname: String, text: String, nativeImageAssetIDs: Set<String>) async throws -> Data {
        guard let rich = NativeCommentImages.richTextJSON(for: text, assetIDs: nativeImageAssetIDs) else {
            return try await submitComment(parentFullname: parentFullname, text: text)
        }
        let data = try await client.post(path: "/api/comment", parameters: [
            "parent": parentFullname,
            "text": NativeCommentImages.markdownBody(for: text, assetIDs: nativeImageAssetIDs),
            "richtext_json": rich,
            "return_rtjson": "true",
            "api_type": "json",
        ])
        try PostedCommentResponse.throwIfRejected(data)
        return data
    }

    /// Fetches the signed-in user's saved multireddits (custom
    /// subreddit groupings).
    public func fetchMultireddits() async throws -> [RedditMultireddit] {
        let data = try await client.get(path: "/api/multi/mine")
        // Per item, so one multireddit with an unexpected field does not
        // drop the whole section.
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw RedditAPIError.decodingFailed("multi/mine: not an array")
        }
        return items.compactMap { item in
            guard let inner = item["data"],
                  let json = try? JSONSerialization.data(withJSONObject: inner) else { return nil }
            return try? JSONDecoder.reddit.decode(RedditMultireddit.self, from: json)
        }
    }

    /// Fetches a multireddit's combined feed. Path format matches
    /// Reddit's API: /user/<username>/m/<multiname>.
    public func fetchMultiredditListing(path: String, sort: String = "hot", after: String? = nil) async throws -> RedditListing {
        try await client.getListing(path: "\(path)/\(sort)", after: after)
    }

    /// Creates a new multireddit.
    @discardableResult
    public func createMultireddit(name: String, username: String) async throws -> Data {
        let path = "/user/\(username)/m/\(name.replacingOccurrences(of: " ", with: "_"))"
        let model = try Self.multiModel(["display_name": name, "subreddits": [[String: String]]()])
        return try await client.put(path: "/api/multi\(path)", parameters: ["model": model])
    }

    /// A multireddit "model" parameter. Serialised, not concatenated:
    /// the hand-built JSON escaped quotes and newlines but not
    /// backslashes or control characters.
    public static func multiModel(_ fields: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), as: UTF8.self)
    }

    /// Reborn "in-app renaming and descriptions" for multireddits via
    /// `PUT /api/multi/<path>` (a full "model" JSON replaces the
    /// display_name/description_md fields; existing subreddits are
    /// preserved by round-tripping the current subreddit list).
    @discardableResult
    public func updateMultireddit(path: String, displayName: String, descriptionMarkdown: String, subredditNames: [String]) async throws -> Data {
        let model = try Self.multiModel([
            "display_name": displayName,
            "description_md": descriptionMarkdown,
            "subreddits": subredditNames.map { ["name": $0] },
        ])
        return try await client.put(path: "/api/multi\(path)", parameters: ["model": model])
    }

    /// Adds a single subreddit to a multireddit directly via Reddit's
    /// dedicated per-subreddit endpoint (`PUT
    /// /api/multi/<multipath>/r/<srname>`), rather than rewriting the
    /// whole subreddit list via `updateMultireddit`.
    @discardableResult
    public func addSubredditToMultireddit(multiPath: String, subreddit: String) async throws -> Data {
        try await client.put(path: "/api/multi\(multiPath)/r/\(subreddit)", parameters: [
            "model": try Self.multiModel(["name": subreddit]),
        ])
    }

    /// Endpoint counterpart to `addSubredditToMultireddit` above
    /// (`DELETE /api/multi/<multipath>/r/<srname>`).
    public func removeSubredditFromMultireddit(multiPath: String, subreddit: String) async throws {
        try await client.delete(path: "/api/multi\(multiPath)/r/\(subreddit)")
    }

    /// Fetches another user's *public* multireddits (their own
    /// private ones are only visible via `/api/multi/mine`).
    public func fetchPublicMultireddits(username: String) async throws -> [RedditMultireddit] {
        let data = try await client.get(path: "/api/multi/user/\(username)")
        let things = try JSONDecoder.reddit.decode([RedditThing<RedditMultireddit>].self, from: data)
        return things.map(\.data)
    }

    /// The signed-in user's Reddit friends list. `/prefs/friends` is
    /// the correct endpoint (`/api/v1/me/friends` returns HTML), but
    /// returns per-category `UserList` listings; this flattens them.
    public func fetchFriends() async throws -> [ModeratorListedUser] {
        let data = try await client.get(path: "/prefs/friends")
        let lists = try JSONDecoder().decode([ModeratorUserListResponse].self, from: data)
        return lists.flatMap(\.data.children)
    }

    /// Casts a vote on a native Reddit poll. Requires the web/cookie
    /// session transport since poll voting's GraphQL mutation isn't
    /// reachable over OAuth. Not `client.webSessionCredential`: poll
    /// voting must work for OAuth accounts too.
    func webFeatureSession() async -> WebSessionCredential? {
        if let username = FavoriteSubredditsAccountContext.currentUsernameProvider(),
           let session = WebSessionRegistry.featureSession(for: username) {
            return session
        }
        // Falls back to the transport session so a keyless (cookie
        // transport) account still votes even before its entry has
        // been migrated into the registry.
        return await client.webSessionCredential
    }

    public func votePoll(postFullname: String, optionID: String) async throws {
        guard let session = await webFeatureSession() else {
            throw PollVoteService.VoteError.requiresWebSession
        }
        do {
            try await PollVoteService.vote(postFullname: postFullname, optionID: optionID, session: session)
        } catch let error as PollVoteService.VoteError {
            // Reborn's poll voting: HTTP 401 means Reddit has declared the cookie
            // dead, so the session is removed and the user re-harvests; otherwise
            // every retry would hit the same 401.
            //
            // 403 is deliberately NOT destructive: it means this particular vote was
            // refused (poll closed, quarantined sub, subreddit ban), which says
            // nothing about session validity.
            if case .sessionExpired = error {
                WebSessionRegistry.remove(username: session.username)
                await client.clearWebSessionIfMatching(username: session.username)
            }
            throw error
        }
    }

    /// Creates a new native poll post. Requires the web/cookie-session
    /// transport, same constraint as voting.
    @discardableResult
    public func submitPoll(subreddit: String, title: String, options: [String], durationDays: Int, flairID: String? = nil, flairText: String? = nil) async throws -> URL {
        guard let session = await webFeatureSession() else {
            throw PollComposeService.ComposeError.requiresWebSession
        }
        return try await PollComposeService.submit(subreddit: subreddit, title: title, options: options, durationDays: durationDays, flairID: flairID, flairText: flairText, session: session)
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
        if let blurs = user.blursMatureMedia {
            MatureMediaPreference.record(username: user.name, blursMatureMedia: blurs)
        }
        return user
    }

    public func fetchSubredditInfo(name: String) async throws -> RedditSubreddit {
        let data = try await client.get(path: "/r/\(name)/about")
        let thing = try JSONDecoder.reddit.decode(RedditThing<RedditSubreddit>.self, from: data)
        return thing.data
    }

    public func fetchSubredditRules(name: String) async throws -> [SubredditRule] {
        let data = try await client.get(path: "/r/\(name)/about/rules")
        let response = try JSONDecoder().decode(SubredditRulesResponse.self, from: data)
        return response.rules
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

    public func searchSubreddits(query: String, limit: Int = 25) async throws -> Data {
        try await client.get(path: "/subreddits/search", parameters: [
            "q": query,
            "limit": String(limit),
        ])
    }

    /// Name-prefix autocomplete for the Jump Bar, using
    /// `api/subreddit_autocomplete_v2` rather than `subreddits/search`
    /// (which ranks by relevance across descriptions, so typing
    /// "athe" would return subreddits whose names don't start with
    /// "athe" at all - useless for a jump-to-subreddit control, whose
    /// every row should start with the typed prefix).
    public func autocompleteSubreddits(query: String, limit: Int = 8, includeOver18: Bool = true) async throws -> Data {
        try await client.get(path: "/api/subreddit_autocomplete_v2", parameters: [
            "query": query,
            "limit": String(limit),
            "include_profiles": "false",
            "include_over_18": includeOver18 ? "true" : "false",
        ])
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

    /// Full-text post search, either site-wide (empty `subreddit`) or
    /// scoped to one subreddit (`restrict_sr=1`), matching Reddit's
    /// own search UI options.
    public func searchPosts(query: String, subreddit: String? = nil, sort: String = "relevance", limit: Int = 25) async throws -> RedditListing {
        let path = if let subreddit, !subreddit.isEmpty { "/r/\(subreddit)/search" } else { "/search" }
        var parameters = ["q": query, "sort": sort, "limit": String(limit)]
        if let subreddit, !subreddit.isEmpty {
            parameters["restrict_sr"] = "1"
        }
        return try await client.getListing(path: path, parameters: parameters)
    }

    /// Raw authenticated GET for `HiddenContentFinder`, which reads the
    /// live listing and `/api/info` as plain JSON (it needs fields such
    /// as `removed_by_category` and `link_id` that the typed models do
    /// not keep).
    public func rawGET(path: String, parameters: [String: String]) async throws -> Data {
        try await client.get(path: path, parameters: parameters)
    }

    /// A user's post/comment history.
    public func fetchUserOverview(username: String, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        try await client.getListing(path: "/user/\(username)/overview", after: after, limit: limit)
    }

    public func fetchUserComments(username: String, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        try await client.getListing(path: "/user/\(username)/comments", after: after, limit: limit)
    }

    /// Post-only counterpart to `fetchUserComments`.
    public func fetchUserSubmitted(username: String, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        try await client.getListing(path: "/user/\(username)/submitted", after: after, limit: limit)
    }

    /// The signed-in user's saved posts/comments (only accessible for
    /// your own account).
    public func fetchSavedItems(username: String, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        try await client.getListing(path: "/user/\(username)/saved", after: after, limit: limit)
    }

    /// The signed-in user's hidden posts (`/user/<me>/hidden`), for Reborn's
    /// own-profile browser.
    public func fetchUserHidden(username: String, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        try await client.getListing(path: "/user/\(username)/hidden", after: after, limit: limit)
    }

    /// Profile row-list "Upvoted" segment (`/user/<name>/upvoted`) -
    /// only visible for the signed-in user, or another user who has
    /// made their votes public (`RedditUser.hasVotesPublic`).
    public func fetchUserUpvoted(username: String, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        try await client.getListing(path: "/user/\(username)/upvoted", after: after, limit: limit)
    }

    /// Profile row-list "Downvoted" segment (`/user/<name>/downvoted`).
    public func fetchUserDownvoted(username: String, after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        try await client.getListing(path: "/user/\(username)/downvoted", after: after, limit: limit)
    }

    /// Two distinct endpoints: `api/v1/me/trophies` for the signed-in
    /// user's own trophies, `api/v1/user/<name>/trophies` for anyone
    /// else. `/api/v1/me/*` doesn't work under the cookie/web-session
    /// transport (same constraint `fetchIdentity()` above documents
    /// and works around). Since `/api/v1/user/<name>/trophies` works
    /// for any username including your own, the OAuth-only `/me/`
    /// form is used only when actually running OAuth transport.
    public func fetchTrophies(username: String, isOwnProfile: Bool = false) async throws -> [RedditTrophy] {
        let usingWebSession = await client.isUsingWebSession
        let useOwnProfileEndpoint = isOwnProfile && !usingWebSession
        let path = useOwnProfileEndpoint ? "/api/v1/me/trophies" : "/api/v1/user/\(username)/trophies"
        let data: Data
        do {
            data = try await client.get(path: path)
        } catch {
            // The web session is refused the v1 endpoint (403); Reddit's
            // older `/user/<name>/trophies` answers the same shape.
            guard usingWebSession else { throw error }
            data = try await client.get(path: "/user/\(username)/trophies")
        }
        let response = try JSONDecoder().decode(TrophyListResponse.self, from: data)
        return response.data.trophies.map(\.data)
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
    /// The bodies of the given comments (`t1_` fullnames), for the inbox's
    /// “replied to your comment” quote. Missing ones are left out.
    public func fetchCommentBodies(fullnames: [String]) async -> [String: String] {
        var result: [String: String] = [:]
        let ids = Array(Set(fullnames.filter { $0.hasPrefix("t1_") }))
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = ids[start..<min(start + 100, ids.count)]
            guard let data = try? await client.get(path: "/api/info", parameters: ["id": batch.joined(separator: ",")]),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let listing = root["data"] as? [String: Any],
                  let children = listing["children"] as? [[String: Any]] else { continue }
            for child in children {
                guard let item = child["data"] as? [String: Any], let name = item["name"] as? String,
                      let body = item["body"] as? String else { continue }
                result[name] = body
            }
        }
        return result
    }

    public func fetchUserProfile(username: String) async throws -> RedditUser {
        let data = try await client.get(path: "/user/\(username)/about")
        let thing = try JSONDecoder.reddit.decode(RedditThing<RedditUser>.self, from: data)
        return thing.data
    }

    /// Unread + all messages. `category` supports Apollo's "Boxes"
    /// menu (inbox, unreadMessages, commentReplies, postReplies,
    /// usernameMentions, messages, moderatorMail), each mapping to its
    /// own `/message/<where>` endpoint - see `InboxCategory.apiPath`.
    public func fetchInbox(category: InboxCategory = .inbox, after: String? = nil) async throws -> [RedditMessage] {
        let data = try await client.getListing(path: "/message/\(category.apiPath)", after: after)
        return data.data.children.compactMap { child -> RedditMessage? in
            let plain = JSONValue.object(child.data.raw).plain
            guard let payload = try? JSONSerialization.data(withJSONObject: plain) else { return nil }
            return try? JSONDecoder.reddit.decode(RedditMessage.self, from: payload)
        }
    }

    /// Whether the inbox comes over the cookie transport, which, unlike
    /// OAuth, carries no copies of Reddit Chat messages.
    public var inboxLacksChatMirrors: Bool {
        get async { await client.isUsingWebSession }
    }

    /// Unread inbox items for the tab badge: `/message/unread` with Reddit's
    /// maximum page, so the count is exact up to 100.
    public func fetchUnreadInboxCount() async throws -> Int {
        // Reddit's own counter first; the unread listing as a fallback.
        // A web session's `/api/v1/me` is `{}`, so it asks `/api/me.json`,
        // which carries the same count.
        let mePath = await client.isUsingWebSession ? "/api/me.json" : "/api/v1/me"
        if let data = try? await client.get(path: mePath),
           let count = InboxUnreadCount.fromIdentity(data) {
            return count
        }
        let listing = try await client.getListing(path: "/message/unread", limit: 100)
        return listing.data.children.count
    }

    public func markMessageRead(fullname: String) async throws {
        try await client.post(path: "/api/read_message", parameters: ["id": fullname])
    }

    /// Reddit's read_message endpoint doubles as unread via
    /// `/api/unread_message` with the same `id` parameter shape, used by the
    /// Inbox "Mark Read" swipe toggling a message back to unread.
    public func markMessageUnread(fullname: String) async throws {
        try await client.post(path: "/api/unread_message", parameters: ["id": fullname])
    }

    /// The inbox "mark all read" toolbar action.
    public func markAllMessagesRead() async throws {
        try await client.post(path: "/api/read_all_messages", parameters: [:])
    }

    /// Sends a brand-new private message to a user (as opposed to
    /// replying to an existing thread, which uses the same
    /// `submitComment`/`/api/comment` endpoint as any other reply
    /// since Reddit treats PM replies as comments on the message
    /// "post").
    public func sendPrivateMessage(to username: String, subject: String, body: String) async throws {
        try await postChecked("/api/compose", [
            "to": username,
            "subject": subject,
            "text": body,
        ])
    }

    /// Fetches the list of available link flairs for a subreddit
    /// before posting.
    public func fetchFlairOptions(subreddit: String) async throws -> [RedditFlairOption] {
        let data = try await client.post(path: "/r/\(subreddit)/api/flairselector", parameters: ["is_newlink": "true"])
        let response = try JSONDecoder.reddit.decode(FlairSelectorResponse.self, from: data)
        return response.choices
    }

    /// Flair options for an existing post (`is_newlink=false`) -
    /// changing or removing a post's flair after submission, rather
    /// than only at compose time.
    public func fetchFlairOptions(forLink fullname: String, subreddit: String) async throws -> [RedditFlairOption] {
        let data = try await client.post(path: "/r/\(subreddit)/api/flairselector", parameters: ["link": fullname])
        let response = try JSONDecoder.reddit.decode(FlairSelectorResponse.self, from: data)
        return response.choices
    }

    /// Flair options for a user in a subreddit - backs the "Set User
    /// Flair" row.
    public func fetchUserFlairOptions(subreddit: String, username: String) async throws -> [RedditFlairOption] {
        let data = try await client.post(path: "/r/\(subreddit)/api/flairselector", parameters: ["name": username])
        let response = try JSONDecoder.reddit.decode(FlairSelectorResponse.self, from: data)
        return response.choices
    }

    /// Sprite regions for a subreddit's old-reddit CSS-class flairs, from
    /// its stylesheet (Reborn #1215). Empty when the stylesheet uses a
    /// layout Reborn doesn't parse either.
    public func fetchFlairSprites(subreddit: String) async throws -> [String: FlairSprites.Region] {
        let data = try await client.get(path: "/r/\(subreddit)/about/stylesheet", parameters: ["raw_json": "1"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["data"] as? [String: Any],
              let css = body["stylesheet"] as? String else { return [:] }
        let images = FlairSprites.imageMap(body["images"] as? [[String: Any]] ?? [])
        return FlairSprites.parse(css: css, images: images)
    }

    /// Applies (or, with a nil template, clears) flair on a post or a
    /// user via `/api/selectflair`.
    @discardableResult
    public func selectFlair(subreddit: String, templateID: String?, linkFullname: String? = nil, username: String? = nil, text: String? = nil) async throws -> Data {
        var params: [String: String] = ["api_type": "json"]
        if let templateID { params["flair_template_id"] = templateID }
        if let linkFullname { params["link"] = linkFullname }
        if let username { params["name"] = username }
        if let text { params["text"] = text }
        return try await postChecked("/r/\(subreddit)/api/selectflair", params)
    }

    @discardableResult
    public func submitPost(subreddit: String, title: String, selftext: String?, url: String?, flairID: String?) async throws -> Data {
        var params: [String: String] = [
            "sr": subreddit,
            "title": title,
            "kind": url != nil ? "link" : "self",
            "api_type": "json",
        ]
        if let selftext { params["text"] = selftext }
        if let url { params["url"] = url }
        if let flairID { params["flair_id"] = flairID }
        return try await postChecked("/api/submit", params)
    }

    /// Uploads image/video data through Reddit's own media pipeline and
    /// submits it as an image post (Reborn's "Native Reddit media upload
    /// support"): a lease-then-upload flow rather than a third-party host.
    @discardableResult
    public func submitImagePost(subreddit: String, title: String, fileData: Data, filename: String, mimeType: String, kind: RedditMediaKind, flairID: String?) async throws -> Data {
        let lease = try await RedditMediaUploadClient.requestUploadLease(kind: kind, filename: filename, mimeType: mimeType, client: client)
        try await RedditMediaUploadClient.upload(fileData: fileData, filename: filename, mimeType: mimeType, lease: lease)
        var params: [String: String] = [
            "sr": subreddit,
            "title": title,
            "kind": "image",
            "url": lease.assetURL,
            "api_type": "json",
        ]
        if let flairID { params["flair_id"] = flairID }
        return try await postChecked("/api/submit", params)
    }

    /// Uploads a native Reddit video, plus a required poster/thumbnail
    /// image, and submits a `kind=video` post. A video submit needs
    /// `kind=video`, `url=<video asset URL>`, AND
    /// `video_poster_url=<poster asset URL>` all three set, unlike an
    /// image post which needs no separate poster.
    @discardableResult
    public func submitVideoPost(subreddit: String, title: String, videoData: Data, videoFilename: String, videoMimeType: String, posterData: Data, flairID: String?) async throws -> Data {
        let videoLease = try await RedditMediaUploadClient.requestUploadLease(kind: .video, filename: videoFilename, mimeType: videoMimeType, client: client)
        try await RedditMediaUploadClient.upload(fileData: videoData, filename: videoFilename, mimeType: videoMimeType, lease: videoLease)
        let posterLease = try await RedditMediaUploadClient.requestUploadLease(kind: .image, filename: "poster.jpg", mimeType: "image/jpeg", client: client)
        try await RedditMediaUploadClient.upload(fileData: posterData, filename: "poster.jpg", mimeType: "image/jpeg", lease: posterLease)
        var params: [String: String] = [
            "sr": subreddit,
            "title": title,
            "kind": "video",
            "url": videoLease.assetURL,
            "video_poster_url": posterLease.assetURL,
            "api_type": "json",
            "validate_on_submit": "false",
        ]
        if let flairID { params["flair_id"] = flairID }
        return try await postChecked("/api/submit", params)
    }

    /// Uploads 2-20 images and submits them as a Reddit gallery post: a JSON
    /// (not form-encoded) POST to `/api/submit_gallery_post.json` with an
    /// `items` array of `{"media_id": <asset_id>, "caption": "",
    /// "outbound_url": ""}`, where `media_id` is the lease response's
    /// `asset_id` (NOT the S3 key or asset URL).
    @discardableResult
    public func submitGalleryPost(subreddit: String, title: String, images: [(data: Data, filename: String, mimeType: String)], flairID: String?) async throws -> Data {
        var mediaIDs: [String] = []
        for image in images {
            let lease = try await RedditMediaUploadClient.requestUploadLease(kind: .image, filename: image.filename, mimeType: image.mimeType, client: client)
            try await RedditMediaUploadClient.upload(fileData: image.data, filename: image.filename, mimeType: image.mimeType, lease: lease)
            // A missing id must not silently drop the image (a gallery with fewer
            // images than picked).
            guard let mediaID = lease.assetID else { throw RedditMediaUploadClient.ClientError.invalidLeaseResponse }
            mediaIDs.append(mediaID)
        }
        let items: [[String: String]] = mediaIDs.map { ["media_id": $0, "caption": "", "outbound_url": ""] }
        var payload: [String: Any] = [
            "api_type": "json",
            "items": items,
            "nsfw": false,
            "resubmit": true,
            "sendreplies": true,
            "show_error_list": true,
            "spoiler": false,
            "sr": subreddit,
            "title": title,
            "validate_on_submit": false,
        ]
        if let flairID { payload["flair_id"] = flairID }
        let data = try await client.postJSON(path: "/api/submit_gallery_post.json", body: payload)
        try PostedCommentResponse.throwIfRejected(data)
        return data
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

public struct RedditFlairOption: Decodable, Sendable, Identifiable, Hashable {
    public let flairTemplateID: String
    public let text: String
    /// Old-reddit CSS class (sprite flairs such as r/nintendo's).
    public let cssClass: String?

    public var id: String { flairTemplateID }

    /// The row title: the flair text, or for an old-reddit sprite flair
    /// with no text, its prettified CSS class (Reborn #1215's fallback).
    public var displayText: String {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        return cssClass.flatMap(Self.prettifiedClass) ?? text
    }

    /// The CSS class whose sprite this row draws: only for a template with
    /// no text of its own. Reborn leaves labelled templates (r/steinsgate
    /// gives each both a class and a name) to their real text.
    public var spriteClass: String? {
        guard text.trimmingCharacters(in: .whitespaces).isEmpty,
              let cssClass = cssClass?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cssClass.isEmpty else { return nil }
        return cssClass
    }

    public init(flairTemplateID: String, text: String, cssClass: String? = nil) {
        self.flairTemplateID = flairTemplateID
        self.text = text
        self.cssClass = cssClass
    }

    enum CodingKeys: String, CodingKey {
        case flairTemplateID = "flair_template_id"
        case text = "flair_text"
        case cssClass = "flair_css_class"
    }

    /// "princessPeach" → "Princess Peach", "Beerus-001" → "Beerus".
    public static func prettifiedClass(_ cssClass: String) -> String? {
        var s = cssClass.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        func sub(_ pattern: String, _ template: String) {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        sub("[-_]?[0-9]{1,4}$", "")
        sub("[-_]+", " ")
        sub("([a-z])([A-Z])", "$1 $2")
        sub("([A-Za-z])([0-9])", "$1 $2")
        sub("([0-9])([A-Za-z])", "$1 $2")
        sub("\\s+", " ")
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s.capitalized
    }
}

struct FlairSelectorResponse: Decodable {
    let choices: [RedditFlairOption]
}

/// Reddit's /api/mod/conversations response shape: a dict of
/// conversations keyed by ID, plus an ordered ID list for display order.
struct ModmailConversationsResponse: Decodable {
    let conversations: [String: ModmailConversation]
    let conversationIds: [String]
}

struct SubredditRulesResponse: Decodable {
    let rules: [SubredditRule]
}

/// Reddit's wiki page response shape: `{"kind": "wikipage", "data": {"content_md": ...}}`.
struct WikiPageResponse: Decodable {
    let data: WikiPageData
    struct WikiPageData: Decodable {
        let contentMd: String
        enum CodingKeys: String, CodingKey {
            case contentMd = "content_md"
        }
    }
}

/// The unread counts behind the Inbox tab badge.
public enum InboxUnreadCount {
    /// `inbox_count` from `/api/v1/me` (or `data.inbox_count` from the
    /// web session's `/api/me.json`).
    public static func fromIdentity(_ data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let body = (root["data"] as? [String: Any]) ?? root
        return (body["inbox_count"] as? NSNumber)?.intValue
    }

    /// Reborn's Chat share of the badge: unread messages, or the pending
    /// chat requests when no message is unread. The two are never summed,
    /// since Reddit's own counter may already fold requests in.
    public static func chat(unread: Int, requests: Int) -> Int {
        unread > 0 ? unread : max(0, requests)
    }

    /// Reborn's combined badge. Over OAuth the inbox already carries a copy
    /// of every chat message, so the larger of the two is shown rather than
    /// counting chats twice; a web session's inbox has no copies, so the
    /// two add up.
    public static func combined(inbox: Int, chat: Int, inboxListsChat: Bool = false) -> Int {
        let inbox = max(0, inbox), chat = max(0, chat)
        return inboxListsChat ? max(inbox, chat) : inbox + chat
    }
}
