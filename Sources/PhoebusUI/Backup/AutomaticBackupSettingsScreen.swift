import SwiftUI
import PhoebusCore

/// Reborn's Automatic Backups (PR #1060): an Automatic Backups switch, Back Up
/// Now, a "Backup Schedule" section holding Backup Interval, a "Backup
/// Activity" section holding Last Backup, Next Backup and a failure row, then
/// Manage Backups.
///
/// Visibility rules: the schedule/activity sections show only while backups are
/// enabled (`automaticVisible`); the failure row only when there is an error;
/// the configuration rows are disabled while a backup runs (`canConfigure`).
///
/// Next Backup shows "Backing Up…" while running, a "Retry: …" prefix when a
/// failure is in backoff, otherwise the next scheduled date.
@MainActor
public struct AutomaticBackupSettingsScreen: View {
    @Setting(AutomaticBackupSettingsStore.storage) private var settings
    @State private var isBackingUp = false
    @State private var lastBackup = AutomaticBackupSettingsStore.lastBackup
    @State private var lastError = AutomaticBackupSettingsStore.lastErrorMessage
    @State private var archives: [URL] = []
    @State private var now = Date()
    /// Post-export warning, shown after every manual export because the archive
    /// carries a signed-in session.
    @State private var showingCredentialWarning = false
    /// The manual backup just written, offered to Files.
    @State private var exportURL: URL?
    @State private var exportResult: (title: String, message: String)?
    @State private var exportedName: String?

    public init() {}

    private var nextBackupText: String {
        if isBackingUp { return "Backing Up…" }
        if let retry = AutomaticBackupSchedule.nextRetryDate(
            enabled: settings.enabled, isBackingUp: isBackingUp,
            suspendedForRestore: false,
            lastAttempt: AutomaticBackupSettingsStore.lastAttempt,
            lastBackup: lastBackup, intervalDays: settings.intervalDays, now: now) {
            return "Retry: " + Self.describe(retry)
        }
        guard let next = AutomaticBackupSchedule.nextBackupDate(
            enabled: settings.enabled, lastBackup: lastBackup,
            intervalDays: settings.intervalDays, now: now) else { return "Never" }
        return Self.describe(next)
    }

