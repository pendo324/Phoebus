import Foundation

/// Apollo-Reborn's "Apollo AI" settings: five sections, fourteen rows. Every
/// persisted key is Reborn's own string, so a device that used Reborn keeps
/// its settings.

/// The four backends, in the picker's order. Raw values are Reborn's persisted
/// strings: the on-device case persists as `"apple"`, not `"onDevice"`.
public enum AIProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case onDevice = "apple"
    case openRouter = "openrouter"
    case gemini = "gemini"
    case custom = "custom"

    public var id: String { rawValue }

    /// Also decodes legacy spellings. `ApolloAISettings` is stored as one JSON
    /// blob, so a single unknown raw value would otherwise throw out of
    /// `init(from:)` and reset every AI setting to `.default`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "apple", "onDevice", "on-device", "ondevice": self = .onDevice
        case "openrouter", "openRouter": self = .openRouter
        case "gemini": self = .gemini
        case "custom": self = .custom
        default:
            // An unrecognised provider falls back to on-device rather than
            // throwing, so one unknown string cannot discard the other settings.
            self = .onDevice
        }
    }

    /// The picker's provider display names.
    public var displayName: String {
        switch self {
        case .onDevice: return "Apple On-Device"
        case .openRouter: return "OpenRouter"
        case .gemini: return "Google Gemini"
        case .custom: return "Custom"
        }
    }

    /// Anything that is not Apple's on-device model posts text to a
    /// third party.
    public var isCloud: Bool { self != .onDevice }

    /// Provider-maintained/current model targets, not pinned free
    /// variants. `custom` has none by design: the user must name a
    /// model.
    public var defaultModel: String? {
        switch self {
        case .openRouter: return "openrouter/free"
        case .gemini: return "gemini-3.6-flash"
        case .onDevice, .custom: return nil
        }
    }

    /// Only these two can list their models live.
    public var supportsModelBrowsing: Bool {
        self == .openRouter || self == .gemini
    }
}

/// How much detail a summary carries.
///
/// Raw values are the stored integers, so the slider index IS the
/// enum value.
public enum AISummaryDetail: Int, Codable, Sendable, CaseIterable, Identifiable {
    case brief = 0
    case balanced = 1
    case inDepth = 2

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .brief: return "Brief"
        case .balanced: return "Balanced"
        case .inDepth: return "In-depth"
        }
    }
}

/// The three mutually-exclusive ways summaries appear when a thread
/// The three mutually-exclusive ways summaries appear when a thread opens.
/// One three-way picker, persisted to two booleans:
///
///     Generate on Open   -> tap = NO,  autoExpand = NO
///     Open Automatically -> tap = NO,  autoExpand = YES
///     Tap to Summarize   -> tap = YES, autoExpand = NO
public enum AISummaryMode: Int, Codable, Sendable, CaseIterable, Identifiable {
    case generateOnOpen = 0
    case openAutomatically = 1
    case tapToSummarize = 2

    public var id: Int { rawValue }

    /// The picker's row titles.
    public var displayName: String {
        switch self {
        case .generateOnOpen: return "Generate on Open"
        case .openAutomatically: return "Open Automatically"
        case .tapToSummarize: return "Tap to Summarize"
        }
    }

    /// Tap wins over auto-expand.
    public static func from(tapToSummarize: Bool, autoExpand: Bool) -> AISummaryMode {
        if tapToSummarize { return .tapToSummarize }
        if autoExpand { return .openAutomatically }
        return .generateOnOpen
    }

    public var tapToSummarize: Bool { self == .tapToSummarize }
    public var autoExpand: Bool { self == .openAutomatically }
}

public struct ApolloAISettings: Codable, Sendable, Equatable {
    /// `UDKeyEnableAISummaries`. "Off by default."
    public var summariesEnabled: Bool
    /// `UDKeyEnableAIPostSummaries`. "Both default ON, so turning the
    /// master on keeps the original behaviour."
    public var postSummariesEnabled: Bool
    /// `UDKeyEnableAICommentSummaries`. Also defaults ON.
    public var commentSummariesEnabled: Bool
    /// 50...300 in 50-word steps, default 150. Applies to text posts
    /// only; linked articles remain eligible regardless.
    public var postWordThreshold: Int
    /// `UDKeyAIPostSummaryDetail`.
    public var postDetail: AISummaryDetail
    /// `UDKeyAICommentSummaryDetail`.
    public var commentDetail: AISummaryDetail
    /// Persisted as `UDKeyEnableTapToSummarize` +
    /// `UDKeyEnableAIAutoExpandSummaries`, never as one value.
    public var summaryMode: AISummaryMode
    /// `UDKeyAISummaryProvider`.
    public var provider: AIProvider

