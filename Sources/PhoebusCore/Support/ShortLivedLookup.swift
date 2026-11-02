import Foundation

/// Answers a repeated lookup (a subreddit's or account's `/about`, the
/// signed-in account's identity) from one request: callers that ask while it
/// runs share it, and a successful answer is reused until it is `maxAge`
/// old. A failure is never kept, so the next caller retries. `maxAge` 0
/// still shares a request that is running and refreshes what is kept, for
/// a caller that needs the answer fresh.
public actor ShortLivedLookup<Value: Sendable> {
    private struct Entry {
        let value: Value
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var running: [String: Task<Value, Error>] = [:]
    private let limit: Int

    public init(limit: Int = 500) {
        self.limit = limit
    }

    public func value(for key: String, maxAge: TimeInterval, now: Date = Date(),
                      fetch: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if maxAge > 0, let entry = entries[key], now.timeIntervalSince(entry.fetchedAt) < maxAge { return entry.value }
        if let task = running[key] { return try await task.value }
        let task = Task { try await fetch() }
        running[key] = task
        do {
            let value = try await task.value
            running[key] = nil
            entries[key] = Entry(value: value, fetchedAt: Date())
            prune(now: now, maxAge: maxAge)
            return value
        } catch {
            running[key] = nil
            throw error
        }
    }

    /// Drops one answer, for a change that makes it stale (subscribing, a
    /// quarantine opt-in).
    public func forget(_ key: String) {
        entries[key] = nil
    }

    public func removeAll() {
        entries.removeAll()
    }

    public var keptCount: Int { entries.count }

    /// Keeps the table from growing for a whole session of scrolling: past
    /// `limit` entries the older half goes.
    private func prune(now: Date, maxAge: TimeInterval) {
        guard entries.count > limit else { return }
        let ordered = entries.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
        for (key, _) in ordered.prefix(entries.count / 2) { entries[key] = nil }
    }
}
