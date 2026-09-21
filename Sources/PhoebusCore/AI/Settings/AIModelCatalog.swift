import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Apollo AI's live cloud model catalog.
///
/// Matches Apollo AI's model browser, including its endpoints, filters and
/// badges, all of which are editorial decisions with stated reasons.
public enum AIModelCatalog {
    public struct Model: Identifiable, Sendable, Equatable {
        public let id: String
        public let displayName: String
        /// "Free"/"Paid" for OpenRouter, a lifecycle tag for Gemini,
        /// or nil.
        public let badge: String?

        public init(id: String, displayName: String, badge: String?) {
            self.id = id
            self.displayName = displayName
            self.badge = badge
        }
    }

    /// Gemini is reached through its
    /// OpenAI-compatible catalog, not its native one.
    public static func endpoint(for provider: AIProvider) -> URL? {
        switch provider {
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/models")
        case .openRouter:
            // `/models/user`, not `/models`: the key's OWN list.
            return URL(string: "https://openrouter.ai/api/v1/models/user")
        case .onDevice, .custom:
            return nil
        }
    }

    /// Verbatim: matches Apollo AI's own text-chat classification.
    ///
    /// The `gemini-2.` exclusion is not tidiness and is worth keeping:
    /// "Gemini's OpenAI catalog currently includes 2.x IDs that new API
    /// projects receive a 404 for at generation time", so listing them
    /// would offer models that cannot work.
    public static func geminiModelLooksLikeTextChat(_ modelID: String) -> Bool {
        var lower = modelID.lowercased()
        if lower.hasPrefix("models/") { lower = String(lower.dropFirst(7)) }
        if lower.hasPrefix("gemini-2.") { return false }
        if !lower.hasPrefix("gemini-") && !lower.hasPrefix("gemma-") { return false }
        for needle in ["embedding", "image", "imagen", "veo", "lyria",
                       "tts", "live", "audio", "robotics", "computer-use"] {
            if lower.contains(needle) { return false }
        }
        return true
    }

    /// Verbatim and in order, matching Apollo AI's own Gemini badges.
    public static func geminiBadge(_ modelID: String) -> String? {
        let lower = modelID.lowercased()
        if lower.contains("experimental") || lower.contains("-exp-") || lower.hasSuffix("-exp") {
            return "Experimental"
        }
        if lower.contains("preview") { return "Preview" }
        if lower.hasSuffix("-latest") { return "Latest" }
        return nil
    }

    /// Verbatim, matching Apollo AI's own free-pricing rule.
    ///
    /// Every applicable charge must be zero, not just prompt and
    /// completion: "a zero prompt/completion price must not hide a
    /// per-request or reasoning charge". And a model with NO pricing
    /// block at all is not free, it is unknown - hence the final check
    /// that both required dimensions were actually present.
    public static func openRouterPricingIsFree(modelID: String,
                                               pricing: [String: Any]?) -> Bool {
        if modelID == "openrouter/free" || modelID.hasSuffix(":free") { return true }
        guard let pricing else { return false }
        for key in ["prompt", "completion", "request", "internal_reasoning"] {
            if let value = pricing[key], doubleValue(value) != 0 { return false }
        }
        return pricing["prompt"] != nil && pricing["completion"] != nil
    }

