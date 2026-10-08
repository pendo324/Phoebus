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

            Section {
                creditRow("Apollo Reborn", "The community project that keeps Apollo running. Phoebus's Apollo Reborn features are ported directly from its GPL-3.0 code, the work of the Apollo Reborn team and contributors, as are its Liquid Glass icons.")
                SettingsNavigationRow {
                    ThanksToScreen()
                } label: {
                    HStack {
                        Text("Apollo Reborn Contributors")
                        Spacer()
                        ApolloSettingsChevron()
                    }
                }
                .apolloPlainSettingsRowInsets()
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

/// "Thanks To": Apollo Reborn's contributors, grouped as Reborn credits
/// them (`RebornContributors`), with "Loading contributors…" /
/// "Couldn't load contributors" states.
struct ThanksToScreen: View {
    @State private var groups: [RebornContributors.Group]?
    @State private var failed = false

    var body: some View {
        List {
            if let groups {
                ForEach(groups, id: \.title) { group in
                    Section {
                        // Dynamic rows use the same 32/32 geometry as static ones; these
                        // sections have no footer, so every row keeps its rule.
                        ForEach(group.names, id: \.self) {
                            Text($0).apolloPlainSettingsRowInsets()
                        }
                    } header: {
                        Text(group.title)
                            .apolloSectionHeader()
                    }
                }
            } else {
                Section {
                    Text(failed ? "Couldn't load contributors" : "Loading contributors…")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Contributors")
                        .apolloSectionHeader()
                }
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Thanks To")
        .navigationBarTitleDisplayModeIfAvailable()
        .task {
            guard groups == nil else { return }
            if let (data, _) = try? await URLSession.shared.data(from: RebornContributors.sourceURL),
               let parsed = RebornContributors.parse(data) {
                groups = parsed
            } else {
                failed = true
            }
        }
    }
}
