import Foundation

/// Writes settings backups in Apollo-Reborn's archive format
/// (`Apollo_Backup_<date>.apollobackup`): a ZIP of `preferences.plist`,
/// `keychain.plist` and `accounts.txt`, the files Reborn's exporter writes.
///
/// - `preferences.plist`: every backed-up key of this app's defaults
///   domain (`SettingsDomainSnapshot`), as Reborn snapshots its own
///   persistent domain.
/// - `keychain.plist`: one item under this app's own service holding the
///   signed-in accounts. Reborn skips keychain items it doesn't own, so
///   the archive still passes its checks.
/// - `accounts.txt`: the usernames, one per line.
///
/// `ApolloBackupImport.read` reads it back; `isPhoebusBackup` tells it
/// apart from a real Apollo backup.
public enum RebornBackupArchive {
    public static let fileExtension = "apollobackup"
    public static let accountsService = "com.pendo324.Phoebus.accounts"
    public static let accountsAccount = "accounts"

    /// Reborn's manual-export name: `Apollo_Backup_yyyy-MM-dd_HHmmss`.
    public static func filename(date: Date = Date()) -> String {
        "Apollo_Backup_\(stamp(date, "yyyy-MM-dd_HHmmss")).\(fileExtension)"
    }

    public static func stamp(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// The archive's bytes for the current settings (and accounts).
    public static func make(defaults: UserDefaults = .standard,
                            accounts: AccountStorePersisted? = AccountKeychainStoreBox().load()) throws -> Data {
        var preferences: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where SettingsDomainSnapshot.isBackedUp(key) {
            // Only what a plist can hold; anything else would fail the write.
            if PropertyListSerialization.propertyList(value, isValidFor: .xml) { preferences[key] = value }
        }
        var entries: [(String, Data)] = [
            (ApolloBackupImport.mainPlistName,
             try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)),
        ]
        var items: [[String: Any]] = []
        if let accounts, !accounts.accounts.isEmpty {
            items.append(["service": accountsService, "account": accountsAccount,
                          "data": try JSONEncoder().encode(accounts)])
            entries.append((ApolloBackupImport.accountsName,
                            Data(accounts.accounts.map(\.username).joined(separator: "\n").utf8)))
        }
        // Always written, as Reborn does, even when empty.
        entries.append((ApolloBackupImport.keychainPlistName,
                        try PropertyListSerialization.data(fromPropertyList: items, format: .xml, options: 0)))
        return ZipWriter.archive(entries)
    }

    /// This app's accounts, if `keychain.plist` carries them.
    static func accounts(fromKeychainPlist data: Data) -> AccountStorePersisted? {
        guard let items = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
                as? [[String: Any]] else { return nil }
        for item in items where item["service"] as? String == accountsService
            && item["account"] as? String == accountsAccount {
            guard let blob = item["data"] as? Data else { continue }
            return try? JSONDecoder().decode(AccountStorePersisted.self, from: blob)
        }
        return nil
    }
}

/// A ZIP of STORED (uncompressed) entries: settings backups are a few
/// small files, so compression isn't worth a dependency.
public enum ZipWriter {
    public static func archive(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, data) in entries {
            let nameBytes = Data(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            // Local file header.
            out.append(le32(0x0403_4B50)); out.append(le16(20)); out.append(le16(0x0800)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0x21))
            out.append(le32(crc)); out.append(le32(UInt32(data.count))); out.append(le32(UInt32(data.count)))
            out.append(le16(UInt16(nameBytes.count))); out.append(le16(0))
            out.append(nameBytes); out.append(data)
            // Central directory entry; regular file, mode 0644.
            central.append(le32(0x0201_4B50)); central.append(le16(0x031E)); central.append(le16(20))
            central.append(le16(0x0800)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc)); central.append(le32(UInt32(data.count))); central.append(le32(UInt32(data.count)))
            central.append(le16(UInt16(nameBytes.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0o100644 << 16))
            central.append(le32(offset)); central.append(nameBytes)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4B50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset)); out.append(le16(0))
        return out
    }

    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
