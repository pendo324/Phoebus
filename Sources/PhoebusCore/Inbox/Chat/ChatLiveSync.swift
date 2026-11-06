import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Event-driven Reddit Chat while the app is open.
///
/// Matrix's `/sync` is a long poll: with `since` and `timeout`, the
/// homeserver holds the request open until something happens (a message,
/// a typing notice, a receipt) or the timeout passes, then answers with
/// only what changed. One request in flight at a time therefore delivers
/// events as they happen, instead of every screen polling on its own
/// timer and re-downloading every room.
///
/// Push while the app is closed is a different matter: Matrix pushers
/// need a push gateway holding this app's APNs credentials, which a
/// sideloaded build does not have, so background delivery stays with
/// Bark and the notification backend.
public actor ChatLiveSync {
    public struct Update: Sendable {
        /// Every room, merged across all syncs so far.
        public let snapshot: RedditChatClient.SyncResult
        /// Rooms that received timeline events in this sync.
        public let timelineRoomIDs: Set<String>
        /// Typing and receipt state per room, merged across syncs.
        public let ephemeral: [String: RedditChatClient.RoomEphemeral]
        /// The first, full sync.
        public let isInitial: Bool
        /// Made by a change on this device (answering a request, muting), not by Reddit.
        public var isLocalChange: Bool = false
    }

    /// How long the homeserver may hold one request, in milliseconds.
    static let longPollTimeout = 30_000

    private let repository: RedditRepository
    private var state = ChatSyncState()
    private var loop: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<Update>.Continuation] = [:]
    private var lastUpdate: Update?

    public init(repository: RedditRepository) {
        self.repository = repository
    }

    /// Updates as they arrive. A new subscriber first gets the latest
    /// state, so a screen opened mid-session doesn't wait for the next
    /// event.
    public func updates() -> AsyncStream<Update> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        if let lastUpdate { continuation.yield(lastUpdate) }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    public var isRunning: Bool { loop != nil }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    private func run() async {
        var since: String?
        var failures = 0
        while !Task.isCancelled {
            do {
                let data = try await repository.chatSyncData(
                    since: since, timeoutMilliseconds: since == nil ? 0 : Self.longPollTimeout)
                if Task.isCancelled { return }
                let delta = try ChatSyncDelta(parsing: data)
                let isInitial = since == nil
                state.apply(delta, replacing: isInitial)
                since = delta.nextBatch ?? since
                failures = 0
                // An empty long-poll answer (the timeout passed) changes
                // nothing, so nobody needs waking.
                guard isInitial || delta.hasChanges else { continue }
                publish(Update(snapshot: state.snapshot(nextBatch: since), timelineRoomIDs: delta.timelineRoomIDs,
                               ephemeral: state.ephemeral, isInitial: isInitial))
                if isInitial { await refreshMuteRules() }
            } catch RedditChatClient.ChatError.noWebSession {
                // No Chat for this account; nothing to retry.
                loop = nil
                return
            } catch {
                if Task.isCancelled { return }
                failures += 1
                // 5 s, 10 s, 20 s, then once a minute.
                let delay = min(60, 5 * (1 << min(failures - 1, 4)))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func publish(_ update: Update) {
        lastUpdate = update
        for continuation in subscribers.values { continuation.yield(update) }
    }

    private func publishLocalChange() {
        publish(Update(snapshot: state.snapshot(nextBatch: lastUpdate?.snapshot.nextBatch), timelineRoomIDs: [],
                       ephemeral: state.ephemeral, isInitial: false, isLocalChange: true))
    }

    /// Reads which rooms the account has muted (its push rules, which `/sync`
    /// does not carry) and marks them. Best effort: a failure leaves the
    /// rooms as they were.
    public func refreshMuteRules() async {
        guard let muted = try? await repository.fetchChatMutedRoomIDs() else { return }
        applyMuteRules(muted)
    }

    func applyMuteRules(_ muted: Set<String>, now: Date = Date()) {
        let before = state.rooms
        state.applyMutedRules(muted, now: now)
        if state.rooms != before { publishLocalChange() }
    }

    /// Mutes or unmutes a joined room, optimistically.
    ///
    /// The row, the badge and the totals change at once, `perform` sends the
    /// rule, and a failure puts everything back before the error reaches the
    /// caller. Reddit flips its own counted flag afterwards, so the room is
    /// read again once the rule is in.
    public func setMuted(
        _ muted: Bool,
        room: ChatRoom,
        perform: @Sendable () async throws -> Void
    ) async throws {
        let action: ChatMuteAction = muted ? .mute : .unmute
        switch state.beginMute(action, room: room) {
        case .unchanged: return
        case .busy: throw ChatMuteError.busy
        case .notJoined: throw ChatMuteError.notAJoinedRoom
        case .started: break
        }
        publishLocalChange()
        do {
            try await perform()
            state.settleMute(roomID: room.id)
            publishLocalChange()
        } catch {
            state.rollbackMute(roomID: room.id)
            publishLocalChange()
            throw error
        }
    }

    public func setMuted(_ muted: Bool, room: ChatRoom) async throws {
        try await setMuted(muted, room: room) { [repository] in
            try await repository.sendChatMute(muted ? .mute : .unmute, roomID: room.id)
        }
        confirmMute(roomID: room.id)
    }

    /// Reads the room's counted flag from Reddit once the rule has had a moment to take effect.
    private func confirmMute(roomID: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let result = try? await self.repository.fetchChatRooms() else { return }
            await self.adoptServerRoom(result.rooms.first { $0.id == roomID })
        }
    }

    func adoptServerRoom(_ server: ChatRoom?) {
        guard let server else { return }
        let before = state.rooms
        state.confirmMute(server: server)
        if state.rooms != before { publishLocalChange() }
    }

    /// Accepts or declines a chat request, optimistically.
    ///
    /// The list and the badge change at once, `perform` sends the answer, and
    /// a failure puts the request back before the error reaches the caller.
    public func answerRequest(
        _ action: ChatRequestAction,
        room: ChatRoom,
        perform: @Sendable () async throws -> Void
    ) async throws {
        guard state.beginRequest(action, room: room) else { throw ChatRequestError.notPending }
        publishLocalChange()
        do {
            try await perform()
            state.settleRequest(roomID: room.id)
        } catch {
            state.rollbackRequest(roomID: room.id)
            publishLocalChange()
            throw error
        }
    }

    public func answerRequest(_ action: ChatRequestAction, room: ChatRoom) async throws {
        try await answerRequest(action, room: room) { [repository] in
            try await repository.sendChatRequestAnswer(action, roomID: room.id)
        }
    }

    /// A fetched room list with the local answers still in effect.
    public func reconciled(_ result: RedditChatClient.SyncResult) -> RedditChatClient.SyncResult {
        state.reconciled(result)
    }
}

/// One `/sync` response as a change set: only the rooms, counters and
/// ephemeral events it actually carried.
public struct ChatSyncDelta: Sendable {
    public struct RoomChange: Sendable {
        public let room: ChatRoom
        /// The response carried `unread_notifications` for this room.
        public let hasCounts: Bool
    }

    public var rooms: [String: RoomChange] = [:]
    public var leftRoomIDs: Set<String> = []
    public var unreadCount: Int?
    public var requestsCount: Int?
    public var nextBatch: String?
    public var timelineRoomIDs: Set<String> = []
    /// Per room: the typing list when an `m.typing` event came (empty
    /// means everyone stopped), and any new receipts.
    public var typing: [String: [String]] = [:]
    public var receipts: [String: [String: String]] = [:]

    public var hasChanges: Bool {
        !rooms.isEmpty || !leftRoomIDs.isEmpty || unreadCount != nil || requestsCount != nil
            || !typing.isEmpty || !receipts.isEmpty
    }

    public init(parsing data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RedditChatClient.ChatError.httpError(status: 0)
        }
        unreadCount = (root[RedditChatClient.unreadCounterKey] as? NSNumber)?.intValue
        requestsCount = (root[RedditChatClient.requestsCounterKey] as? NSNumber)?.intValue
        nextBatch = root["next_batch"] as? String
        let roomsRoot = root["rooms"] as? [String: Any] ?? [:]
        for (bucket, isInvite) in [("join", false), ("invite", true)] {
            guard let group = roomsRoot[bucket] as? [String: Any] else { continue }
            for (roomID, value) in group {
                guard let payload = value as? [String: Any] else { continue }
                rooms[roomID] = RoomChange(
                    room: RedditChatClient.parseRoom(id: roomID, payload: payload, isInvite: isInvite),
                    hasCounts: payload["unread_notifications"] != nil)
                let timeline = (payload["timeline"] as? [String: Any])?["events"] as? [[String: Any]] ?? []
                if !timeline.isEmpty { timelineRoomIDs.insert(roomID) }
            }
        }
        if let left = roomsRoot["leave"] as? [String: Any] { leftRoomIDs = Set(left.keys) }
        for (roomID, events) in RedditChatClient.parseEphemeralEvents(data) {
            if let list = events.typing { typing[roomID] = list }
            if !events.receipts.isEmpty { receipts[roomID] = events.receipts }
        }
    }
}

