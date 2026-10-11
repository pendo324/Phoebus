import SwiftUI
import PhoebusCore

/// The one way a view reads and writes a setting.
///
///     @Setting(GeneralSettings.self) private var general
///     @Setting(ReadPostStore.hideReadKey) private var hideRead
///
///     Toggle("…", isOn: $general.showUserProfilePictures)   // writes one field
///     $general.update { $0.postDisplayStyle = .large }       // several at once
///
/// Every view naming the same setting shares one in-memory copy, which
/// is refreshed whenever the setting is saved from anywhere (another
/// screen, a backup restore, an import), so screens can't disagree and
/// a read in a view body costs nothing. Writes change only the fields
/// they name, on the stored value, never a screen's older copy of it.
@MainActor
@propertyWrapper
public struct Setting<Value: Equatable>: DynamicProperty {
    @ObservedObject private var box: SettingBox<Value>

    public init<Source: SettingsSource>(_ source: Source) where Source.Value == Value {
        _box = ObservedObject(wrappedValue: SettingBox.shared(for: source))
    }

    public init(_ model: Value.Type) where Value: StoredSettingsModel {
        self.init(Value.store)
    }

    public var wrappedValue: Value { box.value }

    public var projectedValue: Handle { Handle(box: box) }

    @MainActor
    @dynamicMemberLookup
    public struct Handle {
        fileprivate let box: SettingBox<Value>

        /// The whole value, as a binding.
        public var binding: Binding<Value> {
            Binding(get: { box.value }, set: { newValue in box.update { $0 = newValue } })
        }

        /// Changes several fields in one save.
        public func update(_ change: (inout Value) -> Void) { box.update(change) }

        /// One field, written onto the stored value.
        public subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> Binding<T> {
            box.noteRowField(keyPath)
            return Binding(get: { box.value[keyPath: keyPath] },
                           set: { newValue in box.update { $0[keyPath: keyPath] = newValue } })
        }
    }
}

/// The shared, observable copy of one setting.
@MainActor
public final class SettingBox<Value: Equatable>: ObservableObject {
    @Published public private(set) var value: Value
    private let key: String
    /// A `SettingsStore`, whose fields can be overridden per account.
    private let hasFields: Bool
    /// Key path to stored field name, "" when it has none.
    private var fieldNames: [AnyKeyPath: String] = [:]
    private let load: () -> Value
    private let write: ((inout Value) -> Void) -> Value
    private var observers: [NSObjectProtocol] = []

    private static var registry: [String: AnyObject] { get { SettingBoxRegistry.boxes } set { SettingBoxRegistry.boxes = newValue } }

    static func shared<Source: SettingsSource>(for source: Source) -> SettingBox<Value> where Source.Value == Value {
        if let existing = registry[source.key] as? SettingBox<Value> { return existing }
        let box = SettingBox(key: source.key, hasFields: source is any FieldedSettingsSource,
                             load: { source.load(from: .standard) },
                             write: { change in source.update(in: .standard, change) })
        registry[source.key] = box
        let key = source.key
        box.observers.append(NotificationCenter.default.addObserver(
            forName: .apolloSettingsChanged, object: nil, queue: .main) { [weak box] note in
                guard (note.object as? String) == key else { return }
                MainActor.assumeIsolated { box?.refresh() }
            })
        // A restore can write a key directly, without a save notification.
        box.observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak box] _ in
                MainActor.assumeIsolated { box?.refresh() }
            })
        return box
    }

    private init(key: String, hasFields: Bool,
                 load: @escaping () -> Value, write: @escaping ((inout Value) -> Void) -> Value) {
        self.key = key
        self.hasFields = hasFields
        self.load = load
        self.write = write
        self.value = load()
    }

    func refresh() {
        let fresh = load()
        if fresh != value { value = fresh }
    }

    func update(_ change: (inout Value) -> Void) {
        let saved = write(change)
        if saved != value { value = saved }
    }

    /// "Separate Settings per Account": hands the field a row's binding
    /// writes to the row's `apolloSearchRow`, which marks it when the
    /// account overrides it. Only a flag check while the switch is off.
    func noteRowField<T>(_ keyPath: WritableKeyPath<Value, T>) {
        guard hasFields, AccountSettingsScope.overridingAccount(for: key, in: .standard) != nil else { return }
        let field = fieldNames[keyPath] ?? {
            let found = AccountSettingsOverrides.field(of: keyPath, in: value) ?? ""
            fieldNames[keyPath] = found
            return found
        }()
        guard !field.isEmpty else { return }
        SettingRowFields.note(SettingRowField(key: key, field: field))
    }
}

/// One stored field a settings row edits.
struct SettingRowField: Hashable {
    let key: String
    let field: String
}

/// The fields the bindings built since the last settings row wrote.
/// A row's controls are built just before its `apolloSearchRow`, in the
/// same body, so that modifier takes them; anything left over is dropped
/// at the end of the turn so it can't land on another screen's row.
@MainActor
enum SettingRowFields {
    private static var pending: [SettingRowField] = []

    static func note(_ field: SettingRowField) {
        if pending.isEmpty {
            Task { @MainActor in pending.removeAll() }
        }
        if !pending.contains(field) { pending.append(field) }
    }

    static func take() -> [SettingRowField] {
        defer { pending.removeAll() }
        return pending
    }
}

@MainActor
private enum SettingBoxRegistry {
    static var boxes: [String: AnyObject] = [:]
}
