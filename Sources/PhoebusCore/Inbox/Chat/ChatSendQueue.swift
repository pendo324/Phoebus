import Foundation

/// A persistent, ordered outbox for chat messages, following the
/// Matrix Rust SDK's `send_queue` design:
///
/// 1. The transaction id is assigned once, at enqueue, and persisted,
///    so it survives retries and app restarts (replaying it dedupes
///    the event; a fresh id would duplicate the message).
/// 2. A failed send blocks the ones behind it, preventing later
///    messages from arriving out of order.
/// 3. Failure is three-state, not boolean: `sendingFailed` carries
///    whether the error is recoverable.
public actor ChatSendQueue {
    /// One queued message.
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let roomID: String
        public let body: String
        /// Assigned at enqueue, never regenerated. This IS the
        /// idempotency key.
        public let transactionID: String
        public let createdAt: Date
        /// Set once the server has accepted it.
        public var eventID: String?
        public var failureMessage: String?
        /// A parked message: it failed unrecoverably and will not be
        /// retried until the user asks.
        public var isParked: Bool
        /// The account that wrote it (lowercased), so switching accounts
        /// never sends it as someone else. nil when none was recorded.
        public var account: String?

        public init(
            roomID: String,
            body: String,
            account: String? = nil,
            transactionID: String = ChatSendQueue.makeTransactionID(),
            createdAt: Date = Date()
        ) {
            self.id = transactionID
            self.account = account?.lowercased()
            self.roomID = roomID
            self.body = body
            self.transactionID = transactionID
            self.createdAt = createdAt
            self.eventID = nil
            self.failureMessage = nil
            self.isParked = false
        }
    }

    /// Matrix transaction ids are opaque; Reddit's own client uses a Reddit
    /// fullname. A UUID is used here because it needs only to be unique per
    /// message and stable across retries.
    public static func makeTransactionID() -> String {
        "phoebus_" + UUID().uuidString
    }

    private let defaultsKey = "com.pendo324.Phoebus.chatSendQueue"
    private var pending: [Entry] = []
    /// Being sent right now. Drains start from several places (opening
    /// the room, sending, Try Again, pull to refresh); without this two
    /// of them could take the same entry and post it twice.
    private var inFlight: Set<String> = []

    public init() {
        pending = Self.load(key: defaultsKey)
    }

    // MARK: Persistence
    //
    // UserDefaults rather than a database: the outbox is a handful of
    // short strings that must outlive a force-quit.

    private static func load(key: String) -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // MARK: Queue operations

    /// Messages still waiting for a room, oldest first.
    public func pendingEntries(roomID: String, account: String? = nil) -> [Entry] {
        pending.filter { $0.roomID == roomID && Self.belongs($0, to: account) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func belongs(_ entry: Entry, to account: String?) -> Bool {
        guard let account, let owner = entry.account else { return true }
        return owner == account.lowercased()
    }

    @discardableResult
    public func enqueue(roomID: String, body: String, account: String? = nil) -> Entry {
        let entry = Entry(roomID: roomID, body: body, account: account)
        pending.append(entry)
        persist()
        return entry
    }

    /// Drops a message without sending it (the Rust SDK's
    /// `SendHandle.abort`).
    public func abort(id: String) {
        pending.removeAll { $0.id == id }
        persist()
    }

    /// Un-parks a message so the queue will try it again
    /// (`SendHandle.tryResend`).
    public func retry(id: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].isParked = false
        pending[index].failureMessage = nil
        persist()
    }

    /// The next message to attempt for a room, or `nil` when empty or
    /// blocked by a parked oldest message.
    public func nextToSend(roomID: String, account: String? = nil) -> Entry? {
        guard let first = pendingEntries(roomID: roomID, account: account).first else { return nil }
        return first.isParked ? nil : first
    }

    /// The next message to send, taken for this drain: nil while another
    /// drain is already sending the room's oldest message, so a message
    /// goes out once and in order. `markSent`/`markFailed` give it back.
    public func claimNext(roomID: String, account: String? = nil) -> Entry? {
        guard let next = nextToSend(roomID: roomID, account: account), !inFlight.contains(next.id) else { return nil }
        inFlight.insert(next.id)
        return next
    }

    /// Records a success and removes the message from the outbox.
    public func markSent(id: String, eventID: String) {
        inFlight.remove(id)
        pending.removeAll { $0.id == id }
        persist()
    }

    /// Records a failure. A recoverable failure leaves the message
    /// queued and retryable; an unrecoverable one parks it, blocking
    /// everything behind it until the user aborts or retries.
    public func markFailed(id: String, message: String, isRecoverable: Bool) {
        inFlight.remove(id)
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].failureMessage = message
        pending[index].isParked = !isRecoverable
        persist()
    }

    /// Clears everything. Test support.
    public func removeAll() {
        pending.removeAll()
        persist()
    }
}
