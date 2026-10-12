import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reborn "Summary Language" (#1362): the language summaries are written in.
/// The model answers in its input's language unless the instructions name one,
/// so every summary prompt leads with "You MUST respond in <language>.".
///
/// The language is the Apollo AI › Summaries › Language pick, else the
/// device's preferred languages in order (Device Default). Apple's on-device
/// model throws `unsupportedLanguageOrLocale` for languages it can't write, so
/// those are skipped; cloud models write any language.
public enum AISummaryLanguage {
    /// A language summaries are written in: language plus script only ("en",
    /// "pt", "zh-Hant"), since the script separates Simplified from Traditional
    /// Chinese and a region adds nothing a summary needs.
    public struct Resolved: Equatable, Sendable {
        public let identifier: String
        /// True when it is the picked language, false when it is the device's.
        public let picked: Bool

        public init(identifier: String, picked: Bool) {
            self.identifier = identifier
            self.picked = picked
        }
    }

    /// A language code as the model lists it: lowercase, without region or
    /// script, and Norwegian "no" (Translation's list) as Bokmål "nb".
    static func modelCode(_ identifier: String) -> String? {
        guard let code = Locale.Components(identifier: identifier).languageComponents.languageCode?.identifier.lowercased(),
              !code.isEmpty else { return nil }
        return code == "no" ? "nb" : code
    }

    /// Base language codes Apple's on-device model writes; nil when the OS
    /// can't say (before iOS 26), which callers read as "unknown", not "none".
    public static var onDeviceCodes: Set<String>? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let codes = SystemLanguageModel.default.supportedLanguages
                .compactMap { $0.languageCode?.identifier.lowercased() }
            return codes.isEmpty ? nil : Set(codes)
        }
        #endif
        return nil
    }

    /// Whether the on-device model can write `identifier` ("pt", "no",
    /// "zh-Hant"). True when the OS can't say.
    public static func onDeviceCanWrite(_ identifier: String, writable: Set<String>? = onDeviceCodes) -> Bool {
        guard let code = modelCode(identifier) else { return false }
        return writable?.contains(code) ?? true
    }

    /// The language summaries are written in, or nil when no candidate fits
    /// (the prompts then name none and the model answers in the text's own
    /// language). `choice` is the stored pick, "" for Device Default.
    public static func resolve(
        choice: String, isCloud: Bool,
        writable onDeviceWritable: Set<String>? = AISummaryLanguage.onDeviceCodes,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Resolved? {
        let writable = isCloud ? nil : onDeviceWritable
        // If the on-device model didn't say what it writes, skip the pick (it
        // could be one the model can't write) and use the device language:
        // Apple Intelligence only runs in a supported device language.
        let choiceIsCandidate = !choice.isEmpty && (isCloud || writable != nil)
        var candidates = choiceIsCandidate ? [choice] : []
        candidates += preferredLanguages
        for (index, candidate) in candidates.enumerated() {
            guard let code = modelCode(candidate), writable?.contains(code) ?? true else { continue }
            // Only a script the identifier spells out ("zh-Hant-TW"), not an inferred one.
            let script = Locale.Components(identifier: candidate).languageComponents.script
            let identifier = script.map { "\(code)-\($0.identifier)" } ?? code
            return Resolved(identifier: identifier, picked: choiceIsCandidate && index == 0)
        }
        return nil
    }

    /// `resolve` for the language and provider in `settings`.
    public static func resolve(for settings: ApolloAISettings) -> Resolved? {
        resolve(choice: settings.summaryLanguage, isCloud: settings.provider.isCloud)
    }

    /// English name of a language identifier: Translation's name for its codes,
    /// else the system's ("Chinese (Traditional)" for zh-Hant).
    public static func name(for identifier: String) -> String {
        if let match = TranslationSettings.languageOptions.first(where: { !$0.code.isEmpty && $0.code == identifier }) {
            return match.name
        }
        return Locale(identifier: "en_US").localizedString(forIdentifier: identifier) ?? identifier
    }

    /// `instructions` led by the language, worded as Apple's guide words it. It
    /// has to come first: appended after the summary rules the on-device model
    /// still answered in the article's language. Unchanged when `language` is nil.
    public static func led(_ instructions: String, by language: Resolved?) -> String {
        guard let language,
              let name = Locale(identifier: "en_US").localizedString(forIdentifier: language.identifier),
              !name.isEmpty else { return instructions }
        return "You MUST respond in \(name). \(instructions)"
    }

    /// Translation's language list, narrowed to what the on-device model writes
    /// while it is the provider (cloud models write all of them). Device
    /// Default ("") stays first. If the model can't say, the full list stays.
    public static func options(isCloud: Bool, writable: Set<String>? = onDeviceCodes) -> [(code: String, name: String)] {
        TranslationSettings.languageOptions.filter {
            $0.code.isEmpty || isCloud || onDeviceCanWrite($0.code, writable: writable)
        }
    }

    /// The row's value: "Device Default (English)", the picked language, or,
    /// when the on-device model can't write the pick (picked under a cloud
    /// provider), what summaries actually use: "Greek (using English)".
    public static func detailText(choice: String, resolved: Resolved?) -> String {
        let inUseName = resolved.map { name(for: $0.identifier) }
        if choice.isEmpty {
            return inUseName.map { "Device Default (\($0))" } ?? "Device Default"
        }
        let choiceName = name(for: choice)
        guard let inUseName, !(resolved?.picked ?? false) else { return choiceName }
        return "\(choiceName) (using \(inUseName))"
    }
}
