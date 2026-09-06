import Foundation
import PhoebusCore
#if canImport(KSCrashRecording)
import KSCrashRecording
#endif

/// One pending local crash report, already sanitized. The raw KSCrash
/// dictionary never leaves `CrashManager`.
struct PendingCrashReport: Identifiable {
    let id: Int64
    let sanitized: [String: Any]

    var crashDate: Date? { CrashReportSanitizer.crashDate(sanitized) }
    var category: String { CrashReportSanitizer.category(sanitized) }
    var exceptionName: String? { CrashReportSanitizer.exceptionName(sanitized) }
    var jsonString: String { CrashReportSanitizer.jsonString(sanitized) }
    var summary: String { CrashReportSanitizer.textSummary(sanitized) }
}

/// Reborn's local crash recorder: KSCrash's recording layer only,
/// installed at launch unless "Store Crash Reports Locally" is off, with the
/// same privacy-locked configuration. Reports stay on the device until the
/// user shares or deletes them.
final class CrashManager: @unchecked Sendable {
    static let shared = CrashManager()

    private(set) var isInstalled = false
    private let lock = NSLock()
    #if canImport(KSCrashRecording)
    private var standaloneStore: CrashReportStore?
    #endif

    /// Library/Caches: diagnostic and disposable; not backed up.
    private var storagePath: String {
        let caches = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        return (caches as NSString).appendingPathComponent("Phoebus/LocalCrashReports")
    }

    private var baseUserInfo: [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "diagnostic_schema": 1,
            "version": info["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info["CFBundleVersion"] as? String ?? "unknown",
        ]
    }

    #if canImport(KSCrashRecording)
    private func storeConfiguration() -> CrashReportStoreConfiguration {
        let configuration = CrashReportStoreConfiguration()
        configuration.reportsPath = (storagePath as NSString).appendingPathComponent(CrashReportStore.defaultInstallSubfolder)
        configuration.appName = "Phoebus"
        configuration.maxReportCount = 3
        configuration.reportCleanupPolicy = .never
        return configuration
    }
    #endif

    /// Must run first thing at launch; KSCrash can't be reconfigured later.
    func installIfEnabled() {
        #if canImport(KSCrashRecording)
        guard CrashCaptureSettings.isEnabled() else { return }
        let configuration = KSCrashConfiguration()
        configuration.installPath = storagePath
        configuration.reportStoreConfiguration = storeConfiguration()
        configuration.monitors = [.machException, .signal, .cppException, .nsException,
                                  .userReported, .system, .applicationState, .memoryTermination]
        // Never record memory near registers or the stack (user content),
        // queue names, console output; no deadlock watchdog or SIGTERM.
        configuration.enableMemoryIntrospection = false
        configuration.enableQueueNameSearch = false
        configuration.addConsoleLogToReport = false
        configuration.printPreviousLogOnStartup = false
        configuration.deadlockWatchdogInterval = 0
        configuration.enableSigTermMonitoring = false
        configuration.enableSwapCxaThrow = false
        configuration.userInfoJSON = ["phoebus": baseUserInfo]
        do {
            try KSCrash.shared.install(with: configuration)
            isInstalled = true
            try? FileManager.default.createDirectory(
                atPath: storagePath, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        } catch {
            isInstalled = false
        }
        #endif
    }

    #if canImport(KSCrashRecording)
    /// The installed recorder's store, or a reader of the same folder so
    /// turning capture off never hides reports already saved.
    private var store: CrashReportStore? {
        if isInstalled, let store = KSCrash.shared.reportStore { return store }
        lock.lock(); defer { lock.unlock() }
        if standaloneStore == nil {
            standaloneStore = try? CrashReportStore(configuration: storeConfiguration())
        }
        return standaloneStore
    }
    #endif

    var pendingReportIDs: [Int64] {
        #if canImport(KSCrashRecording)
        return (store?.reportIDs ?? []).map(\.int64Value)
        #else
        return []
        #endif
    }

    var crashedLastLaunch: Bool {
        #if canImport(KSCrashRecording)
        return isInstalled && KSCrash.shared.crashedLastLaunch
        #else
        return false
        #endif
    }

    func report(id: Int64) -> PendingCrashReport? {
        #if canImport(KSCrashRecording)
        guard let raw = store?.report(for: id)?.value,
              let sanitized = CrashReportSanitizer.sanitized(raw) else { return nil }
        return PendingCrashReport(id: id, sanitized: sanitized)
        #else
        return nil
        #endif
    }

    func delete(id: Int64) {
        #if canImport(KSCrashRecording)
        store?.deleteReport(with: id)
        #endif
        NotificationCenter.default.post(name: .phoebusCrashReportsChanged, object: nil)
    }

    /// Re-publishes the userInfo KSCrash writes into a report: build
    /// metadata plus the recent coarse actions.
    func publishUserInfo(recentActions: [[String: Any]]) {
        #if canImport(KSCrashRecording)
        guard isInstalled else { return }
        var info = baseUserInfo
        info["recent_actions"] = recentActions
        KSCrash.shared.userInfo = ["phoebus": info]
        #endif
    }
}

extension Notification.Name {
    static let phoebusCrashReportsChanged = Notification.Name("phoebusCrashReportsChanged")
}

/// The app's entry point into local crash recording: install KSCrash, start
/// the recent-actions context, and arm the relaunch prompt.
public enum CrashRecorder {
    @MainActor
    public static func start() {
        CrashManager.shared.installIfEnabled()
        CrashContext.start()
        #if canImport(UIKit)
        CrashPromptCoordinator.shared.start()
        #endif
    }

    /// Notes a coarse action for the next crash report.
    public static func record(_ event: CrashContextEvent) {
        CrashContext.record(event)
    }
}
