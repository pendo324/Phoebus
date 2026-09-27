import SwiftUI
import PhoebusCore

/// Reborn's "Open in App" screen. Apollo's "open in app" rows are scattered across
/// native settings, so this screen gathers them in one place, mirroring the same
/// defaults keys rather than duplicating them. Three sections: Apps, Browser,
/// Safari, with the footers verbatim.
public struct OpenInAppSettingsScreen: View {
    @State private var toggles: [OpenInAppToggle: Bool] = [:]
    @Setting(ExternalBrowserSettingsStore.storage) private var browserSettings

    public init() {}

    public var body: some View {
        List {
            Section {
                // Plain app names in alphabetical order; the footer carries the explanation.
                ForEach(OpenInAppToggle.allCases) { toggle in
                    Toggle(toggle.displayName, isOn: binding(for: toggle))
                        .apolloSearchRow(toggle.displayName)
                        .accessibilityIdentifier("openInApp.\(toggle.rawValue)")
                }
            } header: {
                Text("Apps")
                    .apolloSectionHeader()
            } footer: {
                Text("When enabled, links to these services open directly in their app (if installed) instead of a web view.")
                    .apolloSectionFooter()
            }

            Section {
                SettingsLink {
                    ExternalBrowserSettingsScreen()
                } label: {
                    LabeledContent("Open Links in", value: browserSettings.preferredBrowser.displayName)
                }
                .apolloSearchRow("Open Links in", lastBeforeFooter: true)
            } header: {
                Text("Browser")
                    .apolloSectionHeader()
            } footer: {
                // Verbatim, minus its closing "This is Apollo's own setting, relocated here."
                Text("Choose where every other web link opens. In-App Safari opens links inside Phoebus; Safari and the other browsers appear as they're installed. This is Phoebus's own setting, relocated here.")
                    .apolloSectionFooter()
            }

        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Open in App")
        .navigationBarTitleDisplayModeIfAvailable()
        .onAppear(perform: reload)
        // Re-reads when it reappears, since the mirrored defaults can change while it is
        // down the nav stack. `.onAppear` does not fire on tab switches, hence
        // `.apolloTabDidReappear`.
        .onReceive(NotificationCenter.default.publisher(for: .apolloTabDidReappear)) { _ in
            reload()
        }
    }

    private func reload() {
        var loaded: [OpenInAppToggle: Bool] = [:]
        for toggle in OpenInAppToggle.allCases { loaded[toggle] = toggle.isEnabled }
        toggles = loaded
    }

    private func binding(for toggle: OpenInAppToggle) -> Binding<Bool> {
        Binding(
            get: { toggles[toggle] ?? toggle.isEnabled },
            set: { newValue in
                toggles[toggle] = newValue
                toggle.isEnabled = newValue
            }
        )
    }
}
