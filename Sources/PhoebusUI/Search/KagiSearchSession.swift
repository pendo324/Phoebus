#if canImport(WebKit) && canImport(UIKit)
import Foundation
import PhoebusCore

/// Runs one Kagi search (Reborn "Kagi Search", #1305): a plain GET of Kagi's
/// server-rendered results page with the subscriber's Session Link as the
/// `kagi_session` cookie (no web view, no bot check), then one Reddit read
/// for the whole page so the cards open with Reddit's score, comment count
/// and age. The pure parts (URL, parser, results) are `KagiSearch`.
@MainActor
final class KagiSearchSession: ObservableObject {
    enum SearchError: LocalizedError {
        case sessionExpired, timedOut, network(String), unreadable

        var errorDescription: String? {
            switch self {
            case .sessionExpired: return "Kagi didn't accept the saved Session Link."
            case .timedOut: return "Kagi took too long to respond."
            case .network(let message): return message
            case .unreadable: return "Kagi's results page couldn't be read."
            }
        }
    }

    /// The first page is still loading after 8 s.
    @Published private(set) var isSlow = false

    private var generation = 0
    private var slowNotice: Task<Void, Never>?

    /// One search at a time: a new one (or `cancel`) ends the previous one,
    /// which then throws `CancellationError`.
    func search(_ query: String, options: GoogleSearchOptions, page: Int,
                repository: RedditRepository) async throws -> GoogleSearchSession.Page {
        cancel()
        guard let url = KagiSearch.searchURL(query, options: options, page: page) else {
            return GoogleSearchSession.Page(results: [], mayHaveMore: false)
        }
        guard let token = KagiSession.token else { throw SearchError.sessionExpired }
        let mine = generation
        let started = Date()
        if page == 0 {
            slowNotice = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(GoogleSearch.slowNoticeDelay * 1e9))
                if !Task.isCancelled, let self, mine == self.generation { self.isSlow = true }
            }
        }
        defer { if mine == generation { endSlowNotice() } }

        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await KagiSearch.fetchPage(url, token: token)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw SearchError.timedOut
        } catch {
            throw SearchError.network(error.localizedDescription)
        }
        guard mine == generation, !Task.isCancelled else { throw CancellationError() }

        if KagiSearch.isSignedOut(statusCode: response.statusCode, finalURL: response.url) { throw SearchError.sessionExpired }
        guard response.statusCode < 400 else {
            throw SearchError.network("Kagi returned an error (HTTP \(response.statusCode)).")
        }

        // ~175 KB of HTML: parsed off the main thread.
        let html = String(decoding: data.prefix(KagiSearch.maximumPageBytes), as: UTF8.self)
        let (parsed, results) = await Task.detached(priority: .userInitiated) { () -> (KagiSearch.ParsedPage, [GoogleSearchResult]) in
            let parsed = KagiSearch.parseResults(html: html)
            return (parsed, KagiSearch.results(from: parsed))
        }.value
        guard mine == generation, !Task.isCancelled else { throw CancellationError() }
        switch parsed.kind {
        case .signedOut: throw SearchError.sessionExpired
        case .unreadable: throw SearchError.unreadable
        case .results: break
        }

        // A failed or slow Reddit read just leaves Kagi's data.
        var infos: [String: GoogleSearchRedditInfo] = [:]
        if !results.isEmpty {
            let remaining = max(1, KagiSearch.searchTimeout - Date().timeIntervalSince(started))
            infos = await Self.withDeadline(remaining) { await repository.fetchGoogleResultsInfo(results) } ?? [:]
        }
        guard mine == generation, !Task.isCancelled else { throw CancellationError() }
        return GoogleSearchSession.Page(results: KagiSearch.applying(infos, to: results), mayHaveMore: parsed.hasMore)
    }

    func cancel() {
        generation += 1
        endSlowNotice()
    }

    private func endSlowNotice() {
        slowNotice?.cancel()
        slowNotice = nil
        isSlow = false
    }

    private static func withDeadline<T: Sendable>(_ seconds: TimeInterval,
                                                  _ operation: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }
}
#endif
