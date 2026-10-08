import SwiftUI
import PhoebusCore

/// Reborn's "Open in App" screen. Apollo's "open in app" rows are scattered across
/// native settings, so this screen gathers them in one place, mirroring the same
/// defaults keys rather than duplicating them. Sections: Apps, X / Twitter
/// (Reborn "Open via Nitter", #1334), Browser, with the footers verbatim.
public struct OpenInAppSettingsScreen: View {
    @State private var toggles: [OpenInAppToggle: Bool] = [:]
    @Setting(ExternalBrowserSettingsStore.storage) private var browserSettings
    @AppStorage(NitterInstances.enabledKey) private var nitterEnabled = false
    @AppStorage(NitterInstances.hostKey) private var nitterHost = ""
    @State private var loadingNitterInstances = false
    @State private var nitterInstances: [NitterInstances.Instance]?
    @State private var showingNitterPicker = false
    @State private var showingNitterCustomHost = false
    @State private var showingNitterInvalidHost = false
    @State private var nitterCustomHost = ""

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
                Toggle("Open via Nitter", isOn: nitterBinding)
                    .accessibilityIdentifier("openInApp.nitter")
                    .apolloSearchRow("Open via Nitter", lastBeforeFooter: !nitterEnabled)
                if nitterEnabled {
                    Button(action: { presentNitterPicker() }) {
                        HStack {
                            Text("Instance").foregroundStyle(.primary)
                            Spacer()
                            if loadingNitterInstances {
                                ProgressView()
                            } else {
                                Text(NitterInstances.savedHost() ?? "None")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .accessibilityIdentifier("openInApp.nitterInstance")
                    .apolloPlainSettingsRowInsets(rule: false)
                }
            } header: {
                Text("X / Twitter")
                    .apolloSectionHeader()
            } footer: {
                Text("Open X posts and profiles on a Nitter instance, so you can read them without an X account. Instances are run by volunteers, may show a quick browser check first, and can go offline at any time. The instance list comes from status.d420.de.")
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
        .confirmationDialog("Nitter Instance", isPresented: $showingNitterPicker, titleVisibility: .visible) {
            ForEach(nitterInstances ?? [], id: \.host) { instance in
                Button(nitterTitle(for: instance)) { applyNitterHost(instance.host) }
            }
            Button("Custom…") {
                nitterCustomHost = NitterInstances.savedHost() ?? ""
                showingNitterCustomHost = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(nitterPickerMessage)
        }
        .alert("Custom Instance", isPresented: $showingNitterCustomHost) {
            TextField("nitter.example.org", text: $nitterCustomHost)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("openInApp.nitterCustomHost")
            Button("Save") { saveNitterCustomHost() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the address of a Nitter instance. Start it with http:// if it doesn't use HTTPS, like one you host at home.")
        }
        .alert("Invalid Instance", isPresented: $showingNitterInvalidHost) {
            Button("OK") { showingNitterCustomHost = true }
        } message: {
            Text("Enter a host name like nitter.example.org. X and Twitter addresses can't be used.")
        }
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

    // MARK: - Nitter

    /// The switch only turns on once an instance is saved, so switching on with
    /// none goes to the picker; cancelling it leaves the switch off.
    private var nitterBinding: Binding<Bool> {
        Binding(
            get: { nitterEnabled },
            set: { newValue in
                if newValue, NitterInstances.savedHost() == nil {
                    presentNitterPicker()
                } else {
                    nitterEnabled = newValue
                }
            }
        )
    }

    /// Fetches the live instance list, then shows it with a Custom… entry. The
    /// tracker is only contacted from here, on an explicit tap.
    private func presentNitterPicker() {
        guard !loadingNitterInstances else { return }
        loadingNitterInstances = true
        Task {
            nitterInstances = try? await NitterInstanceDirectory.shared.healthyInstances()
            loadingNitterInstances = false
            showingNitterPicker = true
        }
    }

    private var nitterPickerMessage: String {
        guard let instances = nitterInstances else {
            return "Couldn't load the instance list. You can still enter an instance yourself."
        }
        return instances.isEmpty
            ? "No public instances are reported healthy right now. You can still enter an instance yourself."
            : "Public instances currently reported healthy, best first."
    }

    private func nitterTitle(for instance: NitterInstances.Instance) -> String {
        var title = instance.host
        if instance.averagePingMilliseconds > 0 { title += " (\(instance.averagePingMilliseconds) ms)" }
        if instance.host == NitterInstances.savedHost() { title += " (Current)" }
        return title
    }

    /// Picking an instance is what enables the feature, whichever row started it.
    private func applyNitterHost(_ host: String) {
        nitterHost = host
        nitterEnabled = true
    }

    private func saveNitterCustomHost() {
        if let host = NitterInstances.normalizeHost(nitterCustomHost) {
            applyNitterHost(host)
        } else {
            // The text-field alert is still dismissing; present the next one on the next turn.
            DispatchQueue.main.async { showingNitterInvalidHost = true }
        }
    }
}
