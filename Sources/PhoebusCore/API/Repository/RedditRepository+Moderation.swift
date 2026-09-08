import Foundation

/// Moderator tools, mod lists and modmail.
extension RedditRepository {
    /// The public list of a subreddit's moderators (visible to
    /// anyone). `mod_permissions` isn't modeled since we only display
    /// the list, not per-mod permission editing.
    public func fetchPublicModerators(subreddit: String) async throws -> [ModeratorListedUser] {
        let data = try await client.get(path: "/r/\(subreddit)/about/moderators")
        let response = try JSONDecoder().decode(ModeratorUserListResponse.self, from: data)
        return response.data.children
    }

    /// Invites a user to moderate a subreddit, via the shared
    /// `/api/friend` endpoint with `type=moderator_invite`.
    public func inviteModerator(username: String, subreddit: String, permissions: String = "+all") async throws {
        try await client.post(path: "/r/\(subreddit)/api/friend", parameters: [
            "name": username,
            "type": "moderator_invite",
            "permissions": permissions,
        ])
    }

    /// Rescinds a pending moderator invite (from the inviting mod's
    /// side) via `/api/unfriend` with `type=moderator_invite`.
    public func revokeModeratorInvite(username: String, subreddit: String) async throws {
        try await client.post(path: "/r/\(subreddit)/api/unfriend", parameters: [
            "name": username,
            "type": "moderator_invite",
        ])
    }

    /// Removes an existing (already-accepted) moderator via
    /// `/api/unfriend` with `type=moderator`.
    public func removeModerator(username: String, subreddit: String) async throws {
        try await client.post(path: "/r/\(subreddit)/api/unfriend", parameters: [
            "name": username,
            "type": "moderator",
        ])
    }

    /// Accepts a pending moderator invite for the signed-in user via
    /// `/api/accept_moderator_invite`.
    public func acceptModeratorInvite(subreddit: String) async throws {
        try await client.post(path: "/r/\(subreddit)/api/accept_moderator_invite", parameters: ["api_type": "json"])
    }

    /// Declines a pending moderator invite for the signed-in user;
    /// this is simply the invited user rescinding their own invite via
    /// the same `/api/unfriend` call an inviting mod would use, scoped
    /// to their own username.
    public func declineModeratorInvite(username: String, subreddit: String) async throws {
        try await revokeModeratorInvite(username: username, subreddit: subreddit)
    }

    // MARK: - Moderator tools

    /// Fetches a subreddit's mod queue (reported/spam-flagged content
    /// awaiting review).
    public func fetchModQueue(subreddit: String, after: String? = nil) async throws -> RedditListing {
        try await client.getListing(path: "/r/\(subreddit)/about/modqueue", after: after)
    }

    /// Lets a moderator switch between the Reports/Spam/Unmoderated
    /// queues, each its own distinct endpoint, rather than only the
    /// combined `/about/modqueue` view.
    public enum ModQueueFilter: String, CaseIterable, Sendable {
        case all = "modqueue"
        case reports
        case spam
        case unmoderated

        public var label: String {
            switch self {
            case .all: return "All"
            case .reports: return "Reports"
            case .spam: return "Spam"
            case .unmoderated: return "Unmoderated"
            }
        }
    }

    public func fetchModQueue(subreddit: String, filter: ModQueueFilter, after: String? = nil) async throws -> RedditListing {
        try await client.getListing(path: "/r/\(subreddit)/about/\(filter.rawValue)", after: after)
    }

    @discardableResult
    public func approve(fullname: String) async throws -> Data {
        try await client.post(path: "/api/approve", parameters: ["id": fullname])
    }

    @discardableResult
    public func remove(fullname: String, isSpam: Bool = false) async throws -> Data {
        try await client.post(path: "/api/remove", parameters: [
            "id": fullname,
            "spam": isSpam ? "true" : "false",
        ])
    }

    /// The mod queue row's "Ignore Reports" action, backed by
    /// `/api/ignore_reports` and `/api/unignore_reports`.
    @discardableResult
    public func ignoreReports(fullname: String, ignore: Bool = true) async throws -> Data {
        try await client.post(path: ignore ? "/api/ignore_reports" : "/api/unignore_reports", parameters: ["id": fullname])
    }

