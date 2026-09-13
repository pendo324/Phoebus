import Foundation

/// Reddit Chat over Matrix.
extension RedditRepository {
    // MARK: - Reddit Chat (Matrix)

    /// Caches the minted Matrix bearer and the account's own Matrix
    /// user id. Minting costs a full round trip and the token is good
    /// for a day, so re-minting per poll would be wasteful. The
    /// expiry is read out of the JWT rather than assumed.
    private actor ChatSessionCache {
        var bearer: String?
        var selfUserID: String?

        func store(selfUserID: String?) { self.selfUserID = selfUserID }
        func currentSelfUserID() -> String? { selfUserID }

        func currentBearer() -> String? {
            guard let bearer, !RedditChatClient.isExpired(bearer) else { return nil }
            return bearer
        }

        func store(bearer: String) { self.bearer = bearer }
        func clearBearer() { bearer = nil }
    }

    /// One per account, so a switch never carries over the previous
    /// account's bearer, sync token and user id.
    private actor ChatSessionCaches {
        private var byAccount: [String: ChatSessionCache] = [:]
        func cache(for account: String) -> ChatSessionCache {
            if let existing = byAccount[account] { return existing }
            let made = ChatSessionCache()
            byAccount[account] = made
            return made
        }
    }

    private static let chatCaches = ChatSessionCaches()

    /// The active account's name, lowercased, for chat state.
    func chatAccount() async -> String {
        (await webFeatureSession()?.username ?? FavoriteSubredditsAccountContext.currentUsernameProvider() ?? "").lowercased()
    }

    private var chatCache: ChatSessionCache {
        get async { await RedditRepository.chatCaches.cache(for: await chatAccount()) }
    }

    /// A valid Matrix bearer for the active account, minting one when
    /// needed.
    private func chatBearer(forceMint: Bool = false) async throws -> String {
        if !forceMint, let cached = await chatCache.currentBearer() {
            return cached
        }
        guard let session = await webFeatureSession() else {
            throw RedditChatClient.ChatError.noWebSession
        }
        // The session's own token_v2 while it lasts; a forced mint means
        // that one was just rejected.
        if !forceMint, let stored = RedditChatClient.storedBearer(cookieHeader: session.cookieHeader) {
            await chatCache.store(bearer: stored)
            return stored
        }
        let bearer = try await RedditChatClient.mintBearer(cookieHeader: session.cookieHeader)
        await chatCache.store(bearer: bearer)
        return bearer
    }

    /// Fetches the Chat room list and unread counters. Retries once
    /// with a freshly minted bearer on 401/403: a rejected token must
    /// be re-minted, never retried as-is.
    public func fetchChatRooms() async throws -> RedditChatClient.SyncResult {
        do {
            let bearer = try await chatBearer()
            return try await RedditChatClient.sync(bearer: bearer)
        } catch RedditChatClient.ChatError.unauthorized {
            await chatCache.clearBearer()
            let bearer = try await chatBearer(forceMint: true)
            return try await RedditChatClient.sync(bearer: bearer)
        }
    }

    /// One `/sync` for `ChatLiveSync`, re-minting once on 401.
    public func chatSyncData(since: String?, timeoutMilliseconds: Int) async throws -> Data {
        do {
            return try await RedditChatClient.liveSync(
                bearer: try await chatBearer(), since: since, timeoutMilliseconds: timeoutMilliseconds)
        } catch RedditChatClient.ChatError.unauthorized {
            await chatCache.clearBearer()
            return try await RedditChatClient.liveSync(
                bearer: try await chatBearer(forceMint: true), since: since, timeoutMilliseconds: timeoutMilliseconds)
        }
    }

    /// Fetches a chat room's recent messages, re-minting once on 401.
    public func fetchChatMessages(roomID: String, limit: Int = 50) async throws -> [RedditChatClient.ChatMessage] {
        do {
            return try await RedditChatClient.messages(roomID: roomID, bearer: try await chatBearer(), limit: limit)
        } catch RedditChatClient.ChatError.unauthorized {
            await chatCache.clearBearer()
            return try await RedditChatClient.messages(roomID: roomID, bearer: try await chatBearer(forceMint: true), limit: limit)
        }
    }

    /// The persistent chat outbox.
    public static let chatSendQueue = ChatSendQueue()

    /// Queues a message and drains the room's outbox.
    ///
    /// Returns the queued entry immediately so the UI can show it as
    /// pending; the send happens as part of the drain.
    @discardableResult
    public func enqueueChatMessage(roomID: String, body: String) async -> ChatSendQueue.Entry {
        let entry = await RedditRepository.chatSendQueue.enqueue(roomID: roomID, body: body, account: await chatAccount())
        await drainChatQueue(roomID: roomID)
        return entry
    }

