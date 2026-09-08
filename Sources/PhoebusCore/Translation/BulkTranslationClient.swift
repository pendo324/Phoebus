import Foundation
#if canImport(Translation)
import Translation
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for Apollo-Reborn's bulk translation: Google, LibreTranslate,
/// Microsoft Translator and Apple's on-device Translation (`apple`
/// provider), with a cross-provider fallback on request failure.
public enum BulkTranslationClient {
    public enum ClientError: Error, Sendable {
        case invalidResponse
        case emptyText
        case notConfigured
        /// Maps Azure error statuses (401/403/429).
        case providerError(message: String, isQuota: Bool)
    }

    public static func translate(text: String, to targetLanguageCode: String, settings: TranslationSettings, session: URLSession = .shared) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.emptyText }
        let primary = settings.provider
        do {
            return try await translate(text: text, to: targetLanguageCode, via: primary, settings: settings, session: session)
        } catch {
            // Apple stays Apple; the others retry once elsewhere.
            guard let other = fallbackProvider(after: primary, settings: settings) else { throw error }
            do {
                return try await translate(text: text, to: targetLanguageCode, via: other, settings: settings, session: session)
            } catch let fallbackError {
                throw ClientError.providerError(
                    message: "\(describe(error)) · \(describe(fallbackError))",
                    isQuota: isQuota(error) || isQuota(fallbackError))
            }
        }
    }

    /// Reborn's chooser: a Microsoft key first, being the most reliable,
    /// else Google, else a usable LibreTranslate.
    public static func fallbackProvider(after primary: TranslationProvider, settings: TranslationSettings) -> TranslationProvider? {
        if primary == .apple { return nil }
        if primary != .microsoft, !(settings.microsoftAPIKey ?? "").isEmpty { return .microsoft }
        if primary != .google { return .google }
        if !settings.libreTranslateNeedsAPIKey { return .libreTranslate }
        return nil
    }

    private static func describe(_ error: Error) -> String {
        if case ClientError.providerError(let message, _) = error { return message }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private static func isQuota(_ error: Error) -> Bool {
        if case ClientError.providerError(_, let quota) = error { return quota }
        return false
    }

    private static func translate(text: String, to targetLanguageCode: String, via provider: TranslationProvider,
                                  settings: TranslationSettings, session: URLSession) async throws -> String {
        switch provider {
        case .apple:
            return try await translateViaApple(text: text, to: targetLanguageCode)
        case .libreTranslate:
            return try await translateViaLibreTranslate(text: text, to: targetLanguageCode, settings: settings, session: session)
        case .google:
            return try await translateViaGoogle(text: text, to: targetLanguageCode, session: session)
        case .microsoft:
            return try await translateViaMicrosoft(text: text, to: targetLanguageCode, settings: settings, session: session)
        }
    }

    /// LibreTranslate's public POST API, self-hostable. Uses the current
    /// default (`libretranslate.com`) via `settings.normalizedLibreTranslateURL`.
    private static func translateViaLibreTranslate(text: String, to targetLanguageCode: String, settings: TranslationSettings, session: URLSession) async throws -> String {
        guard let url = URL(string: settings.normalizedLibreTranslateURL) else { throw ClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "q": text,
            "source": "auto",
            "target": targetLanguageCode.isEmpty ? deviceLanguageCode() : targetLanguageCode,
            "format": "text",
        ]
        if let apiKey = settings.libreTranslateAPIKey, !apiKey.isEmpty {
            body["api_key"] = apiKey
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translated = json["translatedText"] as? String else {
            throw ClientError.invalidResponse
        }
        return translated
    }

    /// Google's public (keyless, undocumented) `translate.googleapis.com`
    /// single-text endpoint, Reborn's default provider.
    private static func translateViaGoogle(text: String, to targetLanguageCode: String, session: URLSession) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: targetLanguageCode.isEmpty ? deviceLanguageCode() : targetLanguageCode),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components.url else { throw ClientError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidResponse
        }
        if let source = parseGoogleSourceLanguage(data) {
            recordDetected(source, for: text)
        }
        return try parseGoogleResponse(data)
    }

    /// Google's response is a deeply-nested untyped JSON array:
    /// `[[[translatedChunk, originalChunk, ...], ...], ...]` — this
    /// concatenates every translated chunk in the first sub-array.
    /// Google's detected source language (top-level index 2, e.g. "fr").
    /// Used for the "Translated from" marker on titles, where on-device
    /// detection of a few words is unreliable.
    public static func parseGoogleSourceLanguage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count > 2 else { return nil }
        return json[2] as? String
    }

    /// Last detected source language per translated text (Google only).
    nonisolated(unsafe) private static var detected: [String: String] = [:]
    private static let detectedLock = NSLock()

    private static func recordDetected(_ code: String, for text: String) {
        detectedLock.lock(); defer { detectedLock.unlock() }
        detected[text] = code
    }

    public static func detectedSourceLanguage(for text: String) -> String? {
        detectedLock.lock(); defer { detectedLock.unlock() }
        return detected[text]
    }

    public static func parseGoogleResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              let sentenceArray = json.first as? [Any] else {
            throw ClientError.invalidResponse
        }
        let chunks: [String] = sentenceArray.compactMap { entry in
            guard let pair = entry as? [Any], let chunk = pair.first as? String else { return nil }
            return chunk
        }
        guard !chunks.isEmpty else { throw ClientError.invalidResponse }
        return chunks.joined()
    }

    /// Microsoft Translator via Azure Cognitive Services:
    /// `POST api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=<lang>`,
    /// body `[{"Text": "<text>"}]`, `Ocp-Apim-Subscription-Key` header
    /// (required), optional `Ocp-Apim-Subscription-Region` header for
    /// regional resources. Response:
    /// `[{"translations": [{"text": "...", "to": "en"}]}]`.
    ///
    /// Azure keys some languages by dialect or script where Apollo (and
    /// Google/Apple) use a bare ISO 639-1 code. Bare `zh` and `no` are absent
    /// from /languages?scope=translation and the translate endpoint 400s on
    /// them, so they must be mapped. Anything unmapped passes through and, if
    /// Azure still rejects it, surfaces its own error.
    public static func microsoftTargetLanguageCode(_ code: String) -> String {
        switch code {
        case "zh": return "zh-Hans"   // Azure has only zh-Hans/zh-Hant
        case "no": return "nb"        // Azure uses Bokmål's code
        case "sr": return "sr-Cyrl"   // Cyrillic matches Google's output
        case "tl": return "fil"       // Azure files Tagalog under Filipino
        case "iw": return "he"        // legacy Hebrew code
        case "mn": return "mn-Cyrl"   // Azure splits Mongolian by script
        default: return code
        }
    }

    private static func translateViaMicrosoft(text: String, to targetLanguageCode: String, settings: TranslationSettings, session: URLSession) async throws -> String {
        guard let apiKey = settings.microsoftAPIKey, !apiKey.isEmpty else {
            throw ClientError.notConfigured
        }
        var components = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: microsoftTargetLanguageCode(
                targetLanguageCode.isEmpty ? deviceLanguageCode() : targetLanguageCode)),
        ]
        guard let url = components.url else { throw ClientError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        if let region = settings.microsoftRegion, !region.isEmpty {
            request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw microsoftError(forStatus: httpResponse.statusCode, data: data)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let translations = json.first?["translations"] as? [[String: Any]],
              let translated = translations.first?["text"] as? String else {
            throw ClientError.invalidResponse
        }
        return translated
    }

    /// Azure status-code-to-message mapping.
    private static func microsoftError(forStatus status: Int, data: Data) -> ClientError {
        var azureMessage: String?
        if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorNode = errorBody["error"] as? [String: Any],
           let message = errorNode["message"] as? String {
            azureMessage = message
        }
        switch status {
        case 401:
            return .providerError(message: "Microsoft Translator rejected your API key — check it in Translation settings", isQuota: false)
        case 403:
            return .providerError(message: "Microsoft Translator quota exhausted — the free tier resets at the start of each month", isQuota: true)
        case 429:
            return .providerError(message: "Microsoft Translator is rate limiting — too many requests at once", isQuota: true)
        default:
            let message = azureMessage.map { "Microsoft Translator: \($0)" } ?? "Microsoft Translator request failed (HTTP \(status))"
            return .providerError(message: message, isQuota: false)
        }
    }

    /// Whether Apple's provider can run: a headless session needs iOS 26.
    public static var appleTranslationAvailable: Bool {
        #if canImport(Translation) && os(iOS)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Apple on-device. The source is detected here and passed explicitly,
    /// as Reborn does: Apple's own auto-detect can stall on a language
    /// picker. Text whose language can't be told is left alone.
    private static func translateViaApple(text: String, to targetLanguageCode: String) async throws -> String {
        #if canImport(Translation) && canImport(NaturalLanguage) && os(iOS)
        if #available(iOS 26.0, *) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            guard let detected = recognizer.dominantLanguage,
                  (recognizer.languageHypotheses(withMaximum: 1)[detected] ?? 0) >= 0.5 else {
                throw ClientError.providerError(message: "Couldn't tell which language this is.", isQuota: false)
            }
            let target = targetLanguageCode.isEmpty ? deviceLanguageCode() : targetLanguageCode
            let source = Locale.Language(identifier: detected.rawValue)
            let destination = Locale.Language(identifier: target)
            if source.languageCode == destination.languageCode { return text }
            let translator = TranslationSession(installedSource: source, target: destination)
            let response = try await translator.translate(text)
            recordDetected(detected.rawValue, for: text)
            return response.targetText
        }
        #endif
        throw ClientError.notConfigured
    }

    private static func deviceLanguageCode() -> String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }
}
