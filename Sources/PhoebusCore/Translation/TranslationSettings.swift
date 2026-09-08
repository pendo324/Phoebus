import Foundation

/// Apollo-Reborn's "Bulk in-place translation": translate every
/// post/comment inline, with a choice of provider and a mode
/// controlling when translation happens. Distinct from stock Apollo's
/// single Translate action (one tapped piece of text via a webview).
///
/// Default provider is Google. Default LibreTranslate URL is
/// `https://libretranslate.com/translate` (the public `.de` instance
/// shut down; Reborn silently upgrades a stored `.de` URL to `.com`).
///
/// Also supports Microsoft Translator (Azure Cognitive Services, needs
/// the user's own API key) and Apple's on-device Translation. A failed
/// request retries once with another provider, as Reborn's does.
public enum TranslationProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case google
    case libreTranslate
    case microsoft
    /// Apple's on-device Translation. Offered where a session can be made
    /// headlessly (iOS 26 here); never falls back to another provider.
    case apple

    public var id: String { rawValue }

    /// The row's detail text: "Google", "Microsoft" (not the full
    /// service names).
    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .libreTranslate: return "LibreTranslate"
        case .microsoft: return "Microsoft"
        case .apple: return "Apple (On-Device)"
        }
    }
}

/// The three mutually-exclusive translation modes: automatic
/// (translate on load), tap-to-translate (keep original, tappable), or
/// manual (do nothing until requested).
public enum TranslationMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case tapToTranslate
    case manual

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .tapToTranslate: return "Tap to Translate"
        case .manual: return "Manual (Globe)"
        }
    }
}

public struct TranslationSettings: Codable, Sendable, Equatable {
    public var enableBulkTranslation: Bool
    public var provider: TranslationProvider
    public var mode: TranslationMode
    /// Required for `.libreTranslate`. Self-hostable; defaults to the
    /// current public instance.
    public var libreTranslateURL: String
    /// Optional; many public LibreTranslate instances need no key.
    public var libreTranslateAPIKey: String?
    /// Required for `.microsoft`: Azure Cognitive Services API key.
    public var microsoftAPIKey: String?
    /// Optional; only needed for regional/sovereign-cloud Azure resources.
    public var microsoftRegion: String?
    /// Empty means "device default" language.
    public var targetLanguageCode: String
    public var translatePostTitles: Bool
    public var showDetails: Bool
    public var showTitleDetails: Bool
    public var matchAppColour: Bool
    public var useAppleTranslateSheet: Bool
    /// "Don't Translate" language codes, in the order added.
    public var skipLanguageCodes: [String]

    /// Defaults: bulk off, and when on, automatic mode.
    public static let `default` = TranslationSettings(
        enableBulkTranslation: false,
        provider: .google,
        mode: .automatic,
        libreTranslateURL: "https://libretranslate.com/translate",
        libreTranslateAPIKey: nil,
        microsoftAPIKey: nil,
        microsoftRegion: nil,
        targetLanguageCode: ""
    )

    public init(enableBulkTranslation: Bool, provider: TranslationProvider, mode: TranslationMode, libreTranslateURL: String, libreTranslateAPIKey: String?, microsoftAPIKey: String? = nil, microsoftRegion: String? = nil, targetLanguageCode: String, translatePostTitles: Bool = false, showDetails: Bool = true, showTitleDetails: Bool = true, matchAppColour: Bool = false, useAppleTranslateSheet: Bool = false, skipLanguageCodes: [String] = []) {
        self.enableBulkTranslation = enableBulkTranslation
        self.provider = provider
        self.mode = mode
        self.libreTranslateURL = libreTranslateURL
        self.libreTranslateAPIKey = libreTranslateAPIKey
        self.microsoftAPIKey = microsoftAPIKey
        self.microsoftRegion = microsoftRegion
        self.targetLanguageCode = targetLanguageCode
        self.translatePostTitles = translatePostTitles
        self.showDetails = showDetails
        self.showTitleDetails = showTitleDetails
        self.matchAppColour = matchAppColour
        self.useAppleTranslateSheet = useAppleTranslateSheet
        self.skipLanguageCodes = skipLanguageCodes
    }

