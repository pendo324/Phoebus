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
            Binding(get: { box.value[keyPath: keyPath] },
                    set: { newValue in box.update { $0[keyPath: keyPath] = newValue } })
        }
    }
}

/// The shared, observable copy of one setting.
@MainActor
public final class SettingBox<Value: Equatable>: ObservableObject {
    @Published public private(set) var value: Value
    private let load: () -> Value
    private let write: ((inout Value) -> Void) -> Value
    private var observers: [NSObjectProtocol] = []

    private static var registry: [String: AnyObject] { get { SettingBoxRegistry.boxes } set { SettingBoxRegistry.boxes = newValue } }

    static func shared<Source: SettingsSource>(for source: Source) -> SettingBox<Value> where Source.Value == Value {
        if let existing = registry[source.key] as? SettingBox<Value> { return existing }
        let box = SettingBox(load: { source.load(from: .standard) },
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

    private init(load: @escaping () -> Value, write: @escaping ((inout Value) -> Void) -> Value) {
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
}

@MainActor
private enum SettingBoxRegistry {
    static var boxes: [String: AnyObject] = [:]
}
