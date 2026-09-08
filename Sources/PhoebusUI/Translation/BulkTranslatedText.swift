import SwiftUI
import PhoebusCore
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Reborn's bulk in-place translation applied to a single piece of body
/// text (post selftext or comment body): automatic, tap-to-translate or
/// manual, per `TranslationSettings.mode`.
public struct BulkTranslatedText: View {
    @Setting(TranslationSettings.self) private var storedTranslationSettings
    /// A thread's own globe (Reborn's per-thread toggle) overrides the
    /// app-wide setting for that thread only.
    @Environment(\.threadTranslation) private var threadTranslation

    /// The stored settings with the thread's choice applied: on means
    /// translate this thread automatically, off means show originals.
    private var translationSettings: TranslationSettings {
        var settings = storedTranslationSettings
        if let threadTranslation {
            settings.enableBulkTranslation = threadTranslation
            if threadTranslation { settings.mode = .automatic }
        }
        return settings
    }
    let original: String
    let lineLimit: Int?
    @State private var translated: String?
    @State private var isTranslating = false
    @State private var errorMessage: String?

    public init(_ original: String, lineLimit: Int? = nil) {
        self.original = original
        self.lineLimit = lineLimit
    }

    public var body: some View {
        let settings = translationSettings
        Group {
            if !settings.enableBulkTranslation || Self.isSkipped(original, settings: settings) {
                LongBodyText(original, lineLimit: lineLimit)
            } else {
                content(settings: settings)
            }
        }
        .task(id: original) {
            guard settings.enableBulkTranslation, settings.mode == .automatic,
                  translated == nil, !Self.isSkipped(original, settings: settings) else { return }
            await translate(settings: settings)
        }
    }

    @ViewBuilder
    private func content(settings: TranslationSettings) -> some View {
        if let translated {
            VStack(alignment: .leading, spacing: 4) {
                LongBodyText(translated, lineLimit: lineLimit)
                // Reborn's "🌐 Translated from <Language>" marker, shown when
                // "Details on Comments & Posts" is on or the mode is Tap to Translate.
                // The globe and language name take the marker tint: dimmed system
                // green, or the app accent under "Match App Colour".
                if settings.showDetails || settings.mode == .tapToTranslate {
                    let tint = settings.matchAppColour ? Color.apolloAccent : Color.green.opacity(0.7)
                    (Text(Image(systemName: "globe")).foregroundColor(tint)
                     + Text(" Translated from ").foregroundColor(.secondary)
                     + Text(Self.languageName(of: original) ?? "another language").foregroundColor(tint))
                        .font(.caption2)
                }
            }
        } else if isTranslating {
            HStack(spacing: 6) {
                ProgressView()
                Text("Translating…").font(.caption).foregroundStyle(.secondary)
            }
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 4) {
                LongBodyText(original, lineLimit: lineLimit)
                Text(errorMessage).font(.caption2).foregroundStyle(.red)
            }
        } else {
            switch settings.mode {
            case .automatic:
                // The task lives on the stable container below, not on this branch:
                // `translate` flips `isTranslating`, which swaps this branch out, and a
                // `.task` on a view that leaves the hierarchy is cancelled.
                LongBodyText(original, lineLimit: lineLimit)
            case .tapToTranslate:
                VStack(alignment: .leading, spacing: 4) {
                    LongBodyText(original, lineLimit: lineLimit)
                    Button("Translate") {
                        Task { await translate(settings: settings) }
                    }
                    .font(.caption)
                }
            case .manual:
                LongBodyText(original, lineLimit: lineLimit)
                    .onTapGesture(count: 2) {
                        Task { await translate(settings: settings) }
                    }
            }
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
    }

    /// The dominant language of `text` as a lowercase base code ("it").
    static func dominantLanguage(of text: String) -> String? {
        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return language.rawValue.split(separator: "-").first.map { String($0).lowercased() }
        #else
        return nil
        #endif
    }

    static func languageName(of text: String) -> String? {
        guard let code = dominantLanguage(of: text) else { return nil }
        return Locale.current.localizedString(forLanguageCode: code)
    }

    /// Reborn's "Don't Translate" list (`TranslationSkipLanguages`):
    /// text whose dominant language is listed is left alone.
    static func isSkipped(_ text: String, settings: TranslationSettings) -> Bool {
        guard !settings.skipLanguageCodes.isEmpty, let code = dominantLanguage(of: text) else { return false }
        return settings.skipLanguageCodes.contains { $0.lowercased() == code }
    }

    private func translate(settings: TranslationSettings) async {
        isTranslating = true
        defer { isTranslating = false }
        do {
            translated = try await BulkTranslationClient.translate(text: original, to: settings.targetLanguageCode, settings: settings)
        } catch {
            // A cancelled request is not a failure. Automatic translation runs in
            // `.task`, which SwiftUI cancels when the row re-renders or leaves the
            // screen (URLError -999). Leaving the state untouched lets `.task`
            // start again when the row next appears.
            if Self.isCancellation(error) { return }
            errorMessage = "Translation failed."
        }
    }
}

private struct ThreadTranslationKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// A thread's translate-this-thread choice; nil follows Settings.
    var threadTranslation: Bool? {
        get { self[ThreadTranslationKey.self] }
        set { self[ThreadTranslationKey.self] = newValue }
    }
}
