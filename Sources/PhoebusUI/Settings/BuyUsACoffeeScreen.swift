import SwiftUI
import PhoebusCore

/// Reborn's "Buy Us a Coffee" screen, the first row on the root Settings
/// screen in its own section. Lists contributors who opted into a Buy Me a
/// Coffee link, fetched from the same live JSON URL Reborn uses.
public struct BuyUsACoffeeScreen: View {
    @State private var entries: [ApolloContributor] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        List {
            if isLoading {
                HStack {
                    Text("Loading support links…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
                .apolloPlainSettingsRowInsets(rule: false)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load support links").foregroundStyle(.secondary)
                    Text("\(errorMessage)\nTap to retry.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { Task { await load() } }
                .apolloPlainSettingsRowInsets(rule: false)
            } else {
                // Each contributor as an ordinary settings row: the coffee
                // tile, the name in the label colour, a chevron.
                Section {
                    ForEach(entries) { entry in
                        if let urlString = entry.buyMeACoffeeURL, let url = URL(string: urlString) {
                            Button {
                                openURL(url)
                            } label: {
                                SettingsIconRow(title: entry.resolvedDisplayName,
                                                systemImage: "cup.and.saucer.fill",
                                                tint: .yellow)
                            }
                            .buttonStyle(.plain)
                            .apolloSettingsRowInsets()
                        }
                    }
                } header: {
                    Text("If you're enjoying the updates, consider buying us a coffee!")
                        .apolloSectionHeader()
                }
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Buy Us a Coffee")
        .navigationBarTitleDisplayModeIfAvailable()
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = entries.isEmpty
        errorMessage = nil
        do {
            let contributors = try await ApolloContributorsClient.fetchContributors()
            entries = ApolloContributorsClient.buyCoffeeEntries(from: contributors)
            isLoading = false
        } catch {
            isLoading = false
            if entries.isEmpty {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
