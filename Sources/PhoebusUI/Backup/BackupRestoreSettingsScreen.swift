import SwiftUI
import UniformTypeIdentifiers
import PhoebusCore

/// Every file type the restore pickers accept.
///
/// Reborn writes backups as `Apollo_Backup_<date>.apollobackup`: still a ZIP
/// inside, but declared as its own type `app.apolloreborn.backup`, so `.json`
/// and `.zip` alone would grey them out in Files.
///
/// `.data` is a fallback: a `.apollobackup` on a device without Reborn has no
/// declared type, and the importer chooses ZIP vs JSON by content, not name.
public enum BackupFileTypes {
    public static let apolloRebornBackup = UTType(importedAs: "app.apolloreborn.backup", conformingTo: .zip)
    public static var restorable: [UTType] {
        [.json, .zip, apolloRebornBackup]
            + (UTType(filenameExtension: "apollobackup").map { [$0] } ?? [])
            + [.data]
    }
}

/// Reborn's "Backup & Restore" settings screen: export the current settings
/// and accounts as an `.apollobackup` (`RebornBackupArchive`), or import one, a
/// real Apollo backup, or an older Phoebus JSON export.
public struct BackupRestoreSettingsScreen: View {
    @State private var isImporting = false
    /// The archive being handed to Files.
    @State private var exportURL: URL?
    @State private var statusMessage: String?
    @State private var showingRestoreConfirmation = false
    @State private var pendingImportBundle: BackupBundle?
    @State private var pendingApolloPayload: ApolloBackupImport.Payload?

    /// A backup picked elsewhere (the hub's "Cloud Backup" path) to
    /// import as soon as this screen appears.
    private let importURL: URL?

    /// Hides Export, for the sign-in screen where there is nothing yet
    /// to export.
    private let importOnly: Bool

    public init(importURL: URL? = nil, importOnly: Bool = false) {
        self.importURL = importURL
        self.importOnly = importOnly
    }

    public var body: some View {
        List {
            if !importOnly {
            Section {
                Button("Export Settings…") { exportSettings() }
                .apolloSearchRow("Export Settings…", lastBeforeFooter: true)
            } footer: {
                // Covers every setting; the credential sentence mirrors Reborn's
                // post-export warning.
                Text("Saves all of your settings to an Apollo_Backup_….apollobackup file, Apollo Reborn's backup format, including your signed-in accounts. It contains your logged-in account credentials. Keep it private.")
                    .apolloSectionFooter()
            }
            }
            Section {
                Button("Import Settings…") {
                    isImporting = true
                }
                .apolloSearchRow("Import Settings…", lastBeforeFooter: true)
            } footer: {
                // Backups carry accounts, so a restore replaces the signed-in session.
                Text("Overwrites your current settings with those from a previously exported file, including your signed-in accounts. You can also import a real Apollo backup (Apollo_Backup_….apollobackup or .zip): its settings, API keys and signed-in accounts are all restored.")
                    .apolloSectionFooter()
            }
            if let statusMessage {
                Section {
                    // Same 32pt text inset as the rows above.
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .apolloPlainSettingsRowInsets()
                        .accessibilityIdentifier("backupRestore.statusMessage")
                }
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Backup & Restore")
        #if canImport(UIKit)
        .sheet(item: $exportURL, onDismiss: removeExport) { url in
            BackupExportPicker(url: url) { exported in
                statusMessage = exported ? "Exported \(url.lastPathComponent)." : nil
                exportURL = nil
            }
            .ignoresSafeArea()
        }
        #endif
        // `.zip` as well as `.json`: a real Apollo backup (`Apollo_Backup_*.zip`)
        // imports directly. See `ApolloBackupImport`.
        .apolloDocumentImporter(isPresented: $isImporting, allowedContentTypes: BackupFileTypes.restorable) { result in
            handleImportPick(result)
        }
        .onAppear {
            if let importURL { handleImportPick(.success(importURL)) }
        }
        .alert("Restore Settings?", isPresented: Binding(get: { pendingApolloPayload != nil },
                                                          set: { if !$0 { pendingApolloPayload = nil } })) {
            Button("Restore", role: .destructive) {
                if let payload = pendingApolloPayload { applyApolloBackup(payload) }
                pendingApolloPayload = nil
            }
            Button("Cancel", role: .cancel) { pendingApolloPayload = nil }
        } message: {
            Text("This overwrites your current settings and signs in the backup's accounts. This can't be undone.")
        }
        .alert("Restore Settings?", isPresented: $showingRestoreConfirmation, presenting: pendingImportBundle) { bundle in
            Button("Restore", role: .destructive) {
                bundle.restore()
                statusMessage = "Settings restored."
                pendingImportBundle = nil
            }
            Button("Cancel", role: .cancel) { pendingImportBundle = nil }
        } message: { _ in
            Text("This overwrites your current settings. This can't be undone.")
        }
    }

    /// Writes the archive to a temporary file under Reborn's name, then
    /// hands it to Files, which keeps the name and extension.
    private func exportSettings() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(RebornBackupArchive.filename())
            try RebornBackupArchive.make().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            exportURL = url
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// The temporary copy carries credentials, so it doesn't linger.
    private func removeExport() {
        let directory = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where url.pathExtension == RebornBackupArchive.fileExtension {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func applyApolloBackup(_ payload: ApolloBackupImport.Payload) {
        // One of ours: its keys are this app's own, restored as they are.
        if payload.isPhoebusBackup {
            let count = SettingsDomainSnapshot.restore(payload)
            let accounts = payload.phoebusAccounts?.accounts.count ?? 0
            statusMessage = "Restored \(count) settings"
                + (accounts == 0 ? "." : accounts == 1 ? " and 1 account." : " and \(accounts) accounts.")
            return
        }
        let summary = ApolloSettingsMigration.apply(payload)
        // Accounts too: this signs the user back in, which is the point of
        // restoring a backup.
        let restoredAccounts = ApolloSettingsMigration.applyAccounts(payload)
        if restoredAccounts > 0 {
            NotificationCenter.default.post(name: .apolloAccountsRestored, object: nil)
        }
        // Reports what it actually took rather than claiming blanket success: most
        // of a real backup's keys have no equivalent here.
        var parts: [String] = []
        if !summary.isEmpty {
            parts.append("Imported \(summary.applied.count) settings: "
                + summary.applied.joined(separator: ", "))
        }
        if restoredAccounts > 0 {
            parts.append(restoredAccounts == 1
                ? "Restored 1 account."
                : "Restored \(restoredAccounts) accounts.")
        }
        statusMessage = parts.isEmpty
            ? "That Apollo backup had nothing this app can use yet."
            : parts.joined(separator: " ")
    }

    private func handleImportPick(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                // A real Apollo backup is a ZIP; ours is JSON. Chosen by content (the zip's
                // `PK\u{03}\u{04}` magic) rather than extension, because a file picked from
                // Files can arrive with either extension or none.
                if data.count >= 4, data[data.startIndex] == 0x50,
                   data[data.startIndex + 1] == 0x4B {
                    // Asks first, as the JSON path does.
                    pendingApolloPayload = try ApolloBackupImport.read(zipData: data)
                } else {
                    let bundle = try BackupBundle.decode(from: data)
                    pendingImportBundle = bundle
                    showingRestoreConfirmation = true
                }
            } catch {
                statusMessage = "Couldn't read that file — it may not be a valid Phoebus or Apollo backup."
            }
        case .failure(let error):
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