    /// Sends queued messages for a room, oldest first, stopping at the
    /// first failure so a conversation cannot arrive out of order. See
    /// `ChatSendQueue`.
    public func drainChatQueue(roomID: String) async {
        let account = await chatAccount()
        while let entry = await RedditRepository.chatSendQueue.claimNext(roomID: roomID, account: account) {
            do {
                let eventID = try await sendChatMessage(entry: entry)
                await RedditRepository.chatSendQueue.markSent(id: entry.id, eventID: eventID)
            } catch {
                let recoverable = RedditChatClient.isRecoverable(error)
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await RedditRepository.chatSendQueue.markFailed(
                    id: entry.id, message: message, isRecoverable: recoverable)
                // Stop either way: a recoverable failure will be retried
                // on the next drain, and an unrecoverable one is parked.
                // Continuing past it would reorder the conversation.
                return
            }
        }
    }

    /// One send attempt, re-minting once on 401. The retry reuses the
    /// same transaction id: replaying it returns the same `event_id`
    /// rather than posting a second message.
    private func sendChatMessage(entry: ChatSendQueue.Entry) async throws -> String {
        do {
            return try await RedditChatClient.send(
                roomID: entry.roomID, body: entry.body,
                transactionID: entry.transactionID, bearer: try await chatBearer())
        } catch RedditChatClient.ChatError.unauthorized {
            await chatCache.clearBearer()
            return try await RedditChatClient.send(
                roomID: entry.roomID, body: entry.body,
                transactionID: entry.transactionID, bearer: try await chatBearer(forceMint: true))
        }
    }

    /// Messages still queued for a room.
    public func pendingChatMessages(roomID: String) async -> [ChatSendQueue.Entry] {
        await RedditRepository.chatSendQueue.pendingEntries(roomID: roomID, account: await chatAccount())
    }

    public func abortChatMessage(id: String) async {
        await RedditRepository.chatSendQueue.abort(id: id)
    }

    public func retryChatMessage(id: String, roomID: String) async {
        await RedditRepository.chatSendQueue.retry(id: id)
        await drainChatQueue(roomID: roomID)
    }

    /// Edits one of your own messages.
    public func editChatMessage(roomID: String, eventID: String, newBody: String) async throws {
        let txn = ChatSendQueue.makeTransactionID()
        do {
            _ = try await RedditChatClient.editMessage(
                roomID: roomID, eventID: eventID, newBody: newBody,
                transactionID: txn, bearer: try await chatBearer())
        } catch RedditChatClient.ChatError.unauthorized {
            await chatCache.clearBearer()
            // Same txn id on retry, for the reason the send path
            // documents: it is the idempotency key.
            _ = try await RedditChatClient.editMessage(
                roomID: roomID, eventID: eventID, newBody: newBody,
                transactionID: txn, bearer: try await chatBearer(forceMint: true))
        }
    }

    /// Deletes one of your own messages.
    public func deleteChatMessage(roomID: String, eventID: String) async throws {
        let txn = ChatSendQueue.makeTransactionID()
        do {
            _ = try await RedditChatClient.redactMessage(
                roomID: roomID, eventID: eventID, reason: nil,
                transactionID: txn, bearer: try await chatBearer())
        } catch RedditChatClient.ChatError.unauthorized {
            await chatCache.clearBearer()
            _ = try await RedditChatClient.redactMessage(
                roomID: roomID, eventID: eventID, reason: nil,
                transactionID: txn, bearer: try await chatBearer(forceMint: true))
        }
    }

    /// Reactions for many messages at once.
    ///
    /// Reddit delivers reactions ONLY through `/sync` and `/relations`,
    /// never through `/messages`, so a room's reactions cost one
    /// request per message. They are fetched concurrently and bounded,
    /// and a failure yields no reactions for that message rather than
    /// failing the room - reactions are decoration, and losing the
    /// conversation over them would be a bad trade.
    /// `messages` rather than bare ids, because an edited message can
    /// carry reactions on its EDIT event as well as on the original and
    /// both must be gathered under the message the user sees.
    public func chatReactions(
        roomID: String,
        messages: [RedditChatClient.ChatMessage]
    ) async -> [String: [RedditChatClient.MessageReaction]] {
        // Each request is tagged with the message it belongs to, so an
        // edit's reactions land on the message that is actually shown.
        let pairs = messages.flatMap { message in
            message.reactionEventIDs.map { (message.id, $0) }
        }
        return await chatReactions(roomID: roomID, pairs: pairs)
    }

