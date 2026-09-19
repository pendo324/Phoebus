import Foundation

/// Apollo-Reborn's AI-generated themes: describe a theme in natural
/// language and an LLM picks colors. The user supplies their own key for an
/// OpenAI/Gemini/OpenRouter-compatible provider, as with Reborn's AI
/// Summaries; no credential is bundled or shared.
public enum ThemeGenerationProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case openAI
    case gemini
    case openRouter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .openRouter: return "OpenRouter"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .gemini: return "gemini-1.5-flash"
        case .openRouter: return "openai/gpt-4o-mini"
        }
    }
}

public struct ThemeGenerationSettings: Codable, Sendable, Equatable {
    public var provider: ThemeGenerationProvider
    public var apiKey: String?
    public var model: String

    public static let `default` = ThemeGenerationSettings(provider: .openAI, apiKey: nil, model: ThemeGenerationProvider.openAI.defaultModel)

    public init(provider: ThemeGenerationProvider, apiKey: String?, model: String) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
    }
}

public enum ThemeGenerationSettingsStore {
    private static let key = "com.pendo324.Phoebus.themeGenerationSettings"

    public static let storage = SettingsStore<ThemeGenerationSettings>(key: key) { ThemeGenerationSettings.default }

    public static func load() -> ThemeGenerationSettings { storage.load() }

    public static func save(_ settings: ThemeGenerationSettings) { storage.save(settings) }
}

extension ThemeGenerationSettings: StoredSettingsModel {
    public static var store: SettingsStore<ThemeGenerationSettings> { ThemeGenerationSettingsStore.storage }
}
