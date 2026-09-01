import Foundation

/// The one way a setting is stored: a Codable value as JSON under a
/// `UserDefaults` key. Every settings model goes through one of these,
/// so reading, writing, caching and change notification work the same
/// everywhere.
///
/// - Reads are memoized by the stored bytes, so calling `load()` from a
///   view body costs a defaults read and a compare, not a decode. Any
///   write to the key, including a backup restore that bypasses `save`,
///   changes the bytes and misses.
/// - Writes from the UI go through `update`, which changes the STORED
///   value, never a screen's older copy of it.
/// - Every save posts `.apolloSettingsChanged` with the key as its
///   object, which the UI's `@Setting` observes; a store may also name a
///   notification of its own for older observers.
public struct SettingsStore<Value: Codable>: Sendable {
    public let key: String
    private let fallback: @Sendable () -> Value
    /// Posted after a save, in addition to `.apolloSettingsChanged`.
    public let didChange: Notification.Name?
    /// Runs once per freshly decoded value: returns true when it changed
    /// the value and the change should be saved (a one-shot migration).
    private let migrate: (@Sendable (inout Value, UserDefaults) -> Bool)?
    /// Runs after a value is decoded or saved (write-through mirrors).
    private let mirror: (@Sendable (Value, UserDefaults) -> Void)?
    private let memo = DecodeMemo()

    public init(key: String, didChange: Notification.Name? = nil,
                migrate: (@Sendable (inout Value, UserDefaults) -> Bool)? = nil,
                mirror: (@Sendable (Value, UserDefaults) -> Void)? = nil,
                default fallback: @escaping @Sendable () -> Value) {
        self.key = key
        self.didChange = didChange
        self.migrate = migrate
        self.mirror = mirror
        self.fallback = fallback
    }

    /// The stored value, or the default when missing or undecodable.
    public func load(from defaults: UserDefaults = .standard) -> Value {
        loadIfPresent(from: defaults) ?? fallback()
    }

    public var defaultValue: Value { fallback() }

    /// The stored value only if one decodes; nil otherwise.
    public func loadIfPresent(from defaults: UserDefaults = .standard) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if let hit = memo.value(for: data) as? Value { return hit }
        guard var value = try? JSONDecoder().decode(Value.self, from: data) else { return nil }
        if let migrate, migrate(&value, defaults) {
            save(value, to: defaults)
            return value
        }
        memo.store(value, for: data)
        mirror?(value, defaults)
        return value
    }

    /// Replaces the whole stored value. For restores and imports; a
    /// screen changing a setting uses `update`.
    public func save(_ value: Value, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        memo.store(value, for: data)
        mirror?(value, defaults)
        NotificationCenter.default.post(name: .apolloSettingsChanged, object: key)
        if let didChange { NotificationCenter.default.post(name: didChange, object: nil) }
    }

    public func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        NotificationCenter.default.post(name: .apolloSettingsChanged, object: key)
        if let didChange { NotificationCenter.default.post(name: didChange, object: nil) }
    }
}

/// Anything a setting can be read from and written to: a
/// `SettingsStore` (a Codable model as JSON) or a `DefaultsKey` (one
/// plain value under a stock Apollo key). The UI's `@Setting` works with
/// either.
public protocol SettingsSource: Sendable {
    associatedtype Value
    var key: String { get }
    func load(from defaults: UserDefaults) -> Value
    func save(_ value: Value, to defaults: UserDefaults)
}

extension SettingsStore: SettingsSource {}

public extension SettingsSource {
    /// Read-modify-write of the stored value.
    @discardableResult
    func update(in defaults: UserDefaults = .standard, _ change: (inout Value) -> Void) -> Value {
        var value = load(from: defaults)
        change(&value)
        save(value, to: defaults)
        return value
    }
}

/// One plain value (Bool, Int, Double, String, a string array) under
/// its own key, for settings that keep stock Apollo's or Reborn's key so
/// a backup imports them. Same notifications as `SettingsStore`.
public struct DefaultsKey<Value: Sendable>: SettingsSource {
    public let key: String
    private let fallback: @Sendable () -> Value

    public init(_ key: String, default fallback: @autoclosure @escaping @Sendable () -> Value) {
        self.key = key
        self.fallback = fallback
    }

    public func load(from defaults: UserDefaults = .standard) -> Value {
        defaults.object(forKey: key) as? Value ?? fallback()
    }

    public func save(_ value: Value, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .apolloSettingsChanged, object: key)
    }

    public var value: Value {
        get { load() }
        nonmutating set { save(newValue) }
    }
}

/// A setting whose value spans several plain keys, or needs checking as
/// it's read (a clamp, a catalog). Same notifications as the others.
public struct CustomSettingsSource<Value: Sendable>: SettingsSource {
    public let key: String
    private let read: @Sendable (UserDefaults) -> Value
    private let write: @Sendable (Value, UserDefaults) -> Void

    public init(key: String, load: @escaping @Sendable (UserDefaults) -> Value,
                save: @escaping @Sendable (Value, UserDefaults) -> Void) {
        self.key = key
        self.read = load
        self.write = save
    }

    public func load(from defaults: UserDefaults = .standard) -> Value { read(defaults) }

    public func save(_ value: Value, to defaults: UserDefaults = .standard) {
        write(value, defaults)
        NotificationCenter.default.post(name: .apolloSettingsChanged, object: key)
    }
}

public extension Notification.Name {
    /// A setting was saved; `object` is its store's key.
    static let apolloSettingsChanged = Notification.Name("ApolloSettingsChanged")
}

/// A settings model with one app-wide store, so screens can name the
/// type: `@Setting(GeneralSettings.self)`.
public protocol StoredSettingsModel: Codable, Equatable, Sendable {
    static var store: SettingsStore<Self> { get }
}

/// The last decoded value and the bytes it came from.
private final class DecodeMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var value: Any?

    func value(for data: Data) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return self.data == data ? value : nil
    }

    func store(_ value: Any, for data: Data) {
        lock.lock(); defer { lock.unlock() }
        self.data = data
        self.value = value
    }
}

extension KeyedDecodingContainer {
    /// Decodes `key`, falling back to the same field of `defaults` when the
    /// key is missing OR unreadable (a wrong type, or an enum case this build
    /// doesn't know, e.g. after a downgrade or a newer backup), so one bad
    /// field can't reset the whole struct.
    public func decode<Root, Value: Decodable>(_ key: Key, default defaults: Root,
                                                 _ path: KeyPath<Root, Value>) throws -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? defaults[keyPath: path]
    }
}
