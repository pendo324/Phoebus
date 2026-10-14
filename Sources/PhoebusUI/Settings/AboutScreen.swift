import SwiftUI
import PhoebusCore

/// The app's own About page: name, tagline, version, and credit to the
/// two projects it follows, including that Reborn's features are ported
/// from Reborn's own code. No outbound links.
public struct AboutScreen: View {
    public init() {}

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
                }
            }

            Section {
                creditRow("Apollo Reborn", "The community project that keeps Apollo running. Phoebus's Apollo Reborn features are ported directly from its GPL-3.0 code, the work of the Apollo Reborn team and contributors, as are its Liquid Glass icons. Their names are in the app's CREDITS.md.")
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
        .navigationTitle("About")
        .navigationBarTitleDisplayModeIfAvailable()
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
