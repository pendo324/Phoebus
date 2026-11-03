import Foundation

/// What a provider answered for one text: the translation, the language
/// it says it translated from, and whether the text actually changed.
/// Reborn's "Translated from <Language>" marker names the provider's
/// language and is left off text the provider handed back unchanged.
public struct TranslationOutcome: Sendable, Equatable {
    public let text: String
    /// Base code the provider reported ("es", "zh"); nil when it gave none.
    public let sourceLanguage: String?
    public let isChanged: Bool

    public init(original: String, translated: String, reportedSource: String?) {
        self.text = translated
        self.sourceLanguage = TranslationSource.normalizedReportedLanguage(reportedSource)
        self.isChanged = TranslationSource.textChanged(from: original, to: translated)
    }

    /// Whether the translated text replaces the original: it changed, and
    /// the provider did not see a language on the "Don't Translate" list.
    public func isShown(skipping skipLanguageCodes: [String]) -> Bool {
        guard isChanged else { return false }
        guard let sourceLanguage else { return true }
        return !skipLanguageCodes.contains { $0.lowercased() == sourceLanguage }
    }

    /// The marker's language: the provider's, else the caller's on-device
    /// guess, else a generic phrase.
    public func markerLanguageName(fallbackCode: String? = nil, locale: Locale = .current) -> String {
        TranslationSource.markerLanguageName(code: sourceLanguage ?? fallbackCode, locale: locale)
    }
}

public enum TranslationSource {
    /// Folds a provider-reported language ("es", "zh-CN", "zh-Hans",
    /// the withdrawn "iw") to the base code the markers and the Don't
    /// Translate list use. Non-answers ("und", "auto", junk) give nil.
    public static func normalizedReportedLanguage(_ reported: String?) -> String? {
        guard let reported else { return nil }
        let trimmed = reported.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        guard (2...3).contains(base.count), base.allSatisfy({ $0 >= "a" && $0 <= "z" }) else { return nil }
        if base == "und" { return nil }
        // Google still answers with ISO 639's withdrawn codes for these.
        let legacy = ["iw": "he", "jw": "jv", "in": "id", "ji": "yi"]
        return legacy[base] ?? base
    }

    /// The language's name in `locale` ("af" reads "Afrikaans"), nil when
    /// the code is unknown.
    public static func displayName(forCode code: String, locale: Locale = .current) -> String? {
        let name = locale.localizedString(forLanguageCode: code)
        return name == code ? nil : name
    }

    public static func markerLanguageName(code: String?, locale: Locale = .current) -> String {
        guard let code = normalizedReportedLanguage(code) else { return "another language" }
        return displayName(forCode: code, locale: locale) ?? "another language"
    }

    /// False when the "translation" is the original handed back (the
    /// provider saw the target language, or a name or slang word with
    /// nothing to translate). Case, spacing and inline media tokens are
    /// not a change.
    public static func textChanged(from original: String, to translated: String) -> Bool {
        let source = comparable(original)
        let result = comparable(translated)
        return !source.isEmpty && !result.isEmpty && source != result
    }

    /// Lowercased, whitespace-collapsed, with `![gif](giphy|id)` tokens
    /// dropped: those never reach the provider, so a one-word reply with
    /// a GIF would otherwise never equal its own echo.
    static func comparable(_ text: String) -> String {
        var stripped = text
        if stripped.contains("![") {
            stripped = stripped.replacingOccurrences(
                of: #"!\[[^\]\n]*\]\([a-z]+\|[^)\n]*\)"#, with: "", options: .regularExpression)
        }
        return stripped.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Answers already received this session, so a row that scrolls back
/// into view (or a second row with the same text) does not ask again.
/// Text a provider handed back unchanged is kept too: without it every
/// such row would be retried each time it appeared.
public final class TranslationOutcomeCache: @unchecked Sendable {
    public static let shared = TranslationOutcomeCache()

    private var outcomes: [String: TranslationOutcome] = [:]
    private let lock = NSLock()
    private let limit = 1000

    public init() {}

    private func key(_ text: String, _ target: String) -> String {
        target.lowercased() + "\u{1}" + text
    }

    public func outcome(for text: String, target: String) -> TranslationOutcome? {
        lock.lock(); defer { lock.unlock() }
        return outcomes[key(text, target)]
    }

    public func store(_ outcome: TranslationOutcome, for text: String, target: String) {
        lock.lock(); defer { lock.unlock() }
        if outcomes.count >= limit { outcomes.removeAll(keepingCapacity: true) }
        outcomes[key(text, target)] = outcome
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        outcomes.removeAll()
    }
}
