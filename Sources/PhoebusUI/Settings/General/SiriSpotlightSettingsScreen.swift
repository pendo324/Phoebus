import SwiftUI
import PhoebusCore

/// Reborn's Siri & Spotlight settings (#1299, Settings › Apollo Reborn ›
/// Siri & Spotlight): the opt-in "Index Phoebus Content" switch, a refresh of
/// the subscribed communities, and what the index holds. The work runs in the
/// app's content service (`SiriContent.controller`); this only asks it.
@MainActor
public struct SiriSpotlightSettingsScreen: View {
    @Setting(SiriContentSettings.enabled) private var enabled
    @State private var busy = false
    @State private var statusText = "Checking index…"

    public init() {}

    public var body: some View {
        List {
            Section {
                Toggle("Index Phoebus Content", isOn: Binding(
                    get: { enabled },
                    set: { newValue in run { await $0.setIndexing(newValue) } }
                ))
                .disabled(busy)
                .apolloSearchRow("Index Phoebus Content")
                .accessibilityIdentifier("siri.enabled")

                Button("Refresh Subscribed Communities") { run { await $0.refreshSubscriptions() } }
                    .disabled(busy || !enabled)
                    .apolloSearchRow("Refresh Subscribed Communities", lastBeforeFooter: true)
                    .accessibilityIdentifier("siri.refresh")
            } header: {
                Text("Searchable Content")
                    .apolloSectionHeader()
            } footer: {
                Text("Makes eligible public, non-NSFW posts loaded in Phoebus and subscribed communities searchable in Spotlight and Siri. Up to 1,000 posts and 500 communities are retained for 30 days. Turning off clears this index. Private communities and hidden or removed posts are excluded.")
                    .apolloSectionFooter()
            }

            Section {
                Text(statusText)
                    .accessibilityIdentifier("siri.status")
                Button("Check Index Status") { run { await $0.indexStatus() } }
                    .disabled(busy)
                    .apolloSearchRow("Check Index Status", lastBeforeFooter: true)
                    .accessibilityIdentifier("siri.check")
            } header: {
                Text("Index Status")
                    .apolloSectionHeader()
            } footer: {
                Text("Search Phoebus opens the search screen. Find Indexed Phoebus Posts searches this device's catalogue. Failed hide or unsubscribe requests still remove indexed content conservatively.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Siri & Spotlight")
        .task { run { await $0.indexStatus() } }
    }

    private func run(_ command: @escaping @MainActor (any SiriContentControlling) async -> String) {
        guard !busy else { return }
        guard let controller = SiriContent.controller else {
            statusText = "Siri & Spotlight needs iOS 27."
            return
        }
        busy = true
        statusText = "Updating index…"
        Task {
            let result = await command(controller)
            statusText = result
            busy = false
        }
    }
}
