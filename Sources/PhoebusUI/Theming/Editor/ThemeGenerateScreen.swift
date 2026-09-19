import SwiftUI
import PhoebusCore

/// Reborn's AI theme generation sheet: describe a theme in natural language,
/// generate it via the configured LLM provider (`ThemeGenerationSettings`),
/// preview it, and keep it if it looks good.
public struct ThemeGenerateScreen: View {
    let onGenerated: (Theme) -> Void
    @State private var description = ""
    @State private var isDark = false
    @State private var isGenerating = false
    @State private var generatedTheme: Theme?
    @State private var errorMessage: String?
    @Setting(ThemeGenerationSettingsStore.storage) private var settings
    @Environment(\.dismiss) private var dismiss

    public init(onGenerated: @escaping (Theme) -> Void) {
        self.onGenerated = onGenerated
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("e.g. \"sunset over the ocean\"", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        // Free-form entry row: geometry only, and no
                        // footer on this section, so it keeps its rule.
                        .apolloPlainSettingsRowInsets()
                    Toggle("Dark variant", isOn: $isDark)
                        // Sheet, not a settings screen: geometry only.
                        .apolloPlainSettingsRowInsets()
                } header: {
                    Text("Describe your theme")
                        .apolloSectionHeader()
                }
                Section {
                    ApolloSettingsPicker("Provider", selection: $settings.provider,
                                 options: ThemeGenerationProvider.allCases.map { $0 },
                                 display: { $0.displayName })
                    .onChange(of: settings.provider) { _, newProvider in
                        $settings.update { $0.model = newProvider.defaultModel }
                    }
                    .apolloPlainSettingsRowInsets()
                    TextField("API Key", text: Binding(
                        get: { settings.apiKey ?? "" },
                        set: { v in $settings.update { $0.apiKey = v.isEmpty ? nil : v } }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    // "API Key" is a placeholder here, not a row
                    // title, so this is geometry only.
                    .apolloPlainSettingsRowInsets()
                    TextField("Model", text: $settings.model)
                        // Last row before the footer: no rule.
                        .apolloPlainSettingsRowInsets(rule: false)
                } header: {
                    Text("Provider")
                        .apolloSectionHeader()
                } footer: {
                    Text("Uses your own API key.")
                    .apolloSectionFooter()
                }
                if let generatedTheme {
                    Section {
                        HStack {
                            Circle().fill(Color(hex: generatedTheme.accentColorHex)).frame(width: 24, height: 24)
                            Text(generatedTheme.name)
                            Spacer()
                            HStack(spacing: 2) {
                                ForEach(generatedTheme.commentDepthColorHexes, id: \.self) { hex in
                                    Circle().fill(Color(hex: hex)).frame(width: 8, height: 8)
                                }
                            }
                        }
                        .apolloPlainSettingsRowInsets()
                        Button("Use This Theme") {
                            onGenerated(generatedTheme)
                            dismiss()
                        }
                        .apolloPlainSettingsRowInsets()
                    } header: {
                        Text("Preview")
                            .apolloSectionHeader()
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .apolloSettingsListAppearance()
            .navigationTitle("Generate Theme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await generate() }
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Text("Generate")
                        }
                    }
                    .disabled(description.isEmpty || isGenerating)
                }
            }
        }
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            generatedTheme = try await ThemeGenerationClient.generateTheme(description: description, isDark: isDark, settings: settings)
        } catch ThemeGenerationClient.ClientError.notConfigured {
            errorMessage = "Enter your API key first."
        } catch {
            errorMessage = "Couldn't generate a theme. Check your API key and try again."
        }
    }
}
