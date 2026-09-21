import SwiftUI
import PhoebusCore

/// Reborn's "Apollo AI" settings screen: five sections and fourteen rows.
///
/// Covers the Post/Link and Comment sub-toggles, the Minimum Post Length
/// slider, both detail sliders, the "When Opening a Thread" mode picker, the
/// per-provider Model field, the live model browser, the custom Base URL, the
/// Availability readout for cloud providers, Clear AI Cache and Export Apollo
/// AI Logs. Titles, footers and enablement rules follow Reborn; see
/// `ApolloAISettings`.
public struct ApolloAISettingsScreen: View {
    @Setting(ApolloAISettingsStore.storage) private var settings
    @State private var showingClearCacheConfirm = false
    @State private var toast: String?
    @State private var logExport: URL?
    @State private var customHeaders = AICustomHeaders.load()
    /// The header being edited (nil name: a new one).
    @State private var editingHeader: AICustomHeaders.Header?
    @State private var editingOriginalName: String?
    @State private var headerName = ""
    @State private var headerValue = ""

    public init() {}

    public var body: some View {
        List {
            generalSection
            providerSection
            if settings.provider == .custom { customHeadersSection }
            summariesSection
            availabilitySection
            maintenanceSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Phoebus AI")
        .confirmationDialog("Clear AI Cache?",
                            isPresented: $showingClearCacheConfirm,
                            titleVisibility: .visible) {
            Button("Clear AI Cache", role: .destructive) { clearCache() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved post and comment summaries will be removed and generated again when needed.")
        }
        .alert(editingOriginalName == nil ? "Add Header" : "Edit Header", isPresented: $editingHeader.isPresent()) {
            TextField("Name", text: $headerName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Value", text: $headerValue)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { saveHeader() }
            if let original = editingOriginalName {
                Button("Delete", role: .destructive) {
                    customHeaders.removeAll { $0.name == original }
                    AICustomHeaders.save(customHeaders)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        #if canImport(UIKit)
        .sheet(isPresented: $logExport.isPresent()) {
            if let logExport { ActivityShareSheet(items: [logExport]) }
        }
        #endif
        .alert("Phoebus AI", isPresented: $toast.isPresent()) {
            Button("OK", role: .cancel) { toast = nil }
        } message: {
            Text(toast ?? "")
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Toggle("Enable Phoebus AI", isOn: $settings.summariesEnabled)
                .apolloSearchRow("Enable Phoebus AI", lastBeforeFooter: true)
                .accessibilityIdentifier("apolloAI.enableSummaries")
        } header: {
            Text("General")
                .apolloSectionHeader()
        } footer: {
            // Changes with the provider: the cloud copy names the
            // service and warns that text leaves the device.
            Text(settings.generalFooter).apolloSectionFooter()
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        Section {
            ApolloSettingsPicker("AI Provider", selection: $settings.provider,
                                 options: AIProvider.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                // Key / Model / Base URL rows follow for cloud and
                // custom providers, so this row is last (and drops its
                // hairline) only for the local ones.
                .apolloSearchRow("AI Provider",
                                 lastBeforeFooter: !settings.provider.isCloud
                                     && settings.provider != .custom)
                .accessibilityIdentifier("apolloAI.providerPicker")

            // Key / Model / Base URL are visible only for the providers
            // that use them.
            if settings.provider.isCloud {
                stackedField("API Key",
                             placeholder: "Your \(settings.provider.displayName) API key",
                             text: activeKeyBinding,
                             isSecure: true)
                    .accessibilityIdentifier("apolloAI.apiKey")

                stackedField("Model",
                             placeholder: settings.provider.defaultModel ?? "Required — e.g. gpt-4o-mini",
                             text: activeModelBinding,
                             isSecure: false)
                    .accessibilityIdentifier("apolloAI.model")
            }

            if settings.provider.supportsModelBrowsing {
                // Disabled until a key exists: greys the title, drops the chevron and kills
                // the selection style.
                SettingsLink {
                    AIModelBrowserScreen(provider: settings.provider,
                                         apiKey: settings.activeAPIKey ?? "",
                                         selection: activeModelBinding)
                } label: {
                    LabeledContent("Browse Available Models") {
                        Text(settings.activeAPIKey?.isEmpty == false ? "Live List" : "API Key Required")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(settings.activeAPIKey?.isEmpty != false)
                .apolloSearchRow("Browse Available Models")
                .accessibilityIdentifier("apolloAI.browseModels")
            }

            if settings.provider == .custom {
                stackedField("Base URL",
                             placeholder: "https://api.example.com/v1",
                             text: Binding(
                                get: { settings.customBaseURL ?? "" },
                                set: { v in $settings.update { $0.customBaseURL = v.isEmpty ? nil : v } }),
                             isSecure: false,
                             isURL: true)
                    .accessibilityIdentifier("apolloAI.baseURL")
            }
        } header: {
            Text("Provider")
                .apolloSectionHeader()
        } footer: {
            Text(settings.providerFooter).apolloSectionFooter()
        }
    }

    // MARK: - Custom Headers

    /// Reborn's "Custom Headers" section, shown for the custom provider: one
    /// row per header (value masked), then "Add Header…".
    private var customHeadersSection: some View {
        Section {
            ForEach(customHeaders, id: \.name) { header in
                Button {
                    beginEditing(header)
                } label: {
                    HStack {
                        Text(header.name).foregroundStyle(.primary)
                        Spacer()
                        Text("••••••••")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Value hidden")
                    }
                }
                .apolloPlainSettingsRowInsets()
            }
            Button("Add Header…") { beginEditing(nil) }
                .foregroundStyle(Color.apolloAccent)
                .apolloSearchRow("Add Header…", lastBeforeFooter: true)
        } header: {
            Text("Custom Headers").apolloSectionHeader()
        } footer: {
            Text("Extra headers sent with every request to your custom provider. For example, OpenCode Go requires x-opencode-session (any fixed value, such as a UUID). Values are stored in Phoebus's settings on this device and are included in settings backups.")
                .apolloSectionFooter()
        }
    }

    private func beginEditing(_ header: AICustomHeaders.Header?) {
        editingOriginalName = header?.name
        headerName = header?.name ?? ""
        headerValue = header?.value ?? ""
        editingHeader = header ?? AICustomHeaders.Header(name: "", value: "")
    }

    private func saveHeader() {
        let name = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = AICustomHeaders.problem(name: name, value: value) {
            toast = problem
            return
        }
        let others = customHeaders.filter { $0.name != editingOriginalName }
        if others.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            toast = "There's already a \(name) header."
            return
        }
        let header = AICustomHeaders.Header(name: name, value: value)
        if let original = editingOriginalName, let index = customHeaders.firstIndex(where: { $0.name == original }) {
            customHeaders[index] = header
        } else {
            customHeaders.append(header)
        }
        AICustomHeaders.save(customHeaders)
    }

    // MARK: - Summaries

    private var summariesSection: some View {
        Section {
            Toggle("Post/Link Summaries", isOn: $settings.postSummariesEnabled)
                .disabled(!settings.summariesEnabled)
                .apolloSearchRow("Post/Link Summaries")
                .accessibilityIdentifier("apolloAI.postSummaries")

            // Six 50-word detents, 50...300. Applies to text posts only: "linked
            // articles remain eligible regardless".
            ApolloAIDetentSlider(
                label: "Minimum Post Length",
                valueText: "\(settings.postWordThreshold) words",
                tickLabels: ApolloAISettings.wordThresholds.map(String.init),
                selectedIndex: Binding(
                    get: { (settings.postWordThreshold / 50) - 1 },
                    set: { v in $settings.update { $0.postWordThreshold = (v + 1) * 50 } }))
                .disabled(!(settings.summariesEnabled && settings.postSummariesEnabled))
                // A custom slider row, invisible to the settings-row scan (it matches none
                // of `Toggle(`/`Button(`/`NavigationLink`). Kept on a 33pt inset beside
                // "Post/Link Summaries" rather than the List default (17pt).
                .apolloPlainSettingsRowInsets()
                .accessibilityIdentifier("apolloAI.postThreshold")

            ApolloAIDetentSlider(
                label: "Post/Link Detail",
                valueText: settings.postDetail.displayName,
                tickLabels: AISummaryDetail.allCases.map(\.displayName),
                selectedIndex: Binding(
                    get: { settings.postDetail.rawValue },
                    set: { v in $settings.update { $0.postDetail = AISummaryDetail(rawValue: v) ?? .balanced } }))
                .disabled(!(settings.summariesEnabled && settings.postSummariesEnabled))
                .apolloPlainSettingsRowInsets()
                .accessibilityIdentifier("apolloAI.postDetail")

            Toggle("Comment Summaries", isOn: $settings.commentSummariesEnabled)
                .disabled(!settings.summariesEnabled)
                .apolloSearchRow("Comment Summaries")
                .accessibilityIdentifier("apolloAI.commentSummaries")

            ApolloAIDetentSlider(
                label: "Discussion Detail",
                valueText: settings.commentDetail.displayName,
                tickLabels: AISummaryDetail.allCases.map(\.displayName),
                selectedIndex: Binding(
                    get: { settings.commentDetail.rawValue },
                    set: { v in $settings.update { $0.commentDetail = AISummaryDetail(rawValue: v) ?? .balanced } }))
                .disabled(!(settings.summariesEnabled && settings.commentSummariesEnabled))
                .apolloPlainSettingsRowInsets()
                .accessibilityIdentifier("apolloAI.commentDetail")

            // One three-way picker, not two switches: the old "Tap to Summarize" /
            // "Open Summaries Automatically" pair was mutually exclusive "with a
            // non-obvious 'neither' state".
            ApolloSettingsPicker("When Opening a Thread", selection: $settings.summaryMode,
                                 options: AISummaryMode.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                .disabled(!settings.summariesEnabled)
                .apolloSearchRow("When Opening a Thread", lastBeforeFooter: true)
                .accessibilityIdentifier("apolloAI.summaryMode")
        } header: {
            Text("Summaries")
                .apolloSectionHeader()
        } footer: {
            Text(ApolloAISettings.summariesFooter).apolloSectionFooter()
        }
    }

    // MARK: - Availability

    private var availabilitySection: some View {
        Section {
            // The row's TITLE changes with the provider: the cloud one
            // is named after the service.
            LabeledContent(settings.provider.isCloud ? settings.provider.displayName : "On-Device Model") {
                Text(availabilityText)
                    .foregroundStyle(availabilityText == "Ready" ? .green : .secondary)
            }
            // Title varies with the provider, so this row is geometry
            // only: a search entry keyed on a changing title could not
            // be matched from the static index.
            .apolloPlainSettingsRowInsets(rule: false)
            .accessibilityIdentifier("apolloAI.availability")
        } header: {
            Text("Availability")
                .apolloSectionHeader()
        } footer: {
            Text(settings.availabilityFooter).apolloSectionFooter()
        }
    }

    /// Maps on-device's five cases onto the bridge's status integers; cloud
    /// otherwise.
    private var availabilityText: String {
        guard !settings.provider.isCloud else { return settings.cloudAvailability }
        switch OnDeviceSummarizer.availability {
        case .available: return "Ready"
        case .appleIntelligenceNotEnabled: return "Reported Disabled"
        case .modelNotReady: return "Model Downloading"
        case .deviceNotEligible: return "Unsupported Device"
        case .osTooOld: return "Requires iOS 26"
        case .unknown: return "Unknown"
        }
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        Section {
            // Destructive and red: a custom cell so it keeps `systemRed` rather than the
            // accent tint a button row would get.
            Button(role: .destructive) {
                showingClearCacheConfirm = true
            } label: {
                Text("Clear AI Cache").foregroundStyle(.red)
            }
            .apolloSearchRow("Clear AI Cache")
            .accessibilityIdentifier("apolloAI.clearCache")

            Button("Export Phoebus AI Logs") { exportLogs() }
                .apolloSearchRow("Export Phoebus AI Logs", lastBeforeFooter: true)
                .accessibilityIdentifier("apolloAI.exportLogs")
        } header: {
            Text("Maintenance")
                .apolloSectionHeader()
        } footer: {
            Text(ApolloAISettings.maintenanceFooter).apolloSectionFooter()
        }
    }

    // MARK: - Provider field plumbing

    /// Writes to the active provider's own key, so switching providers never
    /// loses one.
    private var activeKeyBinding: Binding<String> {
        Binding(
            get: { settings.activeAPIKey ?? "" },
            set: { newValue in
                let stored = newValue.isEmpty ? nil : newValue
                switch settings.provider {
                case .openRouter: $settings.update { $0.openRouterAPIKey = stored }
                case .gemini: $settings.update { $0.geminiAPIKey = stored }
                case .custom: $settings.update { $0.customAPIKey = stored }
                case .onDevice: break
                }
            })
    }

    private var activeModelBinding: Binding<String> {
        Binding(
            get: { settings.activeModel ?? "" },
            set: { newValue in
                let stored = newValue.isEmpty ? nil : newValue
                switch settings.provider {
                case .openRouter: $settings.update { $0.openRouterModel = stored }
                case .gemini: $settings.update { $0.geminiModel = stored }
                case .custom: $settings.update { $0.customModel = stored }
                case .onDevice: break
                }
            })
    }

    /// A caption stacked over the field, not a leading label: body-size caption,
    /// callout-size field beneath it.
    @ViewBuilder
    private func stackedField(_ label: String, placeholder: String,
                              text: Binding<String>, isSecure: Bool,
                              isURL: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.callout)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(isURL ? .URL : .default)
        }
        .apolloSearchRow(label)
    }

    // MARK: - Actions

    private func clearCache() {
        let removed = AISummaryCache.clear()
        AIArticleExtractor.clearCache()
        toast = removed == 1
            ? "Removed 1 cached summary"
            : "Removed \(removed) cached summaries"
    }

    /// Shares a text file of the session's AI diagnostics, or reports plainly when
    /// there is nothing to share rather than presenting an empty sheet.
    private func exportLogs() {
        let entries = ApolloAILog.entries
        guard !entries.isEmpty else {
            toast = "No Phoebus AI activity has been logged this session."
            return
        }
        // A file to share, as Export Debug Logs does.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("phoebus-ai-log.txt")
        do {
            try entries.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            logExport = url
        } catch {
            toast = "Couldn't write the log: \(error.localizedDescription)"
        }
    }

    private static let sampleText = "This is a short sample post used to test your Phoebus AI configuration. It describes a hypothetical weekend hiking trip, mentions good weather, and asks other subreddit members for trail recommendations near the coast."

}
