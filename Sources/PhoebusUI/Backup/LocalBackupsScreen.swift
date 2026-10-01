import SwiftUI
import PhoebusCore

/// Reborn's "Manage Backups": the archives Automatic Backups keeps on the device,
/// split Automatic / Manual, newest first. Tapping one shows Restore, Export and
/// Delete.
struct LocalBackupsScreen: View {
    @State private var backups: [URL] = []
    @State private var showingManual = false
    @State private var expanded: String?
    @State private var restoreTarget: URL?
    @State private var deleteTarget: URL?
    @State private var resultMessage: (title: String, message: String)?

    private var filtered: [URL] {
        backups.filter { (AutomaticBackupArchive.kind(of: $0) == .manual) == showingManual }
    }

    private var automaticCount: Int { backups.filter { AutomaticBackupArchive.kind(of: $0) == .automatic }.count }

    var body: some View {
        List {
            Section {
                Picker("Backup Type", selection: $showingManual) {
                    Text("Automatic · \(automaticCount)").tag(false)
                    Text("Manual · \(backups.count - automaticCount)").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            }
            Section {
                if filtered.isEmpty {
                    Text(showingManual ? "No Manual Backups Yet" : "No Automatic Backups Yet")
                        .foregroundStyle(.secondary)
                        .apolloPlainSettingsRowInsets(rule: false)
                }
                ForEach(filtered, id: \.lastPathComponent) { url in
                    Button {
                        withAnimation { expanded = expanded == url.lastPathComponent ? nil : url.lastPathComponent }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dateText(url))
                                Text(detailText(url))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: expanded == url.lastPathComponent ? "chevron.up" : "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .apolloPlainSettingsRowInsets()
                    if expanded == url.lastPathComponent {
                        HStack {
                            Button("Restore") { restoreTarget = url }
                                .foregroundStyle(Color.apolloAccent)
                                .frame(maxWidth: .infinity)
                            ShareLink(item: url) { Text("Export") }
                                .foregroundStyle(Color.apolloAccent)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Export to Files")
                            Button("Delete") { deleteTarget = url }
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .apolloPlainSettingsRowInsets()
                    }
                }
            } footer: {
                Text((showingManual ? "Manual backups stay until you delete them." : "Keeps the newest 10 automatic backups.")
                     + "\n\nExport a backup to Files before deleting Phoebus or installing it with a different app identifier.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Manage Backups")
        .onAppear(perform: reload)
        .onChange(of: showingManual) { _, _ in expanded = nil }
        .alert("Confirm Restore", isPresented: $restoreTarget.isPresent(), presenting: restoreTarget) { url in
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) { restore(url) }
        } message: { url in
            Text("\(url.lastPathComponent)\n\nThis will replace all existing settings and logged-in accounts with the backup. This cannot be undone.")
        }
        .alert("Delete Backup?", isPresented: $deleteTarget.isPresent(), presenting: deleteTarget) { url in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do { try AutomaticBackupArchive.delete(url) } catch {
                    resultMessage = ("Delete Failed", error.localizedDescription)
                }
                reload()
            }
        } message: { url in
            Text(url.lastPathComponent)
        }
        .alert(resultMessage?.title ?? "", isPresented: Binding(get: { resultMessage != nil },
                                                                set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage?.message ?? "")
        }
    }

    private func reload() {
        backups = (try? AutomaticBackupArchive.localBackupURLs()) ?? []
        if let expanded, !backups.contains(where: { $0.lastPathComponent == expanded }) { self.expanded = nil }
    }

    /// Restored settings and accounts apply without a relaunch.
    private func restore(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            // `.apollobackup` archives, or legacy JSON ones.
            if data.starts(with: [0x50, 0x4B]) {
                let payload = try ApolloBackupImport.read(zipData: data)
                guard payload.isPhoebusBackup else { throw CocoaError(.fileReadCorruptFile) }
                SettingsDomainSnapshot.restore(payload)
            } else {
                try BackupBundle.decode(from: data).restore()
            }
            resultMessage = ("Restore Complete", "Settings successfully restored.")
        } catch {
            resultMessage = ("Restore Failed", "Could not restore backup.")
        }
    }

    private func dateText(_ url: URL) -> String {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return "Date Unavailable"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    private func detailText(_ url: URL) -> String {
        let kind = AutomaticBackupArchive.kind(of: url) == .manual ? "Manual" : "Automatic"
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return kind }
        return "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
    }
}