    /// Per-provider keys and models. Stored separately so switching
    /// back and forth never loses them.
    public var openRouterAPIKey: String?
    public var openRouterModel: String?
    public var geminiAPIKey: String?
    public var geminiModel: String?
    public var customAPIKey: String?
    public var customModel: String?
    /// The only field shared across providers.
    public var customBaseURL: String?

    /// The real word-threshold detents.
    public static let wordThresholds = [50, 100, 150, 200, 250, 300]

    public static let `default` = ApolloAISettings(
        summariesEnabled: false,
        postSummariesEnabled: true,
        commentSummariesEnabled: true,
        postWordThreshold: 150,
        postDetail: .balanced,
        commentDetail: .balanced,
        summaryMode: .generateOnOpen,
        provider: .onDevice
    )

    public init(
        summariesEnabled: Bool,
        postSummariesEnabled: Bool = true,
        commentSummariesEnabled: Bool = true,
        postWordThreshold: Int = 150,
        postDetail: AISummaryDetail = .balanced,
        commentDetail: AISummaryDetail = .balanced,
        summaryMode: AISummaryMode = .generateOnOpen,
        provider: AIProvider,
        openRouterAPIKey: String? = nil,
        openRouterModel: String? = nil,
        geminiAPIKey: String? = nil,
        geminiModel: String? = nil,
        customAPIKey: String? = nil,
        customModel: String? = nil,
        customBaseURL: String? = nil
    ) {
        self.summariesEnabled = summariesEnabled
        self.postSummariesEnabled = postSummariesEnabled
        self.commentSummariesEnabled = commentSummariesEnabled
        self.postWordThreshold = postWordThreshold
        self.postDetail = postDetail
        self.commentDetail = commentDetail
        self.summaryMode = summaryMode
        self.provider = provider
        self.openRouterAPIKey = openRouterAPIKey
        self.openRouterModel = openRouterModel
        self.geminiAPIKey = geminiAPIKey
        self.geminiModel = geminiModel
        self.customAPIKey = customAPIKey
        self.customModel = customModel
        self.customBaseURL = customBaseURL
    }

    /// The active provider's stored key.
    public var activeAPIKey: String? {
        switch provider {
        case .openRouter: return openRouterAPIKey
        case .gemini: return geminiAPIKey
        case .custom: return customAPIKey
        case .onDevice: return nil
        }
    }

    /// The active provider's stored model.
    public var activeModel: String? {
        switch provider {
        case .openRouter: return openRouterModel
        case .gemini: return geminiModel
        case .custom: return customModel
        case .onDevice: return nil
        }
    }

    /// The stored model, else the provider's default.
    public var effectiveModel: String? {
        if let stored = activeModel, !stored.isEmpty { return stored }
        return provider.defaultModel
    }

    /// Cloud availability diagnostic text, in order.
    public var cloudAvailability: String {
        guard (activeAPIKey?.isEmpty == false) else { return "API Key Required" }
        if provider == .custom {
            if customBaseURL?.isEmpty != false { return "Base URL Required" }
            if effectiveModel?.isEmpty != false { return "Model Required" }
        }
        return "Ready"
    }

    /// The General section's footer, which changes with the provider.
    public var generalFooter: String {
        if provider.isCloud {
            return "Summaries are generated by \(provider.displayName) using your API key — post and comment text (and fetched article text) is sent to that service. Your key is stored in Phoebus's settings on this device, and is included in settings backups."
        }
        return "Summaries are generated entirely on-device using Apple Intelligence — no post or comment text is sent to an external AI service. Summarizing a linked article does fetch that page from its source website, which happens automatically when you open a thread unless Tap to Summarize is on."
    }

    /// The Provider section's footer.
    public var providerFooter: String {
        switch provider {
        case .custom:
            return "Any OpenAI-compatible chat-completions service: enter its base URL (e.g. https://api.example.com/v1), an API key, and a model ID."
        case .openRouter, .gemini:
            return "Leave Model empty to use the suggested default. Cloud providers work on any iPhone — no Apple Intelligence required."
        case .onDevice:
            return "Apple On-Device requires an Apple Intelligence-capable device on iOS 26 or later. Choose a cloud provider with your own API key to get summaries on any iPhone."
        }
    }