    static func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public var body: some View {
        List {
            Section {
                Toggle("Automatic Backups", isOn: Binding(
                    get: { settings.enabled },
                    set: { newValue in
                        $settings.enabled.wrappedValue = newValue
                        // Turning it on schedules a check straight away.
                        if newValue { AutomaticBackupRunner.runIfDue(); reloadArchives() }
                    }
                ))
                .disabled(isBackingUp)
                .apolloSearchRow("Automatic Backups")
                .accessibilityIdentifier("automatic.enabled")

                Button("Back Up Now") { backUpNow() }
                    .disabled(isBackingUp)
                    .apolloSearchRow("Back Up Now", lastBeforeFooter: true)
                    .accessibilityIdentifier("automatic.backupNow")
            } footer: {
                Text("Saves your settings on a schedule while Phoebus is open.")
                    .apolloSectionFooter()
            }

            if settings.enabled {
                Section {
                    ApolloSettingsPicker("Backup Interval", selection: Binding(
                        get: { settings.intervalDays },
                        set: { newValue in
                            $settings.intervalDays.wrappedValue = AutomaticBackupSettings.clamp(newValue)
                        }
                    ),
                                         options: AutomaticBackupSettings.supportedIntervals,
                                         display: { AutomaticBackupSettings.intervalDescription($0) })
                    .disabled(isBackingUp)
                    .apolloSearchRow("Backup Interval", lastBeforeFooter: true)
                    .accessibilityIdentifier("automatic.interval")
                } header: {
                    Text("Backup Schedule")
                        .apolloSectionHeader()
                } footer: {
                    // Reborn's footer.
                    Text("Automatic backups are stored inside Phoebus. The latest 10 automatic backups are kept; manual backups remain until you delete them.")
                    .apolloSectionFooter()
                }

                Section {
                    LabeledContent("Last Backup",
                                   value: lastBackup.map(Self.describe) ?? "Never")
                        .apolloSearchRow("Last Backup")
                    LabeledContent("Next Backup", value: nextBackupText)
                        .apolloSearchRow("Next Backup")
                    if let lastError, !lastError.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Backup Failed")
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("automatic.error")
                    }
                } header: {
                    Text("Backup Activity")
                        .apolloSectionHeader()
                }
            }

            // Reborn's "Manage Backups" row, with the count, pushing the
            // archive list (restore, export, delete).
            Section {
                SettingsLink {
                    LocalBackupsScreen()
                } label: {
                    HStack {
                        Text("Manage Backups")
                        Spacer()
                        if !archives.isEmpty {
                            Text("\(archives.count)").foregroundStyle(.secondary)
                        }
                    }
                }
                .apolloPlainSettingsRowInsets(rule: false)
                .accessibilityIdentifier("automatic.manage")
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Automatic Backups")
        #if canImport(UIKit)
        // A swipe-down dismissal reports nothing, so it reads as Cancel.
        .sheet(item: $exportURL, onDismiss: {
            if exportResult == nil, let name = exportedName {
                exportResult = ("Backup Saved Locally", "\(name) remains in Manage Backups. Export it before deleting Phoebus.")
            }
            exportedName = nil
        }) { url in
            BackupExportPicker(url: url) { exported in
                exportURL = nil
                exportResult = exported
                    ? ("Backup Complete", "\(url.lastPathComponent) was saved locally and exported to Files. It contains your logged-in account credentials. Keep it private.")
                    : ("Backup Saved Locally", "\(url.lastPathComponent) remains in Manage Backups. Export it before deleting Phoebus.")
            }
            .ignoresSafeArea()
        }
        #endif
        .alert(exportResult?.title ?? "", isPresented: Binding(get: { exportResult != nil },
                                                               set: { if !$0 { exportResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportResult?.message ?? "")
        }
        .alert("Backup Complete", isPresented: $showingCredentialWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            // Second sentence of Reborn's alert.
            Text("Your backup was saved. It contains your logged-in account credentials. Keep it private.")
        }
        .onAppear {
            now = Date()
            reloadArchives()
        }
    }

    private func reloadArchives() {
        archives = (try? AutomaticBackupArchive.localBackupURLs()) ?? []
    }

    private func backUpNow() {
        isBackingUp = true
        // A manual run, so it is exempt from the 10-archive retention.
        let result = AutomaticBackupRunner.run(kind: .manual)
        isBackingUp = false
        lastBackup = AutomaticBackupSettingsStore.lastBackup
        lastError = AutomaticBackupSettingsStore.lastErrorMessage
        now = Date()
        reloadArchives()
        guard result else { return }
        // Then straight to Files, as Reborn's Back Up Now.
        if let newest = archives.first(where: { AutomaticBackupArchive.kind(of: $0) == .manual }) {
            exportResult = nil
            exportedName = newest.lastPathComponent
            exportURL = newest
        } else {
            showingCredentialWarning = true
        }
    }
}

/// Performs a backup and records the state the rows read.
public enum AutomaticBackupRunner {
    nonisolated(unsafe) private static var observers: [NSObjectProtocol] = []
    nonisolated(unsafe) private static var timer: Timer?

    /// Reborn re-checks whenever the app becomes active, on a significant
    /// time change, and on a timer while it stays open.
    @MainActor
    public static func startActiveChecks() {
        guard observers.isEmpty else { return }
        #if canImport(UIKit)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                runIfDue()
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                    MainActor.assumeIsolated { runIfDue() }
                }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { timer?.invalidate(); timer = nil }
        })
        observers.append(center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { runIfDue() }
        })
        #endif
    }

    @discardableResult
    public static func run(kind: AutomaticBackupArchive.Kind) -> Bool {
        // The attempt is recorded whether or not it succeeds: the retry clock keys
        // off `localLastAttempt` and only counts while it is newer than the last
        // success.
        AutomaticBackupSettingsStore.lastAttempt = Date()
        do {
            _ = try AutomaticBackupArchive.write(kind: kind)
            AutomaticBackupSettingsStore.lastBackup = Date()
            AutomaticBackupSettingsStore.lastErrorMessage = nil
            return true
        } catch {
            AutomaticBackupSettingsStore.lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// The foreground check: scheduling runs while the app is active, not as a
    /// background task.
    public static func runIfDue(now: Date = Date()) {
        let settings = AutomaticBackupSettingsStore.load()
        guard settings.enabled else { return }
        // A failure in backoff must not be retried early.
        if let retry = AutomaticBackupSchedule.nextRetryDate(
            enabled: settings.enabled, isBackingUp: false, suspendedForRestore: false,
            lastAttempt: AutomaticBackupSettingsStore.lastAttempt,
            lastBackup: AutomaticBackupSettingsStore.lastBackup,
            intervalDays: settings.intervalDays, now: now), retry > now {
            return
        }
        guard AutomaticBackupSchedule.isDue(
            enabled: settings.enabled,
            lastBackup: AutomaticBackupSettingsStore.lastBackup,
            intervalDays: settings.intervalDays, now: now) else { return }
        run(kind: .automatic)
    }
}

#if canImport(UIKit)
/// Files' export picker for one backup, copied (the local archive stays).
struct BackupExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (_ exported: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(false) }
    }
}
#endif