/// Every room seen so far, with incremental syncs merged in.
///
/// An incremental response lists only rooms that changed, and within
/// them only the new events, so a room's name or participants are kept
/// from earlier responses rather than read as missing.
public struct ChatSyncState: Sendable {
    public private(set) var rooms: [String: ChatRoom] = [:]
    public private(set) var unreadCount = 0
    public private(set) var requestsCount = 0
    /// Typing and receipts per room, merged: receipts accumulate, and
    /// typing is replaced whenever a sync reports it.
    public private(set) var ephemeral: [String: RedditChatClient.RoomEphemeral] = [:]
    /// Requests answered here whose answer the homeserver's sync has not yet reflected.
    private var answered: [String: AnsweredRequest] = [:]

    private struct AnsweredRequest {
        let action: ChatRequestAction
        /// The request as it was, to put back when the answer fails.
        let original: ChatRoom
        /// When the homeserver accepted the answer; nil while it is in flight.
        var settledAt: Date?
        /// Whether the request was part of Reddit's request counter, and so lowered it.
        var counted: Bool = true

        func hidesInvite(at now: Date) -> Bool {
            guard let settledAt else { return true }
            return now.timeIntervalSince(settledAt) < ChatRequests.staleInviteShield
        }
    }

    /// Rooms the account's push rules mute, as last read or changed here.
    public private(set) var mutedRoomIDs: Set<String> = []
    /// Mutes and unmutes made here whose effect Reddit's sync may not show yet.
    private var pendingMutes: [String: PendingMute] = [:]

