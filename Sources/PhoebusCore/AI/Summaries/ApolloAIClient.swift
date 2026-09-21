import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Apollo-Reborn's "Apollo AI" post/thread summarization. Follows
/// `ThemeGenerationClient`'s networking and key-storage pattern:
/// `URLSession` async calls, "Bearer <key>" auth for OpenAI-compatible
/// endpoints, `?key=<key>` auth for Gemini, and the principle of never
/// shipping or reusing Apollo's own API keys.
public enum ApolloAIClient {
    public enum AIError: Error, Sendable, LocalizedError {
        case notConfigured
        case invalidResponse
        /// Used on a build or OS without FoundationModels at all. Specific
        /// on-device failure reasons live in `OnDeviceSummarizer.SummarizationError`.
        case onDeviceUnavailable
        case customContractMismatch

        public var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Add an API key for this provider first."
            case .invalidResponse:
                return "The AI provider returned an unexpected response."
            case .onDeviceUnavailable:
                return "On-device summaries need iOS 26 or later. Choose a cloud provider instead."
            case .customContractMismatch:
                return "The custom endpoint's response didn't match the expected {\"summary\": \"...\"} or plain-text contract."
            }
        }
    }

    /// What is being summarized, which selects the prompt and token budget.
    /// Apollo uses separate instruction sets and response-token caps for posts
    /// and comments at three detail levels each; see `AISummaryPrompts`.
    public enum Target: Sendable {
        case post
        case comments
        /// A linked article alone.
        case article
        /// A post together with the article it links.
        case postAndLink

        func instructions(_ detail: AISummaryDetail) -> String {
            switch self {
            case .post: return AISummaryPrompts.postInstructions(detail)
            case .comments: return AISummaryPrompts.commentInstructions(detail)
            case .article: return AISummaryPrompts.articleInstructions(detail)
            case .postAndLink: return AISummaryPrompts.postAndLinkInstructions(detail)
            }
        }

        func responseTokens(_ detail: AISummaryDetail) -> Int {
            switch self {
            case .post: return AISummaryPrompts.postResponseTokens(detail)
            case .comments: return AISummaryPrompts.commentResponseTokens(detail)
            case .article: return AISummaryPrompts.articleResponseTokens(detail)
            case .postAndLink: return AISummaryPrompts.postAndLinkResponseTokens(detail)
            }
        }
    }

    /// Summarizes `text` (a post's selftext, optionally followed by a
    /// flattened excerpt of its top comments) using the provider
    /// configured in `settings`.
    ///
    /// `target` picks the per-detail prompt and token cap; defaults to `.post`.
    public static func summarize(text: String, settings: ApolloAISettings,
                                 target: Target = .post,
                                 session: URLSession = .shared) async throws -> String {
        // Export AI Logs: what was asked of which provider, and how it went.
        let started = Date()
        ApolloAILog.record("request \(target) provider=\(settings.provider.rawValue) model=\(settings.effectiveModel ?? "default") chars=\(text.count)")
        do {
            let summary = try await summarizeUnlogged(text: text, settings: settings, target: target, session: session)
            ApolloAILog.record(String(format: "done %@ in %.1fs (%d chars)", "\(target)", Date().timeIntervalSince(started), summary.count))
            return summary
        } catch {
            ApolloAILog.record("failed \(target): \((error as? LocalizedError)?.errorDescription ?? String(describing: error))")
            throw error
        }
    }

    private static func summarizeUnlogged(text: String, settings: ApolloAISettings,
                                          target: Target, session: URLSession) async throws -> String {
        let detail = target == .comments ? settings.commentDetail : settings.postDetail
        let instructions = target.instructions(detail)
        let maxTokens = target.responseTokens(detail)
        switch settings.provider {
        case .onDevice:
            // On-device generation via Apple's FoundationModels; see
            // `OnDeviceSummarizer` (permissive guardrails, no availability pre-gate,
            // one empty-response retry).
            return try await OnDeviceSummarizer.summarize(
                text: text,
                instructions: instructions,
                maximumResponseTokens: maxTokens
            )
        // Each cloud provider uses the model the user chose, falling
        // back to the provider's own default.
        case .openRouter:
            guard let apiKey = settings.openRouterAPIKey, !apiKey.isEmpty else { throw AIError.notConfigured }
            return try await summarizeViaOpenRouter(
                text: text, apiKey: apiKey,
                model: settings.effectiveModel ?? "openrouter/free",
                instructions: instructions, maxTokens: maxTokens, session: session)
        case .gemini:
            guard let apiKey = settings.geminiAPIKey, !apiKey.isEmpty else { throw AIError.notConfigured }
            return try await summarizeViaGemini(
                text: text, apiKey: apiKey,
                model: settings.effectiveModel ?? "gemini-3.6-flash",
                instructions: instructions, maxTokens: maxTokens, session: session)
        case .custom:
            // The custom provider needs a base URL plus a model, and
            // talks the same OpenAI chat-completions shape as the others.
            guard let baseURL = settings.customBaseURL, !baseURL.isEmpty,
                  let model = settings.effectiveModel, !model.isEmpty else {
                throw AIError.notConfigured
            }
            return try await summarizeViaOpenAICompatible(
                text: text, baseURL: baseURL, apiKey: settings.customAPIKey,
                model: model, instructions: instructions, maxTokens: maxTokens,
                session: session)
        }
    }

    /// OpenRouter is explicitly OpenAI-`/chat/completions`-API-compatible.
    private static func summarizeViaOpenRouter(text: String, apiKey: String,
                                               model: String, instructions: String,
                                               maxTokens: Int, session: URLSession) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": text],
            ],
            // Apollo bounds the reply per detail level; without this a
            // "Brief" summary could come back as five paragraphs.
            "max_tokens": maxTokens,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AIError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func summarizeViaGemini(text: String, apiKey: String,
                                           model: String, instructions: String,
                                           maxTokens: Int, session: URLSession) async throws -> String {
        // A bare model id may arrive with Google's own `models/`
        // prefix from the model browser, which the path already supplies.
        let modelID = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent?key=\(apiKey)") else {
            throw AIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "\(instructions)\n\nText to summarize:\n\(text)"]]],
            ],
            "generationConfig": ["maxOutputTokens": maxTokens],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AIError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let contentObj = candidates.first?["content"] as? [String: Any],
              let parts = contentObj["parts"] as? [[String: Any]],
              let responseText = parts.first?["text"] as? String else {
            throw AIError.invalidResponse
        }
        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The custom provider speaks OpenAI chat-completions: base URL
    /// plus `/chat/completions`, matching "Any OpenAI-compatible
    /// chat-completions service" in the settings screen.
    private static func summarizeViaOpenAICompatible(text: String, baseURL: String, apiKey: String?,
                                                     model: String, instructions: String,
                                                     maxTokens: Int, session: URLSession) async throws -> String {
        // `<base>/chat/completions`, tolerating a trailing slash.
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed + "/chat/completions") else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // Custom Headers only ever add to the request.
        for header in AICustomHeaders.load() {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": text],
            ],
            // Apollo bounds the reply per detail level; without this a
            // "Brief" summary could come back as five paragraphs.
            "max_tokens": maxTokens,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AIError.invalidResponse
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let plainText = String(data: data, encoding: .utf8), !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw AIError.customContractMismatch
    }
}
