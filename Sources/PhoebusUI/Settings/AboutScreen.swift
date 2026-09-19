import SwiftUI
import PhoebusCore

/// The app's own About page: name, tagline, version, and credit to the
/// two projects it follows. No outbound links.
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
                creditRow("Apollo", "The original Reddit app by Christian Selig, whose design and behaviour Phoebus follows.")
                creditRow("Apollo Reborn", "The community project that keeps Apollo running, and the source of many of the features here.")
            } header: {
                Text("Credits")
                    .apolloSectionHeader()
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

/// "Thanks To": contributor sections loaded from GitHub, with "Loading
/// contributors…" / "Couldn't load contributors" states.
struct ThanksToScreen: View {
    @State private var contributors: [String]?
    @State private var failed = false

    var body: some View {
        List {
            Section {
                if let contributors {
                    // Dynamic rows use the same 32/32 geometry as static ones; this section has
                    // no footer, so every row keeps its rule.
                    ForEach(contributors, id: \.self) {
                        Text($0).apolloPlainSettingsRowInsets()
                    }
                } else if failed {
                    Text("Couldn't load contributors").foregroundStyle(.secondary)
                } else {
                    Text("Loading contributors…").foregroundStyle(.secondary)
                }
            } header: {
                Text("Contributors")
                    .apolloSectionHeader()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Thanks To")
        .navigationBarTitleDisplayModeIfAvailable()
        .task {
            guard contributors == nil else { return }
            do {
                let url = URL(string: "https://api.github.com/repos/Apollo-Reborn/Apollo-Reborn/contributors?per_page=100")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let list = try JSONDecoder().decode([Contributor].self, from: data)
                contributors = list.map(\.login)
            } catch {
                failed = true
            }
        }
    }

    private struct Contributor: Decodable { let login: String }
}
