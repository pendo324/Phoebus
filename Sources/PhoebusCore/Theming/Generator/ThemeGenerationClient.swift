import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Calls the user's configured LLM provider to generate a `Theme` from a
/// natural-language description (Reborn's AI theme generation).
///
/// Asking a model for raw hex codes maps topics to wildly wrong hues, so
/// the prompt asks it to **name** each color first, which anchors the hex
/// to something semantically correct ("spiderman" -> red/blue). The prompt
/// never includes a literal example reply, since models parrot its hex
/// codes back for every topic. The response is a single-request JSON, not
/// Reborn's name-then-hex reply with an on-device palette-derivation engine.
public enum ThemeGenerationClient {
    public enum ClientError: Error, Sendable {
        case notConfigured
        case invalidResponse
        case invalidThemeJSON
    }

    private static let systemPrompt = """
    You generate color themes for a Reddit client app. Given a short \
    description, first think of the three colors most iconic to that \
    description — naming each one before its hex code helps you land \
    on the semantically correct hue family (for example, a red/blue \
    superhero theme should map to actual red and blue, not an \
    unrelated hue). Then respond with ONLY a JSON object (no markdown \
    fences, no extra text, no literal example values) of the exact form:
    {"name": "Theme Name", "accentColorHex": "RRGGBB", "commentDepthColorHexes": ["RRGGBB", "RRGGBB", "RRGGBB", "RRGGBB", "RRGGBB"]}
    All hex values are 6-character RGB hex strings with no leading #. \
    Provide exactly 5 comment depth colors that are visually distinct \
    from each other and complement the accent color.
    """

    public static func generateTheme(description: String, isDark: Bool, settings: ThemeGenerationSettings = ThemeGenerationSettingsStore.load(), session: URLSession = .shared) async throws -> Theme {
        guard let apiKey = settings.apiKey, !apiKey.isEmpty else { throw ClientError.notConfigured }
        let content = try await requestCompletion(description: description, settings: settings, apiKey: apiKey, session: session)
        return try parseThemeJSON(content, isDark: isDark)
    }

    private static func requestCompletion(description: String, settings: ThemeGenerationSettings, apiKey: String, session: URLSession) async throws -> String {
        switch settings.provider {
        case .openAI, .openRouter:
            return try await requestOpenAICompatible(description: description, settings: settings, apiKey: apiKey, session: session)
        case .gemini:
            return try await requestGemini(description: description, settings: settings, apiKey: apiKey, session: session)
        }
    }

    /// Both OpenAI and OpenRouter speak the same `/chat/completions`
    /// request/response shape (OpenRouter is explicitly OpenAI-API-
    /// compatible), so one implementation covers both, differing only
    /// in base URL.
    private static func requestOpenAICompatible(description: String, settings: ThemeGenerationSettings, apiKey: String, session: URLSession) async throws -> String {
        let baseURL = settings.provider == .openRouter ? "https://openrouter.ai/api/v1/chat/completions" : "https://api.openai.com/v1/chat/completions"
        guard let url = URL(string: baseURL) else { throw ClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": description],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ClientError.invalidResponse
        }
        return content
    }

    private static func requestGemini(description: String, settings: ThemeGenerationSettings, apiKey: String, session: URLSession) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(settings.model):generateContent?key=\(apiKey)") else {
            throw ClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "\(systemPrompt)\n\nDescription: \(description)"]]],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let contentObj = candidates.first?["content"] as? [String: Any],
              let parts = contentObj["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw ClientError.invalidResponse
        }
        return text
    }

    /// Parses the model's JSON theme response, tolerating markdown
    /// code fences some models wrap JSON in despite instructions not
    /// to. Separated out so it's testable without any network call.
    public static func parseThemeJSON(_ content: String, isDark: Bool) throws -> Theme {
        var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
            trimmed = trimmed.replacingOccurrences(of: "```", with: "")
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let accentColorHex = json["accentColorHex"] as? String,
              let commentDepthColorHexes = json["commentDepthColorHexes"] as? [String],
              !commentDepthColorHexes.isEmpty else {
            throw ClientError.invalidThemeJSON
        }
        let id = "generated_\(UUID().uuidString.prefix(8))"
        return Theme(id: id, name: name, accentColorHex: sanitizeHex(accentColorHex), commentDepthColorHexes: commentDepthColorHexes.map(sanitizeHex), isDark: isDark, isGenerated: true)
    }

    private static func sanitizeHex(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").uppercased()
    }
}