    private func chatReactions(
        roomID: String,
        pairs: [(String, String)]
    ) async -> [String: [RedditChatClient.MessageReaction]] {
        guard !pairs.isEmpty else { return [:] }
        let bearer: String
        do { bearer = try await chatBearer() } catch { return [:] }
        let me = await chatCache.currentSelfUserID()
        // Bounded so a long room cannot open 200 sockets at once.
        let limit = 6
        var result: [String: [RedditChatClient.MessageReaction]] = [:]
        var index = 0
        while index < pairs.count {
            let slice = Array(pairs[index..<min(index + limit, pairs.count)])
            await withTaskGroup(of: (String, [RedditChatClient.MessageReaction]).self) { group in
                for (messageID, eventID) in slice {
                    group.addTask {
                        let found = try? await RedditChatClient.reactions(
                            roomID: roomID, eventID: eventID, myUserID: me, bearer: bearer)
                        return (messageID, found ?? [])
                    }
                }
                for await (messageID, found) in group where !found.isEmpty {
                    result[messageID, default: []].append(contentsOf: found)
                }
            }
            index += limit
        }
        return result
    }

    /// Toggles one reaction on a message.
    ///
    /// Reacting again with a key you already used would 409, so an
    /// existing own-reaction is removed instead. That makes the picker
    /// a toggle, which is what tapping an active reaction should do.
    public func toggleChatReaction(
        roomID: String,
        eventID: String,
        key: String,
        existing: RedditChatClient.MessageReaction?
    ) async throws {
        let bearer = try await chatBearer()
        let txn = ChatSendQueue.makeTransactionID()
        if let mine = existing?.myEventID {
            _ = try await RedditChatClient.removeReaction(
                roomID: roomID, reactionEventID: mine,
                transactionID: txn, bearer: bearer)
        } else {
            _ = try await RedditChatClient.addReaction(
                roomID: roomID, eventID: eventID, key: key,
                transactionID: txn, bearer: bearer)
        }
    }

    /// Marks a room read up to a message. Best-effort.
    public func markChatRead(roomID: String, eventID: String) async {
        guard let bearer = try? await chatBearer() else { return }
        await RedditChatClient.sendReadReceipt(roomID: roomID, eventID: eventID, bearer: bearer)
    }

    /// Publishes a typing notice for the active account.
    public func setChatTyping(roomID: String, isTyping: Bool) async {
        guard let bearer = try? await chatBearer(),
              let userID = await chatSelfUserID() else { return }
        await RedditChatClient.sendTyping(
            roomID: roomID, userID: userID, isTyping: isTyping, bearer: bearer)
    }

    /// Uploads an image and sends it as an `m.image` message.
    ///
    /// Not routed through `ChatSendQueue`: the queue persists a text body,
    /// and an image's payload is the uploaded bytes. A failed image send is
    /// reported, not silently retried.
    @discardableResult
    public func sendChatImage(
        roomID: String,
        data: Data,
        filename: String,
        mimeType: String,
        width: Int,
        height: Int
    ) async throws -> String {
        let bearer = try await chatBearer()
        let mxc = try await RedditChatClient.uploadMedia(
            data: data, filename: filename, mimeType: mimeType, bearer: bearer)
        return try await RedditChatClient.sendImage(
            roomID: roomID, mxcURI: mxc, filename: filename, mimeType: mimeType,
            width: width, height: height, byteCount: data.count,
            transactionID: ChatSendQueue.makeTransactionID(), bearer: bearer)
    }

    /// Fetches a message's thread replies, re-minting once on 401.
    public func fetchChatThreadReplies(roomID: String, eventID: String) async throws -> [RedditChatClient.ChatMessage] {
        do {
            return try await RedditChatClient.threadReplies(
                roomID: roomID, eventID: eventID, bearer: try await chatBearer())
        } catch RedditChatClient.ChatError.unauthorized {
            await chatCache.clearBearer()
            return try await RedditChatClient.threadReplies(
                roomID: roomID, eventID: eventID, bearer: try await chatBearer(forceMint: true))
        }
    }

    /// The signed-in account's own Matrix user id, cached.
    ///
    /// Without this a direct room lists every participant including
    /// you, so each DM reads "you, them".
    public func chatSelfUserID() async -> String? {
        if let cached = await chatCache.currentSelfUserID() { return cached }
        guard let bearer = try? await chatBearer() else { return nil }
        let userID = await RedditChatClient.whoami(bearer: bearer)
        await chatCache.store(selfUserID: userID)
        return userID
    }

    /// Resolves Matrix user ids to Reddit usernames.
    ///
    /// A room's participants are opaque `t2_` ids. Reddit's own
    /// `/api/info.json` does NOT resolve them (it returns zero children), so
    /// the Matrix profile endpoint is the only source.
    public func fetchChatDisplayNames(userIDs: [String]) async -> [String: String] {
        guard let bearer = try? await chatBearer() else { return [:] }
        var names: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for userID in userIDs {
                group.addTask {
                    (userID, await RedditChatClient.displayName(forUserID: userID, bearer: bearer))
                }
            }
            for await (userID, name) in group {
                if let name, !name.isEmpty { names[userID] = name }
            }
        }
        return names
    }
}
