import Foundation

/// A whole-domain snapshot of the app's persisted settings.
///
/// Apollo-Reborn's backup is domain-based rather than feature-based: it
/// zips the whole main defaults domain and the app-group domain
/// (theme settings, keyword filters, some account state) wholesale.
/// Snapshotting the domain avoids a hand-maintained feature list
/// rotting as settings are added.
///
/// Keys are filtered to this app's own namespaces:
///   - `com.pendo324.Phoebus.*` and `Phoebus.*`
///   - bare real-Reborn key names adopted for future defaults import
///     (`FollowedUsersOrder`, `ChatMessagesFilter`,
///     `AutomaticBackupsEnabled`, ...)
public enum SettingsDomainSnapshot {
    /// Prefixes owned by this app.
    static let ownedPrefixes = [
        "com.pendo324.Phoebus.",
        "Phoebus.",
    ]

    /// Bare keys we use under their real Reborn names. Listed
    /// explicitly because they carry no prefix to match on, so the
    /// filter would otherwise drop them - the same reason Reborn keeps
    /// a second `group.plist` rather than one domain.
    static let ownedBareKeys: Set<String> = [
        "FollowedUsersOrder",
        "ChatMessagesFilter",
        "ChatMessagesUnreadOnly",
        "AutomaticBackupsEnabled",
        "AutomaticBackupIntervalDays",
        "ApolloSiriContentEnabled",
        "PhoebusLiquidGlassEnabled",
        "CustomAIHeaders",
    ]

    /// Explicit deny-list: high-churn view state, not preferences.
    /// Restoring a stale read-set would mark posts read the user
    /// hasn't actually seen on this device.
    static let excludedKeys: Set<String> = [
        // Which posts have been read, and which comments were seen.
        "com.pendo324.Phoebus.readPostIDs",
        "com.pendo324.Phoebus.seenCommentIDs",
        // The Recently Read list itself is browsing history, not a
        // setting; its SETTINGS (recentlyReadSettings) are kept.
        "com.pendo324.Phoebus.recentlyReadPosts",
        // Where the user happened to be last, restoring which would
        // yank a different device to an unrelated feed.
        "com.pendo324.Phoebus.lastViewedFeedDestination",
        // Automatic-backup run state: folder permission, install
        // identity and last-run state must not transfer between devices.
        "com.pendo324.Phoebus.automaticBackupLast",
        "com.pendo324.Phoebus.automaticBackupLastAttempt",
        "com.pendo324.Phoebus.automaticBackupLastError",
    ]

    /// Whether a defaults key belongs in a backup.
    public static func isBackedUp(_ key: String) -> Bool {
        guard !excludedKeys.contains(key) else { return false }
        if ownedBareKeys.contains(key) { return true }
        return ownedPrefixes.contains { key.hasPrefix($0) }
    }

    /// Captures every backed-up key. Values are held as `JSONValue` so
    /// the snapshot survives a JSON round trip (`UserDefaults` stores
    /// `Data`/`Date`/arrays/dictionaries, none JSON-native).
    public static func capture(from defaults: UserDefaults = .standard) -> [String: JSONValue] {
        var snapshot: [String: JSONValue] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where isBackedUp(key) {
            guard let encoded = JSONValue(propertyListValue: value) else { continue }
            snapshot[key] = encoded
        }
        return snapshot
    }

    /// Restores a Phoebus `.apollobackup`'s preferences and accounts.
    /// Returns how many settings it wrote.
    @discardableResult
    public static func restore(_ payload: ApolloBackupImport.Payload,
                               into defaults: UserDefaults = .standard) -> Int {
        var count = 0
        for (key, value) in payload.preferences where isBackedUp(key) {
            defaults.set(value, forKey: key)
            count += 1
        }
        CustomAPISettingsStore.applyPersisted()
        if let accounts = payload.phoebusAccounts {
            AccountKeychainStoreBox().save(accounts)
            NotificationCenter.default.post(name: .apolloAccountsRestored, object: nil)
        }
        return count
    }

    /// Writes a snapshot back. Additive: a key absent from the
    /// snapshot is left alone rather than deleted, so restoring an
    /// older backup cannot wipe newer settings.
    public static func restore(_ snapshot: [String: JSONValue],
                               into defaults: UserDefaults = .standard) {
        for (key, value) in snapshot {
            guard isBackedUp(key) else { continue }
            guard let plist = value.propertyListValue else { continue }
            defaults.set(plist, forKey: key)
        }
    }
}

public extension JSONValue {
    /// Bridges a `UserDefaults` value into `JSONValue`. `Data` and
    /// `Date` have no JSON representation, so both are tagged and
    /// base64/ISO-encoded rather than dropped.
    init?(propertyListValue value: Any) {
        // Checked before the switch: `as Bool` also matches an integer 0/1
        // NSNumber, which would capture every such setting as a boolean.
        if ApolloSettingsMigration.isBoolean(value), let flag = value as? Bool {
            self = .bool(flag)
            return
        }
        switch value {
        case let value as String:
            self = .string(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as Data:
            self = .object([
                SettingsDomainSnapshot.typeTagKey: .string("data"),
                SettingsDomainSnapshot.typeValueKey: .string(value.base64EncodedString()),
            ])
        case let value as Date:
            self = .object([
                SettingsDomainSnapshot.typeTagKey: .string("date"),
                SettingsDomainSnapshot.typeValueKey: .number(value.timeIntervalSince1970),
            ])
        case let value as [Any]:
            let mapped = value.compactMap { JSONValue(propertyListValue: $0) }
            // A partially-decodable array would silently reorder or
            // drop entries, so take it whole or not at all.
            guard mapped.count == value.count else { return nil }
            self = .array(mapped)
        case let value as [String: Any]:
            var mapped: [String: JSONValue] = [:]
            for (key, element) in value {
                guard let encoded = JSONValue(propertyListValue: element) else { return nil }
                mapped[key] = encoded
            }
            self = .object(mapped)
        default:
            return nil
        }
    }

    /// The inverse.
    var propertyListValue: Any? {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value
        case .number(let value):
            // A whole number round-trips as Int so a restored Int
            // setting does not come back as 3.0.
            if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
                return Int(value)
            }
            return value
        case .array(let values):
            return values.compactMap { $0.propertyListValue }
        case .object(let values):
            if case .string(let tag)? = values[SettingsDomainSnapshot.typeTagKey],
               let payload = values[SettingsDomainSnapshot.typeValueKey] {
                switch tag {
                case "data":
                    if case .string(let base64) = payload {
                        return Data(base64Encoded: base64)
                    }
                case "date":
                    if case .number(let seconds) = payload {
                        return Date(timeIntervalSince1970: seconds)
                    }
                default:
                    break
                }
            }
            var mapped: [String: Any] = [:]
            for (key, value) in values {
                guard let plist = value.propertyListValue else { continue }
                mapped[key] = plist
            }
            return mapped
        case .null:
            return nil
        }
    }
}

extension SettingsDomainSnapshot {
    /// Marker keys for the tagged `Data`/`Date` encodings above.
    /// Prefixed so they cannot collide with a real dictionary key.
    static let typeTagKey = "__apolloType"
    static let typeValueKey = "__apolloValue"
}