    /// The code and name of every language the pickers offer, in this
    /// order.
    public static let languageOptions: [(code: String, name: String)] = [
        ("", "Device Default"), ("en", "English"), ("es", "Spanish"),
        ("pt", "Portuguese"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("nl", "Dutch"), ("ru", "Russian"),
        ("uk", "Ukrainian"), ("pl", "Polish"), ("tr", "Turkish"),
        ("ar", "Arabic"), ("he", "Hebrew"), ("hi", "Hindi"),
        ("bn", "Bengali"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh", "Chinese"), ("vi", "Vietnamese"), ("id", "Indonesian"),
        ("th", "Thai"), ("el", "Greek"), ("sv", "Swedish"),
        ("fi", "Finnish"), ("da", "Danish"), ("no", "Norwegian"),
        ("cs", "Czech"), ("ro", "Romanian"), ("hu", "Hungarian"),
        ("bs", "Bosnian"),
    ]

    /// Matches the language-name lookup used by the pickers.
    public static func displayName(forLanguageCode code: String) -> String {
        let normalized = code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        if normalized.isEmpty { return "Device Default" }
        if let match = languageOptions.first(where: { $0.code == normalized }) { return match.name }
        if let localized = Locale.current.localizedString(forLanguageCode: normalized), !localized.isEmpty {
            return localized.capitalized
        }
        return normalized.uppercased()
    }

    /// The override's name, else "Device Default (English)".
    public var targetLanguageDetailText: String {
        let code = targetLanguageCode.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty { return Self.displayName(forLanguageCode: code) }
        let device = Locale.current.language.languageCode?.identifier ?? "en"
        return "Device Default (\(Self.displayName(forLanguageCode: device)))"
    }

    /// Custom decode so settings persisted before `microsoftAPIKey`/
    /// `microsoftRegion` existed still decode successfully.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableBulkTranslation = try container.decode(Bool.self, forKey: .enableBulkTranslation)
        provider = try container.decode(TranslationProvider.self, forKey: .provider)
        mode = try container.decode(TranslationMode.self, forKey: .mode)
        libreTranslateURL = try container.decode(String.self, forKey: .libreTranslateURL)
        libreTranslateAPIKey = (try? container.decodeIfPresent(String.self, forKey: .libreTranslateAPIKey))
        microsoftAPIKey = (try? container.decodeIfPresent(String.self, forKey: .microsoftAPIKey))
        microsoftRegion = (try? container.decodeIfPresent(String.self, forKey: .microsoftRegion))
        targetLanguageCode = try container.decode(String.self, forKey: .targetLanguageCode)
        translatePostTitles = (try? container.decodeIfPresent(Bool.self, forKey: .translatePostTitles)) ?? false
        showDetails = (try? container.decodeIfPresent(Bool.self, forKey: .showDetails)) ?? true
        showTitleDetails = (try? container.decodeIfPresent(Bool.self, forKey: .showTitleDetails)) ?? true
        matchAppColour = (try? container.decodeIfPresent(Bool.self, forKey: .matchAppColour)) ?? false
        useAppleTranslateSheet = (try? container.decodeIfPresent(Bool.self, forKey: .useAppleTranslateSheet)) ?? false
        skipLanguageCodes = (try? container.decodeIfPresent([String].self, forKey: .skipLanguageCodes)) ?? []
    }

    /// LibreTranslate's public instance refuses keyless requests; a
    /// self-hosted one may not (as in Reborn).
    public var libreTranslateNeedsAPIKey: Bool {
        let host = URL(string: normalizedLibreTranslateURL)?.host?.lowercased() ?? ""
        let isPublic = host == "libretranslate.com" || host.hasSuffix(".libretranslate.com")
        return isPublic && (libreTranslateAPIKey ?? "").isEmpty
    }

    /// Silently upgrades an empty or known-dead stored LibreTranslate
    /// URL (the defunct `.de` public instance) to the current default.
    public var normalizedLibreTranslateURL: String {
        let trimmed = libreTranslateURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let deadURL = "https://libretranslate.de/translate"
        if trimmed.isEmpty || trimmed == deadURL {
            return TranslationSettings.default.libreTranslateURL
        }
        return trimmed
    }
}

public enum TranslationSettingsStore {
    private static let key = "com.pendo324.Phoebus.translationSettings"

    public static let storage = SettingsStore<TranslationSettings>(key: key) { TranslationSettings.default }

    public static func load() -> TranslationSettings { storage.load() }

    public static func save(_ settings: TranslationSettings) { storage.save(settings) }
}

extension TranslationSettings: StoredSettingsModel {
    public static var store: SettingsStore<TranslationSettings> { TranslationSettingsStore.storage }
}

extension TranslationSettings {
    /// Whether a thread opens translated: bulk translation on and
    /// translating automatically.
    public static func threadStartsTranslated(_ settings: TranslationSettings) -> Bool {
        settings.enableBulkTranslation && settings.mode == .automatic
    }
}
