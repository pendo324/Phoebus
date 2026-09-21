import SwiftUI
import PhoebusCore

/// Apollo AI's live model picker: a searchable list titled "OpenRouter Models"
/// or "Gemini Models" with a "Search models" field, a badge pill per row, a
/// checkmark on the current selection, and a provider-specific footer
/// explaining the badges.
///
/// Selecting a model writes it through the binding and pops, since the settings
/// screen re-reads it.
struct AIModelBrowserScreen: View {
    let provider: AIProvider
    let apiKey: String
    @Binding var selection: String

    @Environment(\.dismiss) private var dismiss
    @State private var models: [AIModelCatalog.Model] = []
    @State private var query = ""
    @State private var loadError: String?
    @State private var isLoading = true

    private var filtered: [AIModelCatalog.Model] {
        guard !query.isEmpty else { return models }
        // Matches on ID or name.
        return models.filter {
            $0.id.localizedCaseInsensitiveContains(query)
            || $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading models\u{2026}").foregroundStyle(.secondary)
                }
            } else if let loadError {
                // The empty state tells the user to pull down to retry.
                Text("Couldn't load models.\n\(loadError)\n\nPull down to retry.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("apolloAI.modelBrowser.error")
            } else if filtered.isEmpty {
                Text("No matching models").foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(filtered) { model in
                        Button {
                            selection = model.id
                            dismiss()
                        } label: {
                            row(for: model)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(AIModelCatalog.disclaimer(for: provider)).apolloSectionFooter()
                }
            }
        }
        .apolloSettingsListAppearance()
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search models")
        .navigationTitle(provider == .openRouter ? "OpenRouter Models" : "Gemini Models")
        .navigationBarTitleDisplayModeIfAvailable()
        .refreshable { await load() }
        .task { await load() }
    }

    private func row(for model: AIModelCatalog.Model) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                Text(model.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let badge = model.badge {
                // "Free gets the stronger filled treatment;
                // informational lifecycle/Paid tags" do not.
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(badge == "Free"
                                       ? Color.accentColor
                                       : Color.secondary.opacity(0.18)))
                    .foregroundStyle(badge == "Free" ? Color.white : Color.secondary)
            }
            if model.id == selection {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("apolloAI.model.\(model.id)")
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            models = try await AIModelCatalog.load(provider: provider, apiKey: apiKey)
            ApolloAILog.record("Loaded \(models.count) \(provider.rawValue) models")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? UserFacingError.text(for: error)
            loadError = message
            ApolloAILog.record("Model list failed for \(provider.rawValue): \(message)")
        }
    }
}