    /// Distinguish/Undistinguish, Sticky/Unsticky, and Lock/Unlock
    /// moderator actions, backed by `api/distinguish`,
    /// `api/set_subreddit_sticky`, and `api/lock`/`api/unlock`.
    @discardableResult
    public func distinguish(fullname: String, asMod: Bool) async throws -> Data {
        // The API's how="yes"/"no" convention (also supports
        // "admin"/"special", not exposed here since this app has no
        // admin-tier moderation surface).
        try await client.post(path: "/api/distinguish", parameters: ["id": fullname, "how": asMod ? "yes" : "no"])
    }

    @discardableResult
    public func setSticky(fullname: String, sticky: Bool, slot: Int? = nil) async throws -> Data {
        var parameters = ["id": fullname, "state": sticky ? "true" : "false"]
        if sticky, let slot { parameters["num"] = String(slot) }
        return try await client.post(path: "/api/set_subreddit_sticky", parameters: parameters)
    }

    @discardableResult
    public func setLocked(fullname: String, locked: Bool) async throws -> Data {
        try await client.post(path: locked ? "/api/lock" : "/api/unlock", parameters: ["id": fullname])
    }

    // MARK: - Removal reasons
    // A subreddit-configured list of canned removal-reason templates a
    // moderator can apply when removing a post/comment, optionally
    // sent to the removed user.

