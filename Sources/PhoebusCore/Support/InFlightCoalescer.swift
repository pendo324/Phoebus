import Foundation

/// Runs one piece of work per key at a time: callers that ask for a key
/// while its work is running wait for that result instead of starting
/// their own. A screen of rows showing one flair emoji or default avatar
/// then costs one request, not one per row.
///
/// The work runs in its own task, so a caller that is cancelled (its row
/// scrolled away) stops waiting but does not cancel what the others wait
/// for. Nothing is kept once the work ends, success or failure, so a
/// failed run is retried by the next caller.
public actor InFlightCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private var running: [Key: Task<Value, Error>] = [:]

    public init() {}

    public func value(for key: Key, work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let task = running[key] { return try await task.value }
        let task = Task<Value, Error> {
            do {
                let result = try await work()
                self.finish(key)
                return result
            } catch {
                self.finish(key)
                throw error
            }
        }
        running[key] = task
        return try await task.value
    }

    private func finish(_ key: Key) {
        running[key] = nil
    }

    /// Keys whose work is running. Test-facing.
    public var runningCount: Int { running.count }
}