    /// The Availability section's footer. The on-device string's
    /// second sentence is the same sideloading caveat
    /// `OnDeviceSummarizer` already acts on.
    public var availabilityFooter: String {
        provider.isCloud
            ? "Availability is diagnostic. Ready means the provider is configured; the API key itself is only verified when a summary is generated."
            : "Availability is diagnostic. On some iOS versions, sideloaded apps may report Apple Intelligence as disabled even when generation still works."
    }

    /// The Summaries section's footer, including its blank line.
    public static let summariesFooter = "Minimum Post Length only applies to text posts, not linked articles. Brief, Balanced and In-depth set how much detail a summary goes into.\n\nWhen Opening a Thread: Generate on Open prepares summaries in the background and keeps them collapsed until you tap. Open Automatically expands them on their own. Tap to Summarize only starts when you tap a summary card."

    /// The Maintenance section's footer.
    public static let maintenanceFooter = "Clearing the cache removes saved summaries and extracted article text. Phoebus AI logs contain only AI-specific Reborn diagnostics from the current app session."

    /// Decoding tolerates settings written before any field existed, so
    /// an older payload keeps working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ApolloAISettings.default
        summariesEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .summariesEnabled))
            ?? fallback.summariesEnabled
        postSummariesEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .postSummariesEnabled))
            ?? fallback.postSummariesEnabled
        commentSummariesEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .commentSummariesEnabled))
            ?? fallback.commentSummariesEnabled
        postWordThreshold = (try? container.decodeIfPresent(Int.self, forKey: .postWordThreshold))
            ?? fallback.postWordThreshold
        // `try?` on the enum-valued keys: an out-of-range stored value
        // must lose that one field, never the whole blob.
        postDetail = (try? container.decodeIfPresent(AISummaryDetail.self, forKey: .postDetail))
            .flatMap { $0 } ?? fallback.postDetail
        commentDetail = (try? container.decodeIfPresent(AISummaryDetail.self, forKey: .commentDetail))
            .flatMap { $0 } ?? fallback.commentDetail
        summaryMode = (try? container.decodeIfPresent(AISummaryMode.self, forKey: .summaryMode))
            .flatMap { $0 } ?? fallback.summaryMode
        provider = (try? container.decodeIfPresent(AIProvider.self, forKey: .provider))
            ?? fallback.provider
        openRouterAPIKey = (try? container.decodeIfPresent(String.self, forKey: .openRouterAPIKey))
        openRouterModel = (try? container.decodeIfPresent(String.self, forKey: .openRouterModel))
        geminiAPIKey = (try? container.decodeIfPresent(String.self, forKey: .geminiAPIKey))
        geminiModel = (try? container.decodeIfPresent(String.self, forKey: .geminiModel))
        customAPIKey = (try? container.decodeIfPresent(String.self, forKey: .customAPIKey))
        customModel = (try? container.decodeIfPresent(String.self, forKey: .customModel))
        // Also accepts the legacy key `customEndpointURL`.
        customBaseURL = (try? container.decodeIfPresent(String.self, forKey: .customBaseURL))
            ?? (try? container.decodeIfPresent(String.self, forKey: .customEndpointURL)) ?? nil
    }

    /// Explicit, because the legacy `customEndpointURL` key exists for
    /// DECODING only - synthesising `encode` would write it back out.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summariesEnabled, forKey: .summariesEnabled)
        try container.encode(postSummariesEnabled, forKey: .postSummariesEnabled)
        try container.encode(commentSummariesEnabled, forKey: .commentSummariesEnabled)
        try container.encode(postWordThreshold, forKey: .postWordThreshold)
        try container.encode(postDetail, forKey: .postDetail)
        try container.encode(commentDetail, forKey: .commentDetail)
        try container.encode(summaryMode, forKey: .summaryMode)
        try container.encode(provider, forKey: .provider)
        try container.encodeIfPresent(openRouterAPIKey, forKey: .openRouterAPIKey)
        try container.encodeIfPresent(openRouterModel, forKey: .openRouterModel)
        try container.encodeIfPresent(geminiAPIKey, forKey: .geminiAPIKey)
        try container.encodeIfPresent(geminiModel, forKey: .geminiModel)
        try container.encodeIfPresent(customAPIKey, forKey: .customAPIKey)
        try container.encodeIfPresent(customModel, forKey: .customModel)
        try container.encodeIfPresent(customBaseURL, forKey: .customBaseURL)
    }

    enum CodingKeys: String, CodingKey {
        case summariesEnabled, postSummariesEnabled, commentSummariesEnabled
        case postWordThreshold, postDetail, commentDetail, summaryMode, provider
        case openRouterAPIKey, openRouterModel, geminiAPIKey, geminiModel
        case customAPIKey, customModel, customBaseURL
        case customEndpointURL
    }

    /// The Apollo Reborn hub row's subtitle. The hub uses its own
    /// provider names here, distinct from the picker's ("On-device AI"
    /// vs "Apple On-Device", etc.).
    public var summaryText: String {
        guard summariesEnabled else {
            return "On-device or cloud summaries and generation settings"
        }
        return "\(hubProviderName) enabled"
    }

    /// The hub's own name for the active provider - see `summaryText`.
    public var hubProviderName: String {
        switch provider {
        case .onDevice: return "On-device AI"
        case .openRouter: return "OpenRouter AI"
        case .gemini: return "Gemini AI"
        case .custom: return "Custom cloud AI"
        }
    }
}