    /// Fetches a subreddit's configured removal reasons. Returns an
    /// empty array (not an error) for subreddits with none configured
    /// or non-moderators, matching Reddit's response shape.
    public func fetchRemovalReasons(subreddit: String) async throws -> [RedditRemovalReason] {
        let data = try await client.get(path: "/api/v1/\(subreddit)/removal_reasons")
        guard let raw = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return [] }
        return RedditRemovalReason.parseList(from: raw)
    }

    /// Removes content while applying one of the subreddit's canned
    /// removal reasons; a separate endpoint from plain `api/remove`.
    /// Callers should also call `remove(fullname:isSpam:)` since this
    /// endpoint only attaches the reason/note.
    @discardableResult
    public func applyRemovalReason(fullname: String, reasonID: String, modNote: String = "") async throws -> Data {
        try await client.post(path: "/api/v1/modactions/removal_reasons", parameters: [
            "item_ids": fullname,
            "reason_id": reasonID,
            "mod_note": modNote,
        ])
    }

    /// Sends the removal-reason notification Apollo's "Notify user via…"
    /// step offers after logging a reason: a stickied public reply, or
    /// modmail from the subreddit or from the moderator. Reborn adds
    /// `publicAsSubreddit` (#515), which Reddit posts as u/<Sub>-ModTeam.
    @discardableResult
    public func sendRemovalMessage(fullname: String, kind: RemovalNotifyKind,
                                   title: String, message: String) async throws -> Data {
        let path = fullname.hasPrefix("t1_")
            ? "/api/v1/modactions/removal_comment_message"
            : "/api/v1/modactions/removal_link_message"
        return try await client.post(path: path, parameters: [
            "item_id": fullname,
            "type": kind.rawValue,
            "title": title,
            "message": message,
        ])
    }

    // MARK: - Banned/muted user management

    public func fetchBannedUsers(subreddit: String) async throws -> [ModeratorListedUser] {
        let data = try await client.get(path: "/r/\(subreddit)/about/banned")
        let response = try JSONDecoder().decode(ModeratorUserListResponse.self, from: data)
        return response.data.children
    }

    public func fetchMutedUsers(subreddit: String) async throws -> [ModeratorListedUser] {
        let data = try await client.get(path: "/r/\(subreddit)/about/muted")
        let response = try JSONDecoder().decode(ModeratorUserListResponse.self, from: data)
        return response.data.children
    }

    public func fetchApprovedSubmitters(subreddit: String) async throws -> [ModeratorListedUser] {
        let data = try await client.get(path: "/r/\(subreddit)/about/contributors")
        let response = try JSONDecoder().decode(ModeratorUserListResponse.self, from: data)
        return response.data.children
    }


    /// `durationDays` nil = permanent ban. `banMessage` ("Note to
    /// User") is what the banned user themselves sees, distinct from
    /// `note` (the private mod note, visible only to other
    /// moderators). Reddit's `/api/friend` ban endpoint accepts both
    /// `note` and `ban_message` as separate fields.
    @discardableResult
    public func banUser(username: String, subreddit: String, reason: String, note: String, banMessage: String = "", durationDays: Int?) async throws -> Data {
        var params = [
            "api_type": "json",
            "name": username,
            "ban_reason": reason,
            "note": note,
            "ban_message": banMessage,
        ]
        if let durationDays {
            params["duration"] = String(durationDays)
        }
        return try await client.post(path: "/r/\(subreddit)/api/friend", parameters: params.merging(["type": "banned"]) { a, _ in a })
    }

    @discardableResult
    public func unbanUser(username: String, subreddit: String) async throws -> Data {
        try await client.post(path: "/r/\(subreddit)/api/unfriend", parameters: ["name": username, "type": "banned"])
    }

    /// `note` is a private mod note ("Reason (optional and private)"),
    /// distinct from a ban's mod note; `/api/friend` accepts it for any
    /// relationship type.
    @discardableResult
    public func muteUser(username: String, subreddit: String, note: String = "") async throws -> Data {
        var params = ["name": username, "type": "muted"]
        if !note.isEmpty { params["note"] = note }
        return try await client.post(path: "/r/\(subreddit)/api/friend", parameters: params)
    }

    @discardableResult
    public func unmuteUser(username: String, subreddit: String) async throws -> Data {
        try await client.post(path: "/r/\(subreddit)/api/unfriend", parameters: ["name": username, "type": "muted"])
    }

    @discardableResult
    public func addApprovedSubmitter(username: String, subreddit: String) async throws -> Data {
        try await client.post(path: "/r/\(subreddit)/api/friend", parameters: ["name": username, "type": "contributor"])
    }

    @discardableResult
    public func removeApprovedSubmitter(username: String, subreddit: String) async throws -> Data {
        try await client.post(path: "/r/\(subreddit)/api/unfriend", parameters: ["name": username, "type": "contributor"])
    }

    /// Fetches a subreddit's moderator log, returning the paging cursor
    /// alongside the entries so callers can page past the first ~25.
    /// Supports Reddit's `type`/`mod` query params (the by-moderator and
    /// per-action-type filters), both `nil` by default (unfiltered).
    public func fetchModeratorLog(subreddit: String, after: String? = nil, actionType: String? = nil, moderator: String? = nil) async throws -> (entries: [ModeratorLogEntry], after: String?) {
        var parameters: [String: String] = [:]
        if let after { parameters["after"] = after }
        if let actionType { parameters["type"] = actionType }
        if let moderator { parameters["mod"] = moderator }
        let data = try await client.get(path: "/r/\(subreddit)/about/log", parameters: parameters)
        let response = try JSONDecoder.reddit.decode(ModeratorLogResponse.self, from: data)
        return (response.data.children.map(\.data), response.data.after)
    }

    /// Reads and edits a subreddit's AutoModerator configuration,
    /// which Reddit stores as a plain wiki page at
    /// `config/automoderator`.
    public func fetchAutoModeratorConfig(subreddit: String) async throws -> String {
        let data = try await client.get(path: "/r/\(subreddit)/wiki/config/automoderator")
        let response = try JSONDecoder().decode(WikiPageResponse.self, from: data)
        return response.data.contentMd
    }

    public func saveAutoModeratorConfig(subreddit: String, content: String) async throws {
        try await client.post(path: "/r/\(subreddit)/api/wiki/edit", parameters: [
            "page": "config/automoderator",
            "content": content,
        ])
    }

    /// Mod-only subscriber/pageview traffic history.
    public func fetchSubredditTraffic(subreddit: String) async throws -> SubredditTraffic {
        let data = try await client.get(path: "/r/\(subreddit)/about/traffic")
        return try JSONDecoder().decode(SubredditTraffic.self, from: data)
    }

    /// Fetches modmail conversations for subreddits the user
    /// moderates. `state` supports Apollo's 5-tab modmail structure
    /// (see `ModmailInboxTab`'s doc comment for the per-tab `state`
    /// values). Defaults to `"all"`, matching callers (like
    /// `InboxListScreen`'s unified-inbox modmail surfacing) that want
    /// everything.
    /// Thrown when new modmail is requested under a cookie/web
    /// session, which cannot reach it at all.
    ///
    /// The request 403s under the cookie transport, which rewrites
    /// `oauth.reddit.com` to `www.reddit.com`, where
    /// `/api/mod/conversations` does not exist - the same constraint
    /// `fetchIdentity()` above documents for `/api/v1/me`.
    ///
    /// A distinct error rather than a generic failure, since retrying can
    /// never work: the cause is the account's sign-in method.
    ///
    /// The web client reaches modmail over the same cookie session through
    /// Shreddit GraphQL (`ModmailWebService`), so this error only surfaces
    /// when a web session exists but carries no usable CSRF token.
    public struct ModmailRequiresOAuthError: Error, LocalizedError {
        public init() {}
        public var errorDescription: String? {
            "New Mod Mail needs an API-key sign-in. Accounts signed in without one can't reach it — Reddit only serves modmail over OAuth."
        }
    }

    /// Fetches modmail for whichever transport the account is signed in
    /// with.
    ///
    /// `state` is the REST value (`all`, `mod`, `inprogress`, ...);
    /// the web path maps it onto Reddit's GraphQL `mailboxCategory`
    /// enum, which is NOT the same as uppercasing it.
    public func fetchModmailConversations(
        state: String = "all",
        sort: ModmailSortOption = .recent
    ) async throws -> [ModmailConversation] {
        if let session = await client.webSessionCredential {
            let category = ModmailWebService.MailboxCategory(restState: state)
            let conversations = try await ModmailWebService.fetchConversations(
                category: category,
                sort: ModmailWebService.SortOrder(rawValue: sort.graphQLValue) ?? .recent,
                session: session)
            return conversations.map(\.asModmailConversation)
        }
        return try await fetchModmailConversationPage(state: state, sort: sort).conversations
    }

    /// One page of modmail over OAuth, plus the cursor for the next.
    ///
    /// The web transport returns its first page only (its GraphQL
    /// operation's cursor variable is unknown), so `next` is always nil there.
    public func fetchModmailConversationPage(
        state: String = "all",
        sort: ModmailSortOption = .recent,
        after: String? = nil,
        limit: Int = 100
    ) async throws -> (conversations: [ModmailConversation], next: String?) {
        if await client.webSessionCredential != nil {
            guard after == nil else { return ([], nil) }
            return (try await fetchModmailConversations(state: state, sort: sort), nil)
        }
        var parameters = ["state": state, "sort": sort.restValue, "limit": String(limit)]
        if let after { parameters["after"] = after }
        let data = try await client.get(path: "/api/mod/conversations", parameters: parameters)
        let response = try JSONDecoder().decode(ModmailConversationsResponse.self, from: data)
        // Reddit returns conversations as a dictionary keyed by ID plus
        // a separate ordered ID list; conversationIds preserves display order.
        let page = response.conversationIds.compactMap { response.conversations[$0] }
        return (page, response.conversationIds.count >= limit ? response.conversationIds.last : nil)
    }

    /// Replies within an existing modmail conversation thread.
    ///
    /// `isInternal` sends a moderator-only note, which is invisible to
    /// the user the conversation is with.
    @discardableResult
    public func replyToModmail(conversationID: String, body: String, isInternal: Bool = false) async throws -> Data {
        if let session = await client.webSessionCredential {
            // `AddModmailMessage` requires the author's own fullname
            // (`t2_...`), which the REST reply never needed. Reddit's
            // `/api/me.json` returns the id bare, so the prefix has
            // to be added here; passing the bare id would fail.
            let identity = try await fetchIdentity()
            let authorID = identity.id.hasPrefix("t2_") ? identity.id : "t2_\(identity.id)"
            try await ModmailWebService.reply(
                conversationID: conversationID,
                authorID: authorID,
                body: body,
                isInternal: isInternal,
                session: session)
            return Data()
        }
        var parameters = ["body": body]
        if isInternal { parameters["isInternal"] = "true" }
        return try await client.post(path: "/api/mod/conversations/\(conversationID)", parameters: parameters)
    }

    /// Fetches one conversation and its messages via
    /// `api/mod/conversations/%@`.
    ///
    /// `markRead` is a parameter of the same call; Apollo marks a
    /// conversation read by opening it, so that is what opening it
    /// does here too.
    public func fetchModmailConversation(id: String, markRead: Bool = true) async throws -> ModmailConversationDetail {
        if let session = await client.webSessionCredential {
            let entries = try await ModmailWebService.fetchThread(
                conversationID: id, session: session)
            // Opening a conversation marks it read, same as Apollo.
            // Best-effort: a failure to mark read must not blank out
            // a thread the user can already see.
            if markRead {
                try? await ModmailWebService.setRead(true, conversationIDs: [id], session: session)
            }
            // Look the header up across categories, not just `.all`:
            // an internal conversation (a moderator messaging their
            // own subreddit) never appears in `.all`, only in
            // `.modDiscussions`. Stops at the first hit.
            var match: ModmailWebConversation?
            for category in [ModmailWebService.MailboxCategory.all, .modDiscussions, .archived] {
                let found = try? await ModmailWebService.fetchConversations(
                    category: category, session: session)
                if let hit = found?.first(where: {
                    ModmailWebService.prefixed($0.id) == ModmailWebService.prefixed(id)
                }) {
                    match = hit
                    break
                }
            }
            let header = match?.asModmailConversation ?? ModmailConversation(
                id: id, subject: "", lastUpdated: nil,
                numMessages: entries.filter(\.isMessage).count,
                subredditName: nil, lastUnread: nil)
            return ModmailConversationDetail(
                conversation: header,
                messages: entries.compactMap(\.asModmailMessage))
        }
        let data = try await client.get(
            path: "/api/mod/conversations/\(id)",
            parameters: ["markRead": markRead ? "true" : "false"]
        )
        return try ModmailConversationDetail.decode(from: data)
    }


    /// Marks every conversation in one mailbox read. Scoped to the
    /// mailbox on purpose - see `ModmailWebService`.
    @discardableResult
    public func markAllModmailRead(state: String = "all") async throws -> Data {
        if let session = await client.webSessionCredential {
            try await ModmailWebService.markAllRead(
                category: ModmailWebService.MailboxCategory(restState: state), session: session)
            return Data()
        }
        return try await client.post(path: "/api/mod/conversations/bulk/read", parameters: [:])
    }

    // MARK: Modmail quick actions
    //
    // The five per-conversation actions, each a distinct endpoint:
    // highlight, unhighlight, archive, unarchive, and mark unread.

    @discardableResult
    public func highlightModmail(conversationID: String) async throws -> Data {
        if let session = await client.webSessionCredential {
            try await ModmailWebService.setHighlighted(true, conversationIDs: [conversationID], session: session)
            return Data()
        }
        return try await client.post(path: "/api/mod/conversations/\(conversationID)/highlight", parameters: [:])
    }

    /// Unhighlight is the same path with DELETE, not a separate
    /// endpoint - Apollo has no `/unhighlight`, unlike mute/unmute
    /// and archive/unarchive which are both separate paths.
    @discardableResult
    public func unhighlightModmail(conversationID: String) async throws -> Data {
        if let session = await client.webSessionCredential {
            try await ModmailWebService.setHighlighted(false, conversationIDs: [conversationID], session: session)
            return Data()
        }
        return try await client.delete(path: "/api/mod/conversations/\(conversationID)/highlight")
    }

    @discardableResult
    public func archiveModmail(conversationID: String) async throws -> Data {
        if let session = await client.webSessionCredential {
            try await ModmailWebService.setArchived(true, conversationIDs: [conversationID], session: session)
            return Data()
        }
        return try await client.post(path: "/api/mod/conversations/\(conversationID)/archive", parameters: [:])
    }

    @discardableResult
    public func unarchiveModmail(conversationID: String) async throws -> Data {
        if let session = await client.webSessionCredential {
            try await ModmailWebService.setArchived(false, conversationIDs: [conversationID], session: session)
            return Data()
        }
        return try await client.post(path: "/api/mod/conversations/\(conversationID)/unarchive", parameters: [:])
    }

    /// Takes a `conversationIds` list, not a single id in the path.
    @discardableResult
    public func markModmailUnread(conversationIDs: [String]) async throws -> Data {
        if let session = await client.webSessionCredential {
            try await ModmailWebService.setRead(false, conversationIDs: conversationIDs, session: session)
            return Data()
        }
        return try await client.post(
            path: "/api/mod/conversations/unread",
            parameters: ["conversationIds": conversationIDs.joined(separator: ",")]
        )
    }

    /// Same list shape as `markModmailUnread`.
    @discardableResult
    public func markModmailRead(conversationIDs: [String]) async throws -> Data {
        if let session = await client.webSessionCredential {
            try await ModmailWebService.setRead(true, conversationIDs: conversationIDs, session: session)
            return Data()
        }
        return try await client.post(
            path: "/api/mod/conversations/read",
            parameters: ["conversationIds": conversationIDs.joined(separator: ",")]
        )
    }

    @discardableResult
    public func muteModmail(conversationID: String) async throws -> Data {
        try await client.post(path: "/api/mod/conversations/\(conversationID)/mute", parameters: [:])
    }

    @discardableResult
    public func unmuteModmail(conversationID: String) async throws -> Data {
        try await client.post(path: "/api/mod/conversations/\(conversationID)/unmute", parameters: [:])
    }
}