    private struct PendingMute {
        let muted: Bool
        /// The room as it was, to put back when the change fails.
        let original: ChatRoom
        /// When the homeserver took the change; nil while it is in flight.
        var settledAt: Date?

        func shields(at now: Date) -> Bool {
            guard let settledAt else { return true }
            return now.timeIntervalSince(settledAt) < ChatMute.staleShield
        }
    }

    public enum MuteStart: Equatable, Sendable {
        case started
        /// The room already is as asked.
        case unchanged
        /// A change to this room is in flight.
        case busy
        /// Not a joined room Phoebus has listed.
        case notJoined
    }

    public init() {}

    /// The room with its mute state: the push rules, or a change made here that Reddit's
    /// sync has not caught up with, for which Reddit's counted flag is taken to follow it.
    private func withMute(_ room: ChatRoom, now: Date) -> ChatRoom {
        guard !room.isInvite else { return room }
        var muted = mutedRoomIDs.contains(room.id)
        var counted = room.countsTowardGlobalBadge
        if let pending = pendingMutes[room.id], pending.shields(at: now) {
            muted = pending.muted
            counted = !pending.muted
        }
        return room.withMute(muted, countsTowardGlobalBadge: counted)
    }

    private func isShielding(at now: Date) -> Bool {
        pendingMutes.values.contains { $0.shields(at: now) }
    }

