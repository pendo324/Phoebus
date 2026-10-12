import AppIntents
import Foundation
import OSLog
import PhoebusCore

// Reborn "Siri & Spotlight" (#1299): logging, errors and navigation shared by
// the entities, intents and the content service.

/// Fixed events, never account or content data: no ids, search terms,
/// returned content or error strings.
enum SiriLog {
    private static let logger = Logger(subsystem: "com.pendo324.Phoebus", category: "Siri")

    static func event(_ message: StaticString) {
        logger.notice("[Siri] \(String(describing: message), privacy: .public)")
    }

    static func event(_ message: StaticString, count: Int) {
        logger.notice("[Siri] \(String(describing: message), privacy: .public) count=\(count, privacy: .public)")
    }

    // These entry points can be called by Siri, Spotlight or Shortcuts. A query
    // callback proves entity access, not which system surface requested it.
    static func query<Value: Sendable>(_ operation: StaticString,
                                       perform: @Sendable () async throws -> [Value]) async throws -> [Value] {
        logger.notice("[Siri] Query started: \(String(describing: operation), privacy: .public)")
        do {
            let values = try await perform()
            logger.notice("[Siri] Query completed: \(String(describing: operation), privacy: .public) count=\(values.count, privacy: .public)")
            return values
        } catch {
            logger.notice("[Siri] Query failed: \(String(describing: operation), privacy: .public)")
            throw error
        }
    }
}

enum SiriNavigationError: Error, CustomLocalizedStringResourceConvertible {
    case emptyQuery

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyQuery: "Enter something to search for in Phoebus."
        }
    }
}

/// Opens what an intent names, through the same pending-target path the
/// Shortcuts intents already use.
@MainActor
enum SiriNavigation {
    /// When an intent last drove navigation. Donate only interactions people
    /// start in the app's own UI, never ones Siri or Shortcuts started (the
    /// system already donates those), so the onscreen bridge checks this.
    private(set) static var lastIntentNavigation: Date?

    static var intentNavigationIsRecent: Bool {
        lastIntentNavigation.map { Date().timeIntervalSince($0) < 10 } ?? false
    }

    static func open(_ target: RedditURLTarget) {
        lastIntentNavigation = Date()
        AppIntentNavigation.shared.pendingTarget = target
    }

    /// Selects the Search tab and runs the query there.
    static func search(_ query: String) throws {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw SiriNavigationError.emptyQuery }
        lastIntentNavigation = Date()
        QuickActionRouter.shared.pendingSearchQuery = term
        QuickActionRouter.shared.pending = .search
    }
}
