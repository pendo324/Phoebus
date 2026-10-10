import Foundation

/// "Separate Settings per Account" (Phoebus-only; Apollo and Reborn share
/// one set of settings across accounts). Two layers: the global value
/// under a store's key, and per account a partial override under
/// `<key>@<username>` holding only the fields that account changed, as
/// a JSON dictionary merged over the global JSON at decode time.
///
/// With the switch off nothing here runs beyond one `bool(forKey:)`, so
/// every read and write is exactly the single-layer behaviour.
public enum AccountSettingsScope {
    public static let enabledKey = "com.pendo324.Phoebus.perAccountSettingsEnabled"

    /// The switch itself, which is always global. Flipping it re-reads
    /// every live setting.
    public static let enabledStorage = CustomSettingsSource<Bool>(
        key: enabledKey,
        load: { $0.bool(forKey: enabledKey) },
        save: { value, defaults in
            let theme = selectedThemeID(in: defaults)
            defaults.set(value, forKey: enabledKey)
            refreshAll(in: defaults, themeChanged: selectedThemeID(in: defaults) != theme)
        })

    /// Posted after the account, the switch or the editing layer changed
    /// and every registered setting was re-read.
    public static let didChangeNotification = Notification.Name("com.pendo324.Phoebus.accountSettingsScopeDidChange")

    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// The signed-in account, set by the account manager on launch and
    /// on every switch. Nil when signed out, which reads the globals.
    public static var activeAccount: String? { state.read { $0.account } }

    /// True while Settings is open on the global layer ("Edit Global
    /// Defaults"): reads and writes skip the account's overrides.
    public static var isEditingGlobalDefaults: Bool { state.read { $0.editingGlobal } }

    public static func setActiveAccount(_ username: String?, in defaults: UserDefaults = .standard) {
        let username = username?.lowercased()
        let theme = selectedThemeID(in: defaults)
        let changed = state.write { state -> Bool in
            guard state.account != username else { return false }
            state.account = username
            return true
        }
        if changed, isEnabled(in: defaults) {
            refreshAll(in: defaults, themeChanged: selectedThemeID(in: defaults) != theme)
        }
    }

    public static func setEditingGlobalDefaults(_ editing: Bool, in defaults: UserDefaults = .standard) {
        let theme = selectedThemeID(in: defaults)
        let changed = state.write { state -> Bool in
            guard state.editingGlobal != editing else { return false }
            state.editingGlobal = editing
            return true
        }
        if changed, isEnabled(in: defaults) {
            refreshAll(in: defaults, themeChanged: selectedThemeID(in: defaults) != theme)
        }
    }

    /// The account whose override layer `key` reads and writes right
    /// now, or nil for the global layer.
    public static func overridingAccount(for key: String, in defaults: UserDefaults) -> String? {
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let (account, editingGlobal) = state.read { ($0.account, $0.editingGlobal) }
        guard let account, !editingGlobal, AccountSettingsOverrides.isOverridable(key) else { return nil }
        return account
    }

    /// For a setting stored as one plain value (the selected theme): the
    /// defaults key to read, the account's when it has one.
    public static func readKey(for key: String, in defaults: UserDefaults = .standard) -> String {
        guard let account = overridingAccount(for: key, in: defaults) else { return key }
        let overrideKey = AccountSettingsOverrides.overrideKey(key, account: account)
        return defaults.object(forKey: overrideKey) != nil ? overrideKey : key
    }

    /// The defaults key a plain-value setting writes to.
    public static func writeKey(for key: String, in defaults: UserDefaults = .standard) -> String {
        guard let account = overridingAccount(for: key, in: defaults) else { return key }
        return AccountSettingsOverrides.overrideKey(key, account: account)
    }

