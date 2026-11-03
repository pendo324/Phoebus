import SwiftUI
import PhoebusCore

/// Post title translation (Reborn "Translate Post Titles" + "Details on
/// Titles").
///
/// Gated on bulk translation, the post-title toggle and the Don't Translate
/// list. Titles swap in place in the feed row and post header; the
/// "Translated from …" marker follows `ShowTranslationTitleDetails`.
///
/// Answers live in the shared `TranslationOutcomeCache` keyed by (target,
/// text), since titles repeat across feed, header, peek and tabs. A title the
/// provider hands back unchanged (already in the target language) is kept
/// there too, so it is neither swapped, marked nor asked for again.
@MainActor
final class TitleTranslationCache {
    static let shared = TitleTranslationCache()
    private var inFlight: [String: Task<TranslationOutcome?, Never>] = [:]

    /// The text to show, nil when the title is unknown or needs no swap.
    func cached(_ title: String, settings: TranslationSettings) -> String? {
        let outcome = TranslationOutcomeCache.shared.outcome(for: title, target: settings.targetLanguageCode)
        return outcome.flatMap { $0.isShown(skipping: settings.skipLanguageCodes) ? $0.text : nil }
    }

    func translate(_ title: String, settings: TranslationSettings) async -> String? {
        if TranslationOutcomeCache.shared.outcome(for: title, target: settings.targetLanguageCode) == nil {
            let key = settings.targetLanguageCode + "\u{1}" + title
            if let task = inFlight[key] {
                _ = await task.value
            } else {
                let task = Task<TranslationOutcome?, Never> {
                    try? await BulkTranslationClient.translateCached(text: title, to: settings.targetLanguageCode, settings: settings)
                }
                inFlight[key] = task
                _ = await task.value
                inFlight[key] = nil
            }
        }
        return cached(title, settings: settings)
    }
}

enum TitleTranslation {
    /// Whether this title should be translated at all right now.
    static func applies(to title: String, settings: TranslationSettings) -> Bool {
        settings.enableBulkTranslation && settings.translatePostTitles
            && settings.mode == .automatic
            && !BulkTranslatedText.isSkipped(title, settings: settings)
            && BulkTranslatedText.dominantLanguage(of: title)
                .map { $0 != settings.targetLanguageCode.lowercased().split(separator: "-").first.map(String.init) } ?? true
    }
}

/// Drives one title's translation. Owners read `display` for the text
/// and `marker` for the optional "Translated from" line.
struct TitleTranslationModifier: ViewModifier {
    let title: String
    @Binding var translated: String?
    /// The thread's globe: titles follow it too, as Reborn's do.
    @Environment(\.threadTranslation) private var threadTranslation
    @Environment(\.isSettingsPreview) private var isSettingsPreview

    func body(content: Content) -> some View {
        content.task(id: "\(title)|\(String(describing: threadTranslation))") {
            // A settings preview never sends its sample title to a translator.
            guard !isSettingsPreview else { return }
            var settings = TranslationSettingsStore.load()
            if let threadTranslation {
                settings.enableBulkTranslation = threadTranslation
                if threadTranslation { settings.mode = .automatic }
            }
            guard TitleTranslation.applies(to: title, settings: settings) else {
                translated = nil
                return
            }
            if let hit = TitleTranslationCache.shared.cached(title, settings: settings) {
                translated = hit
                return
            }
            translated = await TitleTranslationCache.shared.translate(title, settings: settings)
        }
    }
}

extension View {
    func apolloTranslatesTitle(_ title: String, into translated: Binding<String?>) -> some View {
        modifier(TitleTranslationModifier(title: title, translated: translated))
    }
}

/// "🌐 Translated from <Language>" under a translated title, shown when
/// Details on Titles is on (same tint rule as bodies: dimmed green, or
/// the accent under Match App Colour).
struct TitleTranslationMarker: View {
    @Setting(TranslationSettings.self) private var translationSettings
    let original: String

    /// The language the provider reported, falling back to on-device
    /// detection for an answer that named none.
    private func languageName(_ settings: TranslationSettings) -> String {
        let outcome = TranslationOutcomeCache.shared.outcome(for: original, target: settings.targetLanguageCode)
        let fallback = BulkTranslatedText.dominantLanguage(of: original)
        return outcome?.markerLanguageName(fallbackCode: fallback)
            ?? TranslationSource.markerLanguageName(code: fallback)
    }

    var body: some View {
        let settings = translationSettings
        if settings.showTitleDetails {
            let tint = settings.matchAppColour ? Color.apolloAccent : Color.green.opacity(0.7)
            (Text(Image(systemName: "globe")).foregroundColor(tint)
             + Text(" Translated from ").foregroundColor(.secondary)
             + Text(languageName(settings)).foregroundColor(tint))
                .font(.caption2)
                .accessibilityIdentifier("title.translationMarker")
        }
    }
}
