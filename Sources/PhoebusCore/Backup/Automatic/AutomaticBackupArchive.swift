import Foundation

/// Writes and prunes local settings archives for Automatic Backups
/// (`backUpNow`, `localBackupURLs` newest first, `deleteLocalBackup`).
///
/// Archives are Reborn's `.apollobackup` (`RebornBackupArchive`), named
/// `Apollo_<Auto|Manual>_Backup_<day>_<NNN>.apollobackup` with the number
/// counting up within the day. JSON archives are still listed and restore.
///
/// Storage is Documents/`Phoebus Backups`, as Reborn uses
/// `Documents/Apollo Reborn Backups`. Run state stays in Application Support
/// (see `AutomaticBackupSettingsStore`) so restoring settings cannot transfer
/// device-local state.
public enum AutomaticBackupArchive {
    /// Naming shape: a timestamp so the newest sorts last lexically.
    static let legacyFilenamePrefix = "phoebus-settings-"
    static let legacyExtension = "json"

    /// `automatic` archives are subject to the 10-item retention;
    /// `manual` ones "remain until you delete them".
    public enum Kind: String, Sendable {
        case automatic
        case manual
    }

    /// Directory name; Reborn uses `Documents/Apollo Reborn Backups`.
    public static let directoryName = "Phoebus Backups"

    /// Archives live in Documents (Files-app visible with `UIFileSharingEnabled`).
    public static func directory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let directory = documents.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func filename(kind: Kind, date: Date, existing: [String]) -> String {
        let day = RebornBackupArchive.stamp(date, "yyyy-MM-dd")
        let sequences = existing.compactMap { name -> Int? in
            guard name.hasPrefix("Apollo_"), name.contains("_Backup_\(day)_") else { return nil }
            return Int((name as NSString).deletingPathExtension.split(separator: "_").last ?? "")
        }
        let next = (sequences.max() ?? 0) + 1
        let label = kind == .automatic ? "Auto" : "Manual"
        return "Apollo_\(label)_Backup_\(day)_\(String(format: "%03d", next)).\(RebornBackupArchive.fileExtension)"
    }

    /// Which kind an existing archive is, read back from its name.
    public static func kind(of url: URL) -> Kind {
        let name = url.lastPathComponent
        return name.hasPrefix("Apollo_Manual_") || name.contains("-\(Kind.manual.rawValue)-") ? .manual : .automatic
    }

    /// Newest first.
    public static func localBackupURLs() throws -> [URL] {
        let directory = try directory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return urls
            .filter { $0.pathExtension == RebornBackupArchive.fileExtension
                || ($0.pathExtension == legacyExtension && $0.lastPathComponent.hasPrefix(legacyFilenamePrefix)) }
            .sorted { modified($0) > modified($1) }
    }

    public static func write(kind: Kind, date: Date = Date()) throws -> URL {
        let directory = try directory()
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let url = directory.appendingPathComponent(filename(kind: kind, date: date, existing: existing))
        try RebornBackupArchive.make().write(to: url, options: .atomic)
        if kind == .automatic { try pruneAutomatic() }
        return url
    }

    public static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// "The latest 10 automatic backups are kept; manual backups
    /// remain until you delete them."
    static func pruneAutomatic() throws {
        let automatic = try localBackupURLs().filter { kind(of: $0) == .automatic }
        guard automatic.count > AutomaticBackupSchedule.automaticRetentionCount else { return }
        for url in automatic.dropFirst(AutomaticBackupSchedule.automaticRetentionCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
