import Foundation

/// Automatic Backups (Apollo-Reborn, `AutomaticBackupsEnabled` /
/// `AutomaticBackupIntervalDays`). Opt-in settings ZIPs, default OFF,
/// every 3 days; intervals clamp to 1/3/7 days. `AutomaticBackupDestination`
/// is not implemented (legacy). Checked on foreground, not a background
/// task. Latest 10 automatic backups are kept; manual ones are untouched.
public struct AutomaticBackupSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Only 1, 3 or 7. Use `AutomaticBackupSettings.clamp(_:)`.
    public var intervalDays: Int

    public static let `default` = AutomaticBackupSettings(enabled: false, intervalDays: 3)

    public init(enabled: Bool, intervalDays: Int) {
        self.enabled = enabled
        self.intervalDays = AutomaticBackupSettings.clamp(intervalDays)
    }

    /// Only 1, 3, or 7 are valid; anything else clamps to 3.
    public static func clamp(_ days: Int) -> Int {
        switch days {
        case 1, 3, 7: return days
        default: return 3
        }
    }

    /// The three choices, in order.
    public static let supportedIntervals = [1, 3, 7]

    /// Row detail: "Every Day" for 1, otherwise "Every N Days".
    public static func intervalDescription(_ days: Int) -> String {
        days == 1 ? "Every Day" : "Every \(days) Days"
    }
}

/// Scheduling arithmetic, kept pure so the rules are checkable.
public enum AutomaticBackupSchedule {
    /// Retry interval after a failed attempt.
    public static let retryInterval: TimeInterval = 15 * 60

    /// Clock-skew tolerance: a stored date more than 300s in the future is
    /// disbelieved.
    public static let futureSkewTolerance: TimeInterval = 300

    /// Retention: the latest 10 automatic backups are kept.
    public static let automaticRetentionCount = 10

    /// Next scheduled backup date.
    public static func nextBackupDate(
        enabled: Bool,
        lastBackup: Date?,
        intervalDays: Int,
        now: Date = Date()
    ) -> Date? {
        guard enabled else { return nil }
        // A missing or future-dated last backup means one is due now.
        guard let lastBackup,
              lastBackup.timeIntervalSince(now) <= futureSkewTolerance else { return now }
        return lastBackup.addingTimeInterval(TimeInterval(intervalDays) * 24 * 60 * 60)
    }

    /// Next retry date.
    ///
    /// `nil` unless the last ATTEMPT is newer than the last SUCCESS,
    /// i.e. only while a failure is outstanding.
    public static func nextRetryDate(
        enabled: Bool,
        isBackingUp: Bool,
        suspendedForRestore: Bool,
        lastAttempt: Date?,
        lastBackup: Date?,
        intervalDays: Int,
        now: Date = Date()
    ) -> Date? {
        guard enabled, !isBackingUp, !suspendedForRestore else { return nil }
        guard let lastAttempt,
              lastAttempt.timeIntervalSince(now) <= futureSkewTolerance else { return nil }
        // Retry only while the last attempt is newer than the last success.
        if let lastBackup, lastBackup >= lastAttempt { return nil }
        var retry = lastAttempt.addingTimeInterval(retryInterval)
        // Never retry before the next scheduled backup is due.
        if let due = nextBackupDate(enabled: enabled, lastBackup: lastBackup,
                                    intervalDays: intervalDays, now: now), due > retry {
            retry = due
        }
        return retry.timeIntervalSince(now) > 0 ? retry : nil
    }

    /// Whether a foreground check should run a backup now.
    public static func isDue(
        enabled: Bool,
        lastBackup: Date?,
        intervalDays: Int,
        now: Date = Date()
    ) -> Bool {
        guard let due = nextBackupDate(enabled: enabled, lastBackup: lastBackup,
                                       intervalDays: intervalDays, now: now) else { return false }
        return due <= now
    }

    /// Applies the retention rule to a newest-first list.
    public static func pruned(automaticBackups newestFirst: [String]) -> [String] {
        Array(newestFirst.prefix(automaticRetentionCount))
    }
}

public enum AutomaticBackupSettingsStore {
    /// Reborn's key names.
    private static let enabledKey = "AutomaticBackupsEnabled"
    private static let intervalKey = "AutomaticBackupIntervalDays"

    /// Reborn's two plain keys, so a backup carries them.
    public static let storage = CustomSettingsSource<AutomaticBackupSettings>(
        key: enabledKey,
        load: { defaults in
            AutomaticBackupSettings(enabled: defaults.bool(forKey: enabledKey),
                                    intervalDays: AutomaticBackupSettings.clamp(defaults.object(forKey: intervalKey) as? Int ?? 3))
        },
        save: { settings, defaults in
            defaults.set(settings.enabled, forKey: enabledKey)
            defaults.set(settings.intervalDays, forKey: intervalKey)
        })

    public static func load() -> AutomaticBackupSettings { storage.load() }


    public static func save(_ settings: AutomaticBackupSettings) { storage.save(settings) }

    /// Last SUCCESSFUL backup.
    private static let lastBackupKey = "com.pendo324.Phoebus.automaticBackupLast"
    /// Last ATTEMPT, successful or not - the retry clock keys off this.
    private static let lastAttemptKey = "com.pendo324.Phoebus.automaticBackupLastAttempt"
    private static let lastErrorKey = "com.pendo324.Phoebus.automaticBackupLastError"

    public static var lastBackup: Date? {
        get { UserDefaults.standard.object(forKey: lastBackupKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastBackupKey) }
    }

    public static var lastAttempt: Date? {
        get { UserDefaults.standard.object(forKey: lastAttemptKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastAttemptKey) }
    }

    public static var lastErrorMessage: String? {
        get { UserDefaults.standard.string(forKey: lastErrorKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastErrorKey) }
    }
}