public enum ApolloAISettingsStore {
    private static let key = "com.pendo324.Phoebus.apolloAISettings"

    public static let storage = SettingsStore<ApolloAISettings>(key: key) { ApolloAISettings.default }

    public static func load() -> ApolloAISettings { storage.load() }

    public static func save(_ settings: ApolloAISettings) { storage.save(settings) }
}

/// The detent slider's snapping rule, split out so it can be tested
/// without SwiftUI. Ported from the tweak's hysteretic-index math: the
/// 0.65 threshold widens the dead band past normal fingertip jitter,
/// unlike a plain `round()` which snaps at 0.5 and flickers.
public enum ApolloAIDetentSliderMath {
    public static let hysteresis: Float = 0.65

    public static func hystereticIndex(raw: Float, current: Int,
                                       minimum: Int, maximum: Int) -> Int {
        var current = max(minimum, min(current, maximum))
        while current < maximum && raw > Float(current) + hysteresis { current += 1 }
        while current > minimum && raw < Float(current) - hysteresis { current -= 1 }
        return current
    }
}

extension ApolloAISettings: StoredSettingsModel {
    public static var store: SettingsStore<ApolloAISettings> { ApolloAISettingsStore.storage }
}

/// "Custom Headers" for the custom AI provider (Reborn's `CustomAIHeaders`):
/// extra HTTP headers added to every request, as `[{name, value}]` in the
/// order added. Reserved and malformed headers are refused when entered and
/// dropped when read.
public enum AICustomHeaders {
    public static let defaultsKey = "CustomAIHeaders"

    public struct Header: Equatable, Sendable {
        public var name: String
        public var value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }

    static let reserved: Set<String> = [
        "authorization", "content-type", "content-length", "content-encoding", "accept", "accept-encoding",
        "connection", "host", "proxy-authenticate", "proxy-authorization", "www-authenticate",
        "keep-alive", "proxy-connection", "te", "transfer-encoding", "upgrade",
    ]

    /// Why a header can't be used, in Reborn's words; nil when it can.
    public static func problem(name: String, value: String) -> String? {
        if name.isEmpty { return "Enter a header name." }
        if name.contains(":") { return "Enter the name without a colon, and its value in the Value field." }
        let token = Set("!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        if !name.allSatisfy({ token.contains($0) }) {
            return "Header names can't contain spaces, quotes or symbols like ( ) , / ; = ? @ [ ] { }."
        }
        if reserved.contains(name.lowercased()) {
            return name.caseInsensitiveCompare("Authorization") == .orderedSame
                ? "Phoebus already sends your API key as the Authorization header."
                : "\(name) can't be set as a custom header."
        }
        if value.isEmpty { return "Enter a value for this header." }
        if !value.unicodeScalars.allSatisfy({ $0 == "\t" || (0x20..<0x7F).contains($0.value) }) {
            return "Header values must be plain text, with no line breaks, emoji or curly quotes."
        }
        return nil
    }

    /// Valid entries only, first of each name (case-insensitive) kept.
    public static func sanitized(_ stored: Any?) -> [Header] {
        guard let entries = stored as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        var out: [Header] = []
        for entry in entries {
            guard let rawName = entry["name"] as? String, let rawValue = entry["value"] as? String else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard problem(name: name, value: value) == nil, seen.insert(name.lowercased()).inserted else { continue }
            out.append(Header(name: name, value: value))
        }
        return out
    }

    public static func load(_ defaults: UserDefaults = .standard) -> [Header] {
        sanitized(defaults.object(forKey: defaultsKey))
    }

    public static func save(_ headers: [Header], _ defaults: UserDefaults = .standard) {
        if headers.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(headers.map { ["name": $0.name, "value": $0.value] }, forKey: defaultsKey)
        }
    }
}
