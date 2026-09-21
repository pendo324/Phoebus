import SwiftUI
import PhoebusCore

/// Reborn's "Translation" settings screen. Five sections: General (8 rows;
/// disabled rows grey out rather than disappear), Context Menu (only where
/// Apple's Translate sheet exists), Don't Translate (one row per skipped
/// language plus "Add Language…"), Microsoft, and LibreTranslate.
public struct TranslationSettingsScreen: View {
    @Setting(TranslationSettingsStore.storage) private var settings
    @State private var showingAddLanguage = false
    @State private var pendingRemoval: String?

    public init() {}

    private var bulkOn: Bool { settings.enableBulkTranslation }
    /// Details toggles are also greyed in Tap to Translate mode, where
    /// "the markers/affordances ARE the controls".
    private var detailsEnabled: Bool { bulkOn && settings.mode != .tapToTranslate }

    public var body: some View {
        List {
            Section {
                Toggle("Enable Bulk Translation", isOn: $settings.enableBulkTranslation)
                    .apolloSearchRow("Enable Bulk Translation")
                ApolloSettingsPicker("Translation Mode", selection: $settings.mode,
                                     options: TranslationMode.allCases.map { $0 },
                                     display: { $0.displayName },
                                     showsChevron: bulkOn) {
                    Text("Translation Mode")
                }
                .disabled(!bulkOn)
                .apolloSearchRow("Translation Mode")
                Toggle("Translate Post Titles", isOn: $settings.translatePostTitles)
                    .disabled(!bulkOn)
                    .apolloSearchRow("Translate Post Titles")
                Toggle("Details on Comments & Posts", isOn: $settings.showDetails)
                    .disabled(!detailsEnabled)
                    .apolloSearchRow("Details on Comments & Posts")
                Toggle("Details on Titles", isOn: $settings.showTitleDetails)
                    .disabled(!detailsEnabled)
                    .apolloSearchRow("Details on Titles")
                Toggle("Match App Colour", isOn: $settings.matchAppColour)
                    .disabled(!bulkOn)
                    .apolloSearchRow("Match App Colour")
                // Value rows with a disclosure indicator.
                ApolloSettingsPicker("Target Language", selection: $settings.targetLanguageCode,
                                     options: TranslationSettings.languageOptions.map { $0.code },
                                     display: { $0.isEmpty ? settings.targetLanguageDetailText
                                                           : TranslationSettings.displayName(forLanguageCode: $0) },
                                     showsChevron: true) {
                    Text("Target Language")
                }
                .apolloSearchRow("Target Language")
                ApolloSettingsPicker("Primary Provider", selection: $settings.provider,
                                     options: TranslationProvider.allCases.filter {
                                         $0 != .apple || BulkTranslationClient.appleTranslationAvailable || settings.provider == .apple
                                     },
                                     display: { $0.displayName },
                                     showsChevron: true) {
                    Text("Primary Provider")
                }
                .apolloSearchRow("Primary Provider", lastBeforeFooter: true)
            } header: {
                Text("General")
                    .apolloSectionHeader()
            } footer: {
                Text("Translates comments and post titles in place.\n\nAutomatic translates on open. Tap to Translate adds a per-item tap. Manual waits for the globe.\n\nDetails rows add \"Translated from …\" labels.\n\nGoogle is free but rate-limits heavy use. Apple is offline and unlimited (iOS 18+). Microsoft and LibreTranslate need their own keys, set up below.")
                    .apolloSectionFooter()
            }

            // Built only where the OS can present Apple's sheet
            // (iOS 17.4+).
            if #available(iOS 17.4, *) {
                Section {
                    Toggle("Use Apple Translate Sheet", isOn: $settings.useAppleTranslateSheet)
                        .apolloSearchRow("Use Apple Translate Sheet", lastBeforeFooter: true)
                } header: {
                    Text("Context Menu")
                        .apolloSectionHeader()
                } footer: {
                    Text("Opens iOS's Translate sheet instead of a Google Translate page. Not always on-device — iOS may send text to Apple's servers unless offline mode is on in the Translate app.")
                        .apolloSectionFooter()
                }
            }

            Section {
                ForEach(settings.skipLanguageCodes, id: \.self) { code in
                    // Subtitle cell: name over the upper-cased code,
                    // with a red trash accessory.
                    Button {
                        pendingRemoval = code
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(TranslationSettings.displayName(forLanguageCode: code))
                                    .foregroundStyle(.primary)
                                Text(code.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                    // "Add Language…" follows, so these keep the rule.
                    .apolloPlainSettingsRowInsets()
                }
                Button("Add Language…") { showingAddLanguage = true }
                    .apolloSearchRow("Add Language…", lastBeforeFooter: true)
            } header: {
                Text("Don't Translate")
                    .apolloSectionHeader()
            } footer: {
                Text("Posts and comments detected as one of these languages will be left in their original form. Mixed-language text is still translated so embedded foreign words come through.")
                    .apolloSectionFooter()
            }

            Section {
                // "API Key" appears in both the Microsoft and LibreTranslate sections,
                // so a search anchor on the title would be ambiguous: geometry only.
                ApolloSettingsTextFieldRow("API Key", placeholder: "Required", text: optionalBinding(\.microsoftAPIKey), secure: true, widthFraction: 0.60)
                    .apolloPlainSettingsRowInsets()
                ApolloSettingsTextFieldRow("Region", placeholder: "e.g. westeurope", text: optionalBinding(\.microsoftRegion), widthFraction: 0.60)
                    .apolloSearchRow("Region", lastBeforeFooter: true)
            } header: {
                Text("Microsoft")
                    .apolloSectionHeader()
            } footer: {
                Text("Free Azure key — 2 million characters a month. Add a Translator resource on the F0 plan in the Azure portal, then paste a key here. Region is the resource's location; leave empty only if it's Global.")
                    .apolloSectionFooter()
            }

            Section {
                ApolloSettingsTextFieldRow("API URL", placeholder: TranslationSettings.default.libreTranslateURL, text: $settings.libreTranslateURL, widthFraction: 0.60, keyboard: .URL)
                    .apolloSearchRow("API URL")
                ApolloSettingsTextFieldRow("API Key", placeholder: "Required", text: optionalBinding(\.libreTranslateAPIKey), secure: true, widthFraction: 0.60)
                    .apolloPlainSettingsRowInsets(rule: false)
            } header: {
                Text("LibreTranslate")
                    .apolloSectionHeader()
            } footer: {
                Text("A key is required — the free public instances shut down. Get one at portal.libretranslate.com, or point the URL at your own server, which needs no key.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Translation")
        // "Don't Translate" sheet.
        .confirmationDialog("Don't Translate", isPresented: $showingAddLanguage, titleVisibility: .visible) {
            let remaining = TranslationSettings.languageOptions
                .filter { !$0.code.isEmpty && !settings.skipLanguageCodes.contains($0.code) }
            if remaining.isEmpty {
                Button("All available languages already added") {}.disabled(true)
            } else {
                ForEach(remaining, id: \.code) { option in
                    Button(option.name) { $settings.update { $0.skipLanguageCodes.append(option.code) } }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick a language to leave untranslated.")
        }
        // Removal confirmation.
        .confirmationDialog(
            pendingRemoval.map { "Remove \(TranslationSettings.displayName(forLanguageCode: $0)) from Don't Translate?" } ?? "",
            isPresented: $pendingRemoval.isPresent(),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let code = pendingRemoval { $settings.update { $0.skipLanguageCodes.removeAll { $0 == code } } }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<TranslationSettings, String?>) -> Binding<String> {
        Binding(
            get: { settings[keyPath: keyPath] ?? "" },
            set: { v in $settings.update { $0[keyPath: keyPath] = v.isEmpty ? nil : v } }
        )
    }
}

