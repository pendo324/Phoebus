import Foundation

/// Reads an Apollo settings backup (`Apollo_Backup_*.zip`) so the real app's
/// export imports directly.
///
/// ## Contents
///
///     preferences.plist   the app's NSUserDefaults domain
///     group.plist         the shared app-group domain
///     keychain.plist      Valet keychain items
///     accounts.txt        newline-separated usernames
///
/// ## Security
///
/// `keychain.plist` holds a live Reddit session cookie, a modhash and the
/// OAuth account blob; `preferences.plist` holds working Imgur, Giphy,
/// ImageChest and Bark API keys. All of it is imported, since it is the
/// user's own backup restored onto their own device and Apollo's own restore
/// replays the same Valet items. The file is untrusted input carrying
/// credentials, so the archive is validated before extraction and a keychain
/// item claiming a service Apollo does not own is rejected outright.
///
/// ## Hand-rolled ZIP reader
///
/// The package has no zip dependency and its tests run on Linux. A backup is
/// a handful of small STORED or DEFLATED entries, so reading the central
/// directory directly is less code than a dependency and keeps the archive
/// validation in one place.
public enum ApolloBackupImport {
    /// The four filenames a backup can contain.
    public static let mainPlistName = "preferences.plist"
    public static let groupPlistName = "group.plist"
    public static let keychainPlistName = "keychain.plist"
    public static let accountsName = "accounts.txt"

    public enum ImportError: Error, Equatable {
        case notAZipArchive
        case unsafeArchive(String)
        case missingPreferences
        case malformedPreferences
    }

    /// Archive validation (Reborn's safety checks):
    ///   - at most 4 entries, every name one of the four known ones;
    ///   - no duplicate names, so a second `preferences.plist` cannot shadow the
    ///     validated first one;
    ///   - regular files only, which also rules out path traversal;
    ///   - a 128 MB total ceiling, against zip bombs.
    public static let allowedNames: Set<String> = [
        mainPlistName, groupPlistName, keychainPlistName, accountsName,
    ]
    public static let maximumTotalBytes = 128 * 1024 * 1024
    public static let maximumEntryCount = 4

    /// The preferences read out of a backup, as raw defaults keys, including the
    /// credentials (Apollo's own restore replays the Valet items so the user is
    /// signed back in).
    ///
    /// Not `Sendable`: a plist decodes to `[String: Any]` of Foundation reference
    /// types. Reading and applying both happen on the main actor.
    public struct Payload {
        public var preferences: [String: Any]
        public var group: [String: Any]
        /// Accounts decoded from `keychain.plist` + `accounts.txt`.
        /// Empty when the backup carried neither.
        public var accounts: [ApolloKeychainImport.ImportedAccount]
        /// This app's own accounts, from a backup Phoebus wrote
        /// (`RebornBackupArchive`).
        public var phoebusAccounts: AccountStorePersisted?

        /// Written by Phoebus rather than Apollo: its preferences are this
        /// app's own keys, restored as they are.
        public var isPhoebusBackup: Bool {
            phoebusAccounts != nil || preferences.keys.contains { $0.hasPrefix("com.pendo324.Phoebus.") || $0.hasPrefix("Phoebus.") }
        }

        public init(preferences: [String: Any],
                    group: [String: Any] = [:],
                    accounts: [ApolloKeychainImport.ImportedAccount] = []) {
            self.preferences = preferences
            self.group = group
            self.accounts = accounts
        }

        /// Both domains, with `preferences.plist` winning a tie. Real
        /// Apollo restores them into two different suites; this app has
        /// one, and the app domain is the authoritative one for the
        /// settings we map.
        public var merged: [String: Any] {
            group.merging(preferences) { _, main in main }
        }
    }

    /// Reads and validates a backup zip.
    public static func read(zipData: Data) throws -> Payload {
        let entries = try ZipReader.entries(in: zipData)
        guard !entries.isEmpty else { throw ImportError.notAZipArchive }
        guard entries.count <= maximumEntryCount else {
            throw ImportError.unsafeArchive("too many entries")
        }
        var seen = Set<String>()
        var total = 0
        for entry in entries {
            guard allowedNames.contains(entry.name) else {
                throw ImportError.unsafeArchive("unexpected file \(entry.name)")
            }
            guard !seen.contains(entry.name) else {
                throw ImportError.unsafeArchive("duplicate \(entry.name)")
            }
            seen.insert(entry.name)
            total += entry.uncompressedSize
            guard total <= maximumTotalBytes else {
                throw ImportError.unsafeArchive("archive too large")
            }
        }
        guard let main = entries.first(where: { $0.name == mainPlistName }) else {
            throw ImportError.missingPreferences
        }
        guard let prefs = try plist(from: try ZipReader.data(for: main, in: zipData)) else {
            throw ImportError.malformedPreferences
        }
        var groupPrefs: [String: Any] = [:]
        // The group domain is OPTIONAL, so a backup without it, or
        // with an unreadable one, still imports the main preferences.
        if let groupEntry = entries.first(where: { $0.name == groupPlistName }),
           let groupData = try? ZipReader.data(for: groupEntry, in: zipData),
           let parsed = (try? plist(from: groupData)) ?? nil {
            groupPrefs = parsed
        }
        // Credentials. Both files are OPTIONAL - a backup taken on a
        // signed-out device has neither - so a failure to read them
        // must not fail the settings import.
        var accounts: [ApolloKeychainImport.ImportedAccount] = []
        if let keychainEntry = entries.first(where: { $0.name == keychainPlistName }),
           let keychainData = try? ZipReader.data(for: keychainEntry, in: zipData) {
            accounts = ApolloKeychainImport.accounts(fromKeychainPlist: keychainData)
        }
        if let accountsEntry = entries.first(where: { $0.name == accountsName }),
           let accountsData = try? ZipReader.data(for: accountsEntry, in: zipData) {
            // The OAuth blob carries no username, so `accounts.txt`
            // supplies it positionally.
            accounts = ApolloKeychainImport.applyingUsernames(
                accounts, from: String(decoding: accountsData, as: UTF8.self))
        }
        var payload = Payload(preferences: prefs, group: groupPrefs, accounts: accounts)
        if let keychainEntry = entries.first(where: { $0.name == keychainPlistName }),
           let keychainData = try? ZipReader.data(for: keychainEntry, in: zipData) {
            payload.phoebusAccounts = RebornBackupArchive.accounts(fromKeychainPlist: keychainData)
        }
        return payload
    }

    static func plist(from data: Data) throws -> [String: Any]? {
        let object = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        return object as? [String: Any]
    }
}
