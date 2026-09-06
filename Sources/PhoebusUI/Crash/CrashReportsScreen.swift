import SwiftUI
import PhoebusCore

/// The "Crash Reports" push from the hub's Privacy section (Reborn):
/// the "Store Crash Reports Locally" switch, then the pending reports,
/// newest first.
public struct CrashReportsScreen: View {
    @AppStorage(CrashCaptureSettings.enabledKey) private var captureEnabled = true
    @State private var reportIDs: [Int64] = []
    @State private var unreadableID: Int64?

    public init() {}

    public var body: some View {
        List {
            Section {
                Toggle(isOn: $captureEnabled) {
                    HStack(spacing: 12) {
                        SettingsTile(systemImage: "bandage", tint: .orange)
                        Text("Store Crash Reports Locally")
                    }
                }
                .apolloSettingsRowInsets()
            } footer: {
                Text("Saves a technical report on this device if Phoebus unexpectedly closes. Reports are never sent automatically — you can review, share, or delete each one here. Changing this takes effect the next time Phoebus launches.")
                    .apolloSectionFooter()
            }
            Section {
                if reportIDs.isEmpty {
                    Text("No crash reports on this device")
                        .foregroundStyle(.secondary)
                        .apolloSettingsRowInsets()
                }
                ForEach(reportIDs, id: \.self) { id in
                    if let report = CrashManager.shared.report(id: id) {
                        NavigationLink {
                            CrashReviewScreen(report: report)
                        } label: {
                            CrashReportRow(report: report)
                        }
                    } else {
                        Button { unreadableID = id } label: {
                            Text("Unreadable crash report")
                        }
                    }
                }
            } header: {
                Text("Pending Crash Reports")
                    .apolloSectionHeader()
            } footer: {
                if !reportIDs.isEmpty {
                    Text("Tap a report to review exactly what it contains, share it, or delete it.")
                        .apolloSectionFooter()
                }
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Crash Reports")
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .phoebusCrashReportsChanged)) { _ in reload() }
        .alert("Couldn't Read Report", isPresented: $unreadableID.isPresent()) {
            Button("Delete Report", role: .destructive) {
                if let unreadableID { CrashManager.shared.delete(id: unreadableID) }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The local crash report could not be read.")
        }
    }

    private func reload() {
        reportIDs = CrashManager.shared.pendingReportIDs.reversed()
    }
}

/// Date, then the exception name or crash category.
struct CrashReportRow: View {
    let report: PendingCrashReport

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(report.crashDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Crash report")
            Text(report.exceptionName ?? (report.category == "user" ? "Test report (no crash)" : report.category))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Reborn's crash review: what the report holds and never holds, the
/// exact technical report, export and delete. Sharing is by export.
struct CrashReviewScreen: View {
    let report: PendingCrashReport
    /// Set when shown as the relaunch prompt's sheet.
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryTitle).font(.headline)
                    Text(summaryBody).font(.subheadline).foregroundStyle(.secondary)
                }
            } footer: {
                Text("This report was saved on your device when Phoebus unexpectedly closed. It has not been sent anywhere.")
                    .apolloSectionFooter()
            }
            Section {
                Text("• Crash type and stack trace\n• Phoebus version and build\n• iOS version and device model\n• Loaded software module filenames and UUIDs\n• Recent coarse actions, such as “opened post” or “started video”")
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: {
                Text("Included in the report").apolloSectionHeader()
            }
            Section {
                Text("• Reddit account or username\n• Names of communities\n• Post or comment contents, titles, or IDs\n• Search terms and browsing URLs\n• API keys, tokens, or cookies\n• A persistent installation identifier")
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: {
                Text("Never included").apolloSectionHeader()
            } footer: {
                Text("The technical report is built from an allowlist: only the fields above are copied from the crash data.")
                    .apolloSectionFooter()
            }
            Section {
                NavigationLink("View Technical Report") { TechnicalReportScreen(json: report.jsonString) }
                Button("Export Sanitized Report…") { exportReport() }
                    .foregroundStyle(Color.apolloAccent)
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete Report").frame(maxWidth: .infinity)
                }
                .foregroundStyle(.red)
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Review Crash Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onClose != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                }
            }
        }
        .sheet(item: $exportURL) { url in
            ActivityShareSheet(items: [url])
        }
        .alert("Delete Crash Report?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                CrashManager.shared.delete(id: report.id)
                close()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The report only exists on this device. This can't be undone.")
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var summaryTitle: String {
        [
            "nsexception": "App Exception",
            "mach": "Invalid Memory Access",
            "signal": "Fatal Signal",
            "cpp_exception": "C++ Exception",
            "memory_termination": "Likely Memory Termination",
            "deadlock": "Main Thread Deadlock",
            "user": "Reported Problem",
        ][report.category] ?? "Crash"
    }

    private var summaryBody: String {
        var lines: [String] = []
        if let date = report.crashDate { lines.append(date.formatted(date: .abbreviated, time: .shortened)) }
        if let name = report.exceptionName { lines.append(name) }
        if let environment = report.sanitized["environment"] as? [String: Any] {
            lines.append("Phoebus \(environment["phoebus_version"] as? String ?? "?") (\(environment["phoebus_build"] as? String ?? "?"))")
        }
        if report.category == "memory_termination" {
            lines.append("This report contains recent memory and application-state information, but may not contain a crash stack trace.")
        }
        return lines.joined(separator: "\n")
    }

    private func exportReport() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("phoebus-crash-\(report.id).json")
        do {
            try report.jsonString.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {}
    }
}

/// The exact sanitized JSON, byte for byte what an export holds. A
/// read-only monospaced `UITextView`, as Reborn's: a SwiftUI `Text` of a
/// report this long draws nothing.
struct TechnicalReportScreen: View {
    let json: String

    var body: some View {
        MonospacedTextView(text: json)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Technical Report")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MonospacedTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.alwaysBounceVertical = true
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.backgroundColor = .systemBackground
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}
