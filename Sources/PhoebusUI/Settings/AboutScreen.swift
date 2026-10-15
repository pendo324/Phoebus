import SwiftUI
import PhoebusCore

/// The About screen: the app's own identity, updates, support (the Feature
/// Requests, Bug Reports, Crash Reports, Export Debug Logs, GitHub and
/// Version rows), and credits. No outbound links except the two GitHub rows.
public struct AboutScreen: View {
    let accountManager: AccountManager
    @Setting(AppUpdatePolicy.automaticChecks) private var automaticUpdateChecks
    @State private var debugLogExport: URL?
    @State private var exportingLogs = false
    /// Re-read on appear and whenever a report is added or deleted.
    @State private var crashReportCount = 0

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    public var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("Phoebus")
                        .font(.title.weight(.bold))
                    Text("Radiant Reddit Browsing")
                        .foregroundStyle(.secondary)
                    Text(versionText)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            // Reborn "In-App Update Prompt" (#1343).
            Section {
                CheckForUpdatesRow()
                    .apolloSearchRow("Check for Updates")
                if BuildChannel.current != nil {
                    UpdateInstallerRow()
                        .apolloSearchRow("Update Installer") // search: requires releaseChannel
                    // Reborn "In-App Update Prompt".
                    Toggle("Automatic Update Checks", isOn: $automaticUpdateChecks.binding)
                        .accessibilityIdentifier("settings.automaticUpdateChecks")
                        .apolloSearchRow("Automatic Update Checks", lastBeforeFooter: true) // search: requires releaseChannel
                }
            } header: {
                Text("Updates")
                    .apolloSectionHeader()
            } footer: {
                if BuildChannel.current != nil {
                    Text("Update checks read Phoebus's AltStore source from GitHub once a day, and GitHub only sees your IP address.")
                        .apolloSectionFooter()
                }
            }

            Section {
                SettingsCategoryLinkRow(
                    title: "Feature Requests",
                    subtitle: "Suggest ideas for Phoebus",
                    emoji: "💡",
                    tint: .yellow,
                    url: "https://github.com/pendo324/Phoebus/issues"
                )
                // A push to the in-app report form, not a link.
                SettingsNavigationRow {
                    SettingsDrillDownLeaf(destination: .bugReports)
                } label: {
                    HStack {
                        SettingsCategoryEmojiRow(
                            title: SettingsDrillDownDestination.bugReports.title,
                            subtitle: "Report a problem on GitHub",
                            emoji: "🐛",
                            tint: .red)
                        Spacer()
                    }
                }
                .apolloSettingsRowInsets()
                SettingsNavigationRow {
                    SettingsDrillDownLeaf(destination: .crashReports)
                } label: {
                    SettingsCategoryRow(
                        title: SettingsDrillDownDestination.crashReports.title,
                        subtitle: "Reports kept on this device",
                        systemImage: "bandage",
                        tint: .orange,
                        detail: crashReportCount > 0 ? "\(crashReportCount)" : nil)
                }
                .apolloSettingsRowInsets()
                exportLogsRow
                // The GitHub row draws the SF Symbol mark on its tile.
                SettingsCategoryLinkRow(
                    title: "Open Source on GitHub",
                    subtitle: "@pendo324",
                    emoji: "🐙",
                    tint: .black,
                    url: "https://github.com/pendo324/Phoebus",
                    artwork: .symbol("chevron.left.forwardslash.chevron.right")
                )
                // A plain value row: no tile, title at the row's leading edge, "v3.7.1"-style
                // detail trailing.
                HStack {
                    Text("Version")
                        .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                    Spacer()
                    Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                        .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                        .foregroundStyle(Color.apolloSettingsSecondary)
                }
                .apolloPlainSettingsRowInsets(rule: false)
            } header: {
                Text("Support")
                    .apolloSectionHeader()
            } footer: {
                Text("Request features, report bugs, or browse the source. Phoebus is free and open source.")
                    .apolloSectionFooter()
            }

            Section {
                creditRow("Apollo Reborn", "The community project that keeps Apollo running. Phoebus's Apollo Reborn features are ported directly from its GPL-3.0 code, the work of the Apollo Reborn team and contributors. Their names are in the app's CREDITS.md.")
                creditRow("Apollo", "The original Reddit app by Christian Selig, whose design and behaviour Phoebus recreates.")
            } header: {
                Text("Credits")
                    .apolloSectionHeader()
            } footer: {
                Text("The rest of Phoebus is written from scratch and contains none of Apollo's code.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .apolloSettingsSearchScroll()
        .navigationTitle(SettingsCategory.about.title)
        .navigationBarTitleDisplayModeIfAvailable()
        .onAppear {
            crashReportCount = CrashManager.shared.pendingReportIDs.count
        }
        .onReceive(NotificationCenter.default.publisher(for: .phoebusCrashReportsChanged)) { _ in
            crashReportCount = CrashManager.shared.pendingReportIDs.count
        }
    }

    /// Writes a plain-text log and hands it to the share sheet. It only opens the
    /// share sheet, so it runs on the tap without asking.
    private var exportLogsRow: some View {
        Button {
            Task { await writeDebugLog() }
        } label: {
            SettingsCategoryRow(
                title: SettingsAction.exportLogs.title,
                subtitle: exportingLogs ? "Preparing the log…" : "Share a diagnostic log",
                systemImage: "square.and.arrow.up.on.square.fill",
                tint: .indigo,
                isAction: true)
        }
        .buttonStyle(.plain)
        .apolloSettingsRowInsets()
        .accessibilityIdentifier("settings.exportLogs")
        .modifier(SettingsSearchRowModifier(title: "Export Debug Logs"))
        .sheet(isPresented: $debugLogExport.isPresent()) {
            if let debugLogExport {
                ActivityShareSheet(items: [debugLogExport])
            }
        }
    }

    private func writeDebugLog() async {
        guard !exportingLogs else { return }
        exportingLogs = true
        defer { exportingLogs = false }
        debugLogExport = await DebugLogExport.write(accountCount: accountManager.accounts.count)
    }

    private func creditRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .apolloPlainSettingsRowInsets()
    }
}