    /// Re-reads every store created so far, re-running its write-through
    /// mirror and posting its change notifications, so caches and every
    /// `@Setting` pick up the other layer. The theme is re-announced only
    /// when it changed: re-applying it resets the bar appearance, which
    /// drops the back button from bars already on screen.
    public static func refreshAll(in defaults: UserDefaults = .standard, themeChanged: Bool = true) {
        for refresh in registry.read({ Array($0.values) }) { refresh(defaults) }
        if themeChanged { NotificationCenter.default.post(name: ThemeStore.didChangeNotification, object: nil) }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// The theme ID the app shows now.
    static func selectedThemeID(in defaults: UserDefaults) -> String? {
        defaults.string(forKey: readKey(for: ThemeStore.key, in: defaults))
    }

    /// Re-reads one store, after its override changed outside `save`.
    static func refresh(key: String, in defaults: UserDefaults) {
        registry.read { $0[key] }?(defaults)
    }

    static func register(key: String, refresh: @escaping @Sendable (UserDefaults) -> Void) {
        registry.write { $0[key] = refresh }
    }

    private struct State { var account: String?; var editingGlobal = false }
    private static let state = Locked(State())
    private static let registry = Locked([String: @Sendable (UserDefaults) -> Void]())
}

/// Reading and editing the override layer.
public enum AccountSettingsOverrides {
    /// Stores that stay global whatever the switch says: credentials and
    /// API keys, app lock, device-only state (orientation lock, push
    /// registration), data that is already per account or is user data
    /// rather than a preference, and lists, which have no fields to
    /// override. `DefaultsKey`/`CustomSettingsSource` settings (automatic
    /// backups, app icon, shortcuts, chat filters) are always global too.
    public static let globalOnlyKeys: Set<String> = [
        "Phoebus.appLock",
        "Phoebus.portraitLock",
        "com.pendo324.Phoebus.customAPISettings",
        "com.pendo324.Phoebus.apolloAISettings",
        "com.pendo324.Phoebus.themeGenerationSettings",
        "com.pendo324.Phoebus.translationSettings",
        "com.pendo324.Phoebus.notificationSettings",
        "com.pendo324.Phoebus.notificationBackendSettings",
        "com.pendo324.Phoebus.customSubredditSources",
        "com.pendo324.Phoebus.contentFilters",
        "com.pendo324.Phoebus.matureMediaPreference",
        "com.pendo324.Phoebus.redditBlockedUsers",
        "com.pendo324.Phoebus.savedCategories",
        "com.pendo324.Phoebus.savedCategoryAssignments",
        "com.pendo324.Phoebus.lastViewedFeedDestination",
        "com.pendo324.Phoebus.generatedThemes",
        "com.pendo324.Phoebus.themeVoteArrowsAccent",
        "com.pendo324.Phoebus.postRules",
        "com.pendo324.Phoebus.commentFilters",
        "com.pendo324.Phoebus.userTags",
        "com.pendo324.Phoebus.recentlyVisited",
        "com.pendo324.Phoebus.searchHistory",
        AccountSettingsScope.enabledKey,
    ]

    private static let separator = "@"

    public static func isOverridable(_ key: String) -> Bool {
        !globalOnlyKeys.contains(key) && !key.contains(separator)
    }

    public static func overrideKey(_ key: String, account: String) -> String {
        key + separator + account.lowercased()
    }

    /// The fields `account` overrides in `key`'s store.
    public static func overriddenFields(of key: String, account: String,
                                        in defaults: UserDefaults = .standard) -> Set<String> {
        Set(dictionary(defaults.data(forKey: overrideKey(key, account: account)))?.keys.map { $0 } ?? [])
    }

    /// Drops one field's override ("Use Global Default").
    public static func removeField(_ field: String, of key: String, account: String,
                                   in defaults: UserDefaults = .standard) {
        let overrideKey = overrideKey(key, account: account)
        guard var fields = dictionary(defaults.data(forKey: overrideKey)),
              fields.removeValue(forKey: field) != nil else { return }
        write(fields, to: overrideKey, in: defaults)
        AccountSettingsScope.refresh(key: key, in: defaults)
    }

    /// Every defaults key holding one of `account`'s overrides.
    public static func overrideKeys(for account: String, in defaults: UserDefaults = .standard) -> [String] {
        let suffix = separator + account.lowercased()
        return defaults.dictionaryRepresentation().keys.filter { key in
            guard key.hasSuffix(suffix) else { return false }
            return isOverridable(String(key.dropLast(suffix.count)))
        }.sorted()
    }

    /// "Reset This Account's Overrides": the account follows the globals again.
    public static func removeAll(for account: String, in defaults: UserDefaults = .standard) {
        let theme = AccountSettingsScope.selectedThemeID(in: defaults)
        for key in overrideKeys(for: account, in: defaults) { defaults.removeObject(forKey: key) }
        AccountSettingsScope.refreshAll(in: defaults,
                                        themeChanged: AccountSettingsScope.selectedThemeID(in: defaults) != theme)
    }