    /// Starts muting or unmuting a room: the row and the badge total change at once.
    public mutating func beginMute(_ action: ChatMuteAction, room: ChatRoom, now: Date = Date()) -> MuteStart {
        let current = rooms[room.id] ?? room
        guard !current.isInvite else { return .notJoined }
        if let pending = pendingMutes[room.id], pending.shields(at: now), pending.settledAt == nil { return .busy }
        guard current.isMuted != action.isMute else { return .unchanged }
        pendingMutes[room.id] = PendingMute(muted: action.isMute, original: current, settledAt: nil)
        if action.isMute { mutedRoomIDs.insert(room.id) } else { mutedRoomIDs.remove(room.id) }
        replace(current, with: withMute(current, now: now))
        return .started
    }

    /// The homeserver took the change. The local view stays until a sync agrees with it.
    public mutating func settleMute(roomID: String, now: Date = Date()) {
        pendingMutes[roomID]?.settledAt = now
    }

    /// The change failed: the room and the totals are back as they were.
    public mutating func rollbackMute(roomID: String) {
        guard let entry = pendingMutes.removeValue(forKey: roomID) else { return }
        if entry.original.isMuted { mutedRoomIDs.insert(roomID) } else { mutedRoomIDs.remove(roomID) }
        if let current = rooms[roomID] { replace(current, with: entry.original) }
    }

    /// Reddit's own view of a room read after a change: once its counted flag
    /// follows the rule, nothing local is needed any more.
    public mutating func confirmMute(server: ChatRoom, now: Date = Date()) {
        guard let pending = pendingMutes[server.id], pending.settledAt != nil,
              server.countsTowardGlobalBadge == !pending.muted, let current = rooms[server.id] else { return }
        pendingMutes[server.id] = nil
        replace(current, with: withMute(current.withMute(current.isMuted, countsTowardGlobalBadge: server.countsTowardGlobalBadge), now: now))
    }

    /// The muted rooms as the account's push rules list them. A room with a change in
    /// flight keeps what was asked for.
    public mutating func applyMutedRules(_ muted: Set<String>, now: Date = Date()) {
        var next = muted
        for (id, pending) in pendingMutes where pending.shields(at: now) {
            if pending.muted { next.insert(id) } else { next.remove(id) }
        }
        mutedRoomIDs = next
        for (id, room) in rooms where !room.isInvite {
            rooms[id] = withMute(room, now: now)
        }
    }

    /// Swaps a room and moves the badge total by what its unread count did.
    private mutating func replace(_ old: ChatRoom, with new: ChatRoom) {
        let was = ChatRoomUnread.countsTowardBadge(old) ? old.notificationCount : 0
        let now = ChatRoomUnread.countsTowardBadge(new) ? new.notificationCount : 0
        rooms[new.id] = new
        unreadCount = max(0, unreadCount + now - was)
    }

    /// Starts answering a request: it leaves Requests (declined) or becomes a
    /// joined room (accepted) and the request count drops. False when the room
    /// is not a pending request or is already being answered.
    public mutating func beginRequest(_ action: ChatRequestAction, room: ChatRoom) -> Bool {
        let current = rooms[room.id] ?? room
        guard current.isInvite, answered[room.id] == nil else { return false }
        let counted = ChatRequests.countsAsRequest(current)
        answered[room.id] = AnsweredRequest(action: action, original: current, settledAt: nil, counted: counted)
        rooms[room.id] = action == .accept ? current.withInvite(false) : nil
        if counted { requestsCount = max(0, requestsCount - 1) }
        return true
    }

    /// The homeserver took the answer. The local view stays until a sync agrees with it.
    public mutating func settleRequest(roomID: String, now: Date = Date()) {
        answered[roomID]?.settledAt = now
    }

    /// The answer failed: the request is back where it was.
    public mutating func rollbackRequest(roomID: String) {
        guard let entry = answered.removeValue(forKey: roomID) else { return }
        rooms[roomID] = entry.original
        if entry.counted { requestsCount += 1 }
    }