    private static func doubleValue(_ value: Any) -> Double {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    /// Verbatim: strips a
    /// trailing " (free)" because the badge already says so and the
    /// duplication "causes otherwise-short model names to truncate".
    public static func openRouterDisplayName(_ name: String) -> String {
        if name.lowercased().hasSuffix(" (free)") {
            return String(name.dropLast(" (free)".count))
        }
        return name
    }

    /// The footer under the list, which differs per provider,
    /// verbatim.
    public static func disclaimer(for provider: AIProvider) -> String {
        if provider == .openRouter {
            return "Free and Paid labels use OpenRouter\u{2019}s current live pricing. Free-model availability and rate limits can vary."
        }
        return "Google does not report per-model free-tier eligibility in its model catalog. Preview, Experimental, and Latest labels describe model lifecycle only."
    }

    public enum CatalogError: LocalizedError {
        case missingKey
        case http(Int)
        case invalidResponse
        case empty

        public var errorDescription: String? {
            switch self {
            case .missingKey: return "Enter an API key before browsing models."
            case .http(let code): return "Provider returned HTTP \(code)"
            case .invalidResponse: return "The provider returned an invalid response."
            case .empty: return "No compatible text models are available for this key."
            }
        }
    }

    /// Loads the key's own model list.
    ///
    /// OpenRouter's result is re-ordered so free models lead.
    public static func load(provider: AIProvider, apiKey: String,
                            session: URLSession = .shared) async throws -> [Model] {
        guard !apiKey.isEmpty else { throw CatalogError.missingKey }
        guard let url = endpoint(for: provider) else { throw CatalogError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.http(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["data"] as? [[String: Any]] else {
            throw CatalogError.invalidResponse
        }

        var models: [Model] = []
        for entry in raw {
            guard var modelID = entry["id"] as? String, !modelID.isEmpty else { continue }
            var badge: String?

            if provider == .gemini {
                guard geminiModelLooksLikeTextChat(modelID) else { continue }
                // The stored id drops Google's `models/` prefix.
                if modelID.hasPrefix("models/") { modelID = String(modelID.dropFirst(7)) }
                badge = geminiBadge(modelID)
            } else if provider == .openRouter {
                // Text-out only: a model that cannot emit text cannot
                // summarise.
                if let architecture = entry["architecture"] as? [String: Any],
                   let outputs = architecture["output_modalities"] as? [String],
                   !outputs.contains("text") {
                    continue
                }
                badge = openRouterPricingIsFree(
                    modelID: modelID, pricing: entry["pricing"] as? [String: Any]) ? "Free" : "Paid"
            }

            var name = entry["name"] as? String ?? ""
            if name.isEmpty { name = entry["display_name"] as? String ?? "" }
            if name.isEmpty { name = modelID }
            if provider == .openRouter { name = openRouterDisplayName(name) }

            models.append(Model(id: modelID, displayName: name, badge: badge))
        }

        if provider == .openRouter {
            models = models.filter { $0.badge == "Free" } + models.filter { $0.badge != "Free" }
        }
        guard !models.isEmpty else { throw CatalogError.empty }
        return models
    }
}

/// Apollo AI's own diagnostics, for "Export Apollo AI Logs".
///
/// The AI-specific Reborn diagnostics from the current app session, so
/// this is deliberately in-memory and session-scoped rather than persisted.
public enum ApolloAILog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: [String] = []
    /// Bounded, so a long session cannot grow without limit.
    private static let limit = 500

    public static func record(_ message: String) {
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(message)"
        lock.lock()
        defer { lock.unlock() }
        storage.append(stamped)
        if storage.count > limit { storage.removeFirst(storage.count - limit) }
    }

    public static var entries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public static func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

/// Generated summaries, kept for seven days as Reborn does, so reopening
/// a thread doesn't pay for the same summary again. Backs "Clear AI
/// Cache".
///
/// Clearing returns how many entries it removed, which the confirmation
/// reports ("Removed 1 cached summary" / "Removed N cached summaries").
public enum AISummaryCache {
    private static let prefix = "com.pendo324.Phoebus.aiSummary."
    public static let lifetime: TimeInterval = 7 * 24 * 60 * 60

    public static func key(for identifier: String) -> String { prefix + identifier }

    public static func store(_ summary: String, for identifier: String,
                             in defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(["text": summary, "at": now.timeIntervalSince1970], forKey: key(for: identifier))
    }

    public static func summary(for identifier: String,
                               in defaults: UserDefaults = .standard, now: Date = Date()) -> String? {
        guard let entry = defaults.dictionary(forKey: key(for: identifier)),
              let text = entry["text"] as? String,
              let at = entry["at"] as? TimeInterval else { return nil }
        guard now.timeIntervalSince1970 - at < lifetime else {
            defaults.removeObject(forKey: key(for: identifier))
            return nil
        }
        return text
    }

    /// - Returns: the number of cached summaries removed.
    @discardableResult
    public static func clear(in defaults: UserDefaults = .standard) -> Int {
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in keys { defaults.removeObject(forKey: key) }
        return keys.count
    }
}
