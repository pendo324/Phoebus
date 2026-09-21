import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device summarization via FoundationModels, the default
/// `AIProvider.onDevice` (Reborn's implicit else branch).
///
/// 1. Uses `.permissiveContentTransformations`: the default guardrail
///    false-positives on ordinary news/political Reddit threads.
/// 2. Does not pre-gate on `availability`, which can report
///    `.appleIntelligenceNotEnabled` to sideloaded apps even when the
///    model works; only a thrown error stops generation.
/// 3. Retries once on an empty response with a fresh session.
///
/// The model is cached (building it re-prepares guardrail assets) and
/// sessions are single-use so threads never share transcript context.
/// The `#if canImport(FoundationModels)` guards keep the Linux smoke
/// build compiling.
public enum OnDeviceSummarizer {

    /// Why on-device summarization cannot run, when it cannot.
    public enum Availability: Equatable, Sendable {
        case available
        /// The user has not turned on Apple Intelligence.
        case appleIntelligenceNotEnabled
        /// Model assets are still downloading.
        case modelNotReady
        /// The hardware cannot run it.
        case deviceNotEligible
        /// Built against, or running on, an OS without the framework.
        case osTooOld
        case unknown

        public var explanation: String {
            switch self {
            case .available:
                return "On-device AI is ready."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to use on-device summaries."
            case .modelNotReady:
                return "Apple Intelligence is still downloading its model. Try again shortly."
            case .deviceNotEligible:
                return "This device can't run Apple's on-device model. Choose a cloud provider instead."
            case .osTooOld:
                return "On-device summaries need iOS 26 or later. Choose a cloud provider instead."
            case .unknown:
                return "On-device AI isn't available right now."
            }
        }
    }

    /// Surfaced for diagnostics and for the settings screen's readout.
    ///
    /// Deliberately NOT used to gate `summarize` - see decision 2 in
    /// this type's doc comment.
    public static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
                case .modelNotReady: return .modelNotReady
                case .deviceNotEligible: return .deviceNotEligible
                @unknown default: return .unknown
                }
            @unknown default:
                return .unknown
            }
        }
        #endif
        return .osTooOld
    }

    /// True when the framework is compiled in AND the OS is new enough.
    ///
    /// Separate from `availability`: this answers "can this build call
    /// the API at all", which is what decides whether the on-device
    /// provider is offered, while `availability` answers "would it work
    /// right now".
    public static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    #if canImport(FoundationModels)
    /// Built once: constructing it re-prepares guardrail assets.
    @available(iOS 26.0, *)
    private static let cachedModel = SystemLanguageModel(
        guardrails: .permissiveContentTransformations
    )
    #endif

    /// Summarizes `text` with `instructions` as the system prompt.
    ///
    /// - Parameter onPartial: called with the cumulative text as it
    ///   streams, so a caller can render progressively. Optional
    ///   because the non-streaming callers just await the result.
    public static func summarize(
        text: String,
        instructions: String,
        maximumResponseTokens: Int = 0,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw SummarizationError.unsupported(Availability.osTooOld)
        }

        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: maximumResponseTokens > 0 ? maximumResponseTokens : nil
        )

        // Two attempts: the model occasionally streams nothing and ends
        // cleanly. The retry builds a FRESH session so the empty turn
        // is not replayed as context.
        var latest = ""
        for attempt in 0..<2 {
            let session = LanguageModelSession(
                model: cachedModel,
                instructions: instructions
            )
            latest = ""
            do {
                for try await snapshot in session.streamResponse(to: text, options: options) {
                    latest = snapshot.content
                    onPartial?(latest)
                }
            } catch {
                throw classify(error)
            }
            if !latest.isEmpty { break }
            _ = attempt
        }

        guard !latest.isEmpty else {
            throw SummarizationError.emptyResponse
        }
        return latest
        #else
        throw SummarizationError.unsupported(.osTooOld)
        #endif
    }

    /// Failure modes, mapped from the framework's own error cases.
    public enum SummarizationError: LocalizedError, Equatable {
        /// The model refused, or tripped a guardrail even under the
        /// permissive set.
        case refused
        /// The input was longer than the model's context window.
        case inputTooLong
        /// Too many requests, or one already in flight.
        case busy
        /// The thread's language is not supported.
        case unsupportedLanguage
        /// Model assets are not downloaded.
        case assetsUnavailable
        case emptyResponse
        case unsupported(Availability)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .refused:
                return "Apple's on-device model declined to summarize this thread."
            case .inputTooLong:
                return "This thread is too long for the on-device model. Try a cloud provider."
            case .busy:
                return "The on-device model is busy. Try again in a moment."
            case .unsupportedLanguage:
                return "Apple's on-device model doesn't support this language yet."
            case .assetsUnavailable:
                return "Apple Intelligence is still downloading its model. Try again shortly."
            case .emptyResponse:
                return "The on-device model returned an empty summary."
            case .unsupported(let availability):
                return availability.explanation
            case .failed(let message):
                return message
            }
        }
    }

    /// A readable message for an error the enum has no case for.
    /// `localizedDescription` alone is often useless here; a failed
    /// generation can surface as "The operation couldn't be completed.
    /// (...GenerationError error -1.)". Prefers `failureReason`/
    /// `recoverySuggestion` when present.
    static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError {
            let parts = [localized.failureReason, localized.recoverySuggestion]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        let ns = error as NSError
        // An unclassified GenerationError -1 almost always means the
        // device has no usable model assets yet.
        if ns.localizedDescription.contains("GenerationError error -1") {
            return "Apple's on-device model couldn't run. This usually means "
                + "Apple Intelligence hasn't finished downloading its model, "
                + "or the device can't provide it. (\(ns.localizedDescription))"
        }
        return ns.localizedDescription
    }

    /// Maps a framework error onto `SummarizationError`, mirroring
    /// Reborn's own classifier: `guardrailViolation` and `refusal` are
    /// the same user-facing outcome, and `assetsUnavailable` means "not
    /// ready" rather than "broken".
    static func classify(_ error: Error) -> SummarizationError {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .guardrailViolation, .refusal:
                return .refused
            case .exceededContextWindowSize:
                return .inputTooLong
            case .rateLimited, .concurrentRequests:
                return .busy
            case .unsupportedLanguageOrLocale:
                return .unsupportedLanguage
            case .assetsUnavailable:
                return .assetsUnavailable
            default:
                return .failed(describe(error))
            }
        }
        #endif
        return .failed(describe(error))
    }
}