    /// "Copy Overrides from…": `destination` ends up with exactly
    /// `source`'s overrides, its own dropped first.
    public static func copy(from source: String, to destination: String,
                            in defaults: UserDefaults = .standard) {
        guard source.lowercased() != destination.lowercased() else { return }
        let theme = AccountSettingsScope.selectedThemeID(in: defaults)
        for key in overrideKeys(for: destination, in: defaults) { defaults.removeObject(forKey: key) }
        let suffix = separator + source.lowercased()
        for key in overrideKeys(for: source, in: defaults) {
            guard let value = defaults.object(forKey: key) else { continue }
            defaults.set(value, forKey: overrideKey(String(key.dropLast(suffix.count)), account: destination))
        }
        AccountSettingsScope.refreshAll(in: defaults,
                                        themeChanged: AccountSettingsScope.selectedThemeID(in: defaults) != theme)
    }

    // MARK: Merge

    /// `override`'s fields laid over `global`; nil when either isn't a
    /// JSON object or the result won't decode.
    static func merge<Value: Codable>(_ override: Data, over global: Value) -> Value? {
        guard var merged = jsonObject(global), let fields = dictionary(override) else { return nil }
        merged.merge(fields) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    /// Writes the fields that differ between `old` and `new` into the
    /// override. False when the value has no fields (not a JSON object).
    @discardableResult
    static func record<Value: Encodable>(from old: Value, to new: Value, key: String, account: String,
                                         in defaults: UserDefaults) -> Bool {
        guard let before = jsonObject(old), let after = jsonObject(new) else { return false }
        let changed = changedFields(from: before, to: after)
        guard !changed.isEmpty else { return true }
        let overrideKey = overrideKey(key, account: account)
        var fields = dictionary(defaults.data(forKey: overrideKey)) ?? [:]
        for field in changed { fields[field] = after[field] }
        write(fields, to: overrideKey, in: defaults)
        return true
    }

    /// Top-level fields whose JSON differs, including ones only one side has.
    public static func changedFields(from old: [String: Any], to new: [String: Any]) -> [String] {
        Set(old.keys).union(new.keys).filter { field in
            canonical(old[field]) != canonical(new[field])
        }.sorted()
    }

    /// The top-level fields of `a` and `b` that encode differently: how
    /// a row finds the field its binding writes.
    public static func changedFields(from old: any Encodable, to new: any Encodable) -> [String] {
        guard let before = jsonObject(old), let after = jsonObject(new) else { return [] }
        return changedFields(from: before, to: after)
    }

    /// The stored field a key path writes, found by changing the value at
    /// the key path and seeing which field encodes differently. Nil for
    /// types with no obvious other value (optionals set to nil, arrays,
    /// enums with payloads) or a path touching several fields.
    public static func field<Root, Value>(of keyPath: WritableKeyPath<Root, Value>, in root: Root) -> String? {
        guard let other = differentValue(from: root[keyPath: keyPath]) else { return nil }
        var probe = root
        probe[keyPath: keyPath] = other
        guard let before = root as? any Encodable, let after = probe as? any Encodable else { return nil }
        let changed = changedFields(from: before, to: after)
        return changed.count == 1 ? changed[0] : nil
    }

    static func differentValue<Value>(from value: Value) -> Value? {
        func otherCase<C: CaseIterable & Equatable>(_ value: C) -> C? { C.allCases.first { $0 != value } }
        switch value {
        case let bool as Bool: return !bool as? Value
        case let int as Int: return (int == .max ? int - 1 : int + 1) as? Value
        case let double as Double: return (double + 1) as? Value
        case let string as String: return (string + "_") as? Value
        case let enumValue as any (CaseIterable & Equatable): return otherCase(enumValue) as? Value
        default: return nil
        }
    }

    static func jsonObject(_ value: any Encodable) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return dictionary(data)
    }

    private static func dictionary(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func canonical(_ value: Any?) -> Data? {
        guard let value else { return nil }
        return try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys])
    }

    private static func write(_ fields: [String: Any], to key: String, in defaults: UserDefaults) {
        if fields.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) {
            defaults.set(data, forKey: key)
        }
    }
}

/// A value behind a lock.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func read<T>(_ body: (Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(value)
    }

    func write<T>(_ body: (inout Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