    /// A fetched list with answers still in effect applied, so a pull to refresh
    /// during an answer does not bring a request back.
    public func reconciled(_ result: RedditChatClient.SyncResult, now: Date = Date()) -> RedditChatClient.SyncResult {
        let hiding = answered.filter { $0.value.hidesInvite(at: now) }
        var list: [ChatRoom] = []
        for room in result.rooms {
            guard room.isInvite, let entry = hiding[room.id] else { list.append(withMute(room, now: now)); continue }
            if entry.action == .accept, let local = rooms[room.id] { list.append(local) }
        }
        let unread = isShielding(at: now) ? ChatRoomUnread.badgeTotal(of: list) : result.unreadCount
        return RedditChatClient.SyncResult(
            unreadCount: unread, requestsCount: hiding.isEmpty ? result.requestsCount : min(result.requestsCount, requestsCount),
            rooms: list, nextBatch: result.nextBatch)
    }

    public mutating func apply(_ delta: ChatSyncDelta, replacing: Bool = false, now: Date = Date()) {
        if replacing { rooms = [:]; ephemeral = [:]; answered = [:] }
        for roomID in Set(delta.typing.keys).union(delta.receipts.keys) {
            let old = ephemeral[roomID] ?? .init()
            ephemeral[roomID] = .init(
                typingUserIDs: delta.typing[roomID] ?? old.typingUserIDs,
                readReceipts: old.readReceipts.merging(delta.receipts[roomID] ?? [:]) { $1 })
        }
        for id in delta.leftRoomIDs { rooms[id] = nil; answered[id] = nil }
        for (id, change) in delta.rooms {
            if let entry = answered[id] {
                // A sync that began before the answer still lists the old invite.
                if change.room.isInvite, entry.hidesInvite(at: now) { continue }
                answered[id] = nil
            }
            rooms[id] = withMute(rooms[id].map { Self.merge($0, change) } ?? change.room, now: now)
        }
        // Reddit's own counters when the response carries them;
        // otherwise derived from the rooms, which is what they count.
        // While a mute change is settling Reddit's counter lags it, so the rooms are used.
        unreadCount = isShielding(at: now) ? ChatRoomUnread.badgeTotal(of: Array(rooms.values))
            : delta.unreadCount ?? (delta.rooms.isEmpty ? unreadCount
            : ChatRoomUnread.badgeTotal(of: Array(rooms.values)))
        // Reddit's counter can still include a request answered a moment ago, so
        // while an answer is awaiting its sync the lower of the two is kept.
        let answering = answered.values.contains { $0.hidesInvite(at: now) }
        let derived = rooms.values.filter { $0.isInvite && ChatRequests.countsAsRequest($0) }.count
        let reported = delta.requestsCount ?? (delta.rooms.isEmpty ? requestsCount : derived)
        requestsCount = answering ? min(reported, requestsCount) : reported
    }

    static func merge(_ old: ChatRoom, _ change: ChatSyncDelta.RoomChange) -> ChatRoom {
        let new = change.room
        let newer = new.lastMessageTimestamp >= old.lastMessageTimestamp && new.lastMessageTimestamp > 0
        return ChatRoom(
            id: old.id,
            name: new.name ?? old.name,
            chatType: new.chatType ?? old.chatType,
            participants: Array(Set(old.participants).union(new.participants)).sorted(),
            isInvite: new.isInvite,
            lastMessageTimestamp: max(old.lastMessageTimestamp, new.lastMessageTimestamp),
            preview: newer ? new.preview : old.preview,
            previewSender: newer ? new.previewSender : old.previewSender,
            notificationCount: change.hasCounts ? new.notificationCount : old.notificationCount,
            countsTowardGlobalBadge: change.hasCounts ? new.countsTowardGlobalBadge : old.countsTowardGlobalBadge,
            inviter: new.inviter ?? old.inviter,
            isMuted: old.isMuted)
    }

    public func snapshot(nextBatch: String?) -> RedditChatClient.SyncResult {
        RedditChatClient.SyncResult(
            unreadCount: unreadCount, requestsCount: requestsCount,
            rooms: rooms.values.sorted(by: ChatRoom.newestFirst),
            nextBatch: nextBatch)
    }
}
