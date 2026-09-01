import Foundation

/// A small thread-safe dictionary for static caches that are read and
/// written from concurrent tasks.
public final class LockedCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Key: Value] = [:]

    public init() {}

    public subscript(key: Key) -> Value? {
        get { lock.withLock { storage[key] } }
        set { lock.withLock { storage[key] = newValue } }
    }

    public func removeAll() {
        lock.withLock { storage.removeAll() }
    }
}
