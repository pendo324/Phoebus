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

    public init() {}

    public mutating func apply(_ delta: ChatSyncDelta, replacing: Bool = false) {
        if replacing { rooms = [:]; ephemeral = [:] }
        for roomID in Set(delta.typing.keys).union(delta.receipts.keys) {
            let old = ephemeral[roomID] ?? .init()
            ephemeral[roomID] = .init(
                typingUserIDs: delta.typing[roomID] ?? old.typingUserIDs,
                readReceipts: old.readReceipts.merging(delta.receipts[roomID] ?? [:]) { $1 })
        }
        for id in delta.leftRoomIDs { rooms[id] = nil }
        for (id, change) in delta.rooms {
            rooms[id] = rooms[id].map { Self.merge($0, change) } ?? change.room
        }
        // Reddit's own counters when the response carries them;
        // otherwise derived from the rooms, which is what they count.
        unreadCount = delta.unreadCount ?? (delta.rooms.isEmpty ? unreadCount : rooms.values
            .filter { $0.countsTowardGlobalBadge && !$0.isInvite }
            .reduce(0) { $0 + $1.notificationCount })
        requestsCount = delta.requestsCount ?? (delta.rooms.isEmpty ? requestsCount : rooms.values.filter(\.isInvite).count)
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
            countsTowardGlobalBadge: change.hasCounts ? new.countsTowardGlobalBadge : old.countsTowardGlobalBadge)
    }

    public func snapshot(nextBatch: String?) -> RedditChatClient.SyncResult {
        RedditChatClient.SyncResult(
            unreadCount: unreadCount, requestsCount: requestsCount,
            rooms: rooms.values.sorted { $0.lastMessageTimestamp > $1.lastMessageTimestamp },
            nextBatch: nextBatch)
    }
}
