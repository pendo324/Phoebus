import SwiftUI
import PhoebusCore

/// Post title translation (Reborn "Translate Post Titles" + "Details on
/// Titles").
///
/// Gated on bulk translation, the post-title toggle and the Don't Translate
/// list. Titles swap in place in the feed row and post header; the
/// "Translated from …" marker follows `ShowTranslationTitleDetails`.
///
/// Results live in one process-wide cache keyed by (target, text), since
/// titles repeat across feed, header, peek and tabs.
@MainActor
final class TitleTranslationCache {
    static let shared = TitleTranslationCache()
    private var done: [String: String] = [:]
    private var inFlight: [String: Task<String?, Never>] = [:]

    func cached(_ title: String, target: String) -> String? { done[target + "\u{1}" + title] }

    func translate(_ title: String, settings: TranslationSettings) async -> String? {
        let key = settings.targetLanguageCode + "\u{1}" + title
        if let hit = done[key] { return hit }
        if let task = inFlight[key] { return await task.value }
        let task = Task<String?, Never> {
            try? await BulkTranslationClient.translate(text: title, to: settings.targetLanguageCode, settings: settings)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        // Same text back means the source already was the target
        // language: nothing to swap or mark.
        if let result, result != title { done[key] = result }
        return done[key]
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

    func body(content: Content) -> some View {
        content.task(id: "\(title)|\(String(describing: threadTranslation))") {
            var settings = TranslationSettingsStore.load()
            if let threadTranslation {
                settings.enableBulkTranslation = threadTranslation
                if threadTranslation { settings.mode = .automatic }
            }
            guard TitleTranslation.applies(to: title, settings: settings) else {
                translated = nil
                return
            }
            if let hit = TitleTranslationCache.shared.cached(title, target: settings.targetLanguageCode) {
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

    /// The provider's own detection first (Google reports it), falling
    /// back to on-device detection.
    private var languageName: String? {
        if let code = BulkTranslationClient.detectedSourceLanguage(for: original) {
            return Locale.current.localizedString(forLanguageCode: code)
        }
        return BulkTranslatedText.languageName(of: original)
    }

    var body: some View {
        let settings = translationSettings
        if settings.showTitleDetails {
            let tint = settings.matchAppColour ? Color.apolloAccent : Color.green.opacity(0.7)
            (Text(Image(systemName: "globe")).foregroundColor(tint)
             + Text(" Translated from ").foregroundColor(.secondary)
             + Text(languageName ?? "another language").foregroundColor(tint))
                .font(.caption2)
                .accessibilityIdentifier("title.translationMarker")
        }
    }
}
