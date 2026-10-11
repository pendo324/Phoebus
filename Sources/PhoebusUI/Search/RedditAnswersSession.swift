#if canImport(UIKit)
import Foundation
import PhoebusCore

/// Asks Reddit Answers one question (Phoebus-only): mints (or reuses) the
/// bearer token from the web session, streams the reply and folds it into the
/// answer as it arrives. The pure parts (requests, SSE, patching, the render
/// model) are Core's `RedditAnswers`. Every question is its own conversation.
@MainActor
final class RedditAnswersSession: ObservableObject {
    enum Phase: Equatable {
        case idle, streaming, finished
        case failed(RedditAnswersError)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var content = RedditAnswerContent()
    @Published private(set) var quota: RedditAnswerQuota?
    /// Titles and counts for the cited posts, comments and communities, read
    /// from Reddit once the answer is complete.
    @Published private(set) var sources: [String: RedditAnswerSourceInfo] = [:]
    /// The part of the answer at the top of the screen, as the scroll view
    /// reports it.
    @Published var scrollAnchor: String?
    /// `scrollAnchor` when the screen was left for a cited post: the rebuilt
    /// scroll view starts at the top and reports that, so the place is kept
    /// separately and scrolled back to on return.
    var savedAnchor: String?

    private var task: Task<Void, Never>?
    private var generation = 0

    /// Starting a new question, or leaving the screen, ends the old stream.
    deinit { task?.cancel() }

    /// The question this session is answering (or last answered).
    private(set) var question: String?

    /// Asks `query`, unless this session is already answering the same
    /// question: a rebuilt answer screen keeps the answer (and its place)
    /// instead of asking Reddit again.
    func askIfNew(_ query: String, repository: RedditRepository) {
        if let question, RedditAnswersSession.sameQuestion(question, query), phase != .idle {
            if case .failed = phase {} else { return }
        }
        ask(query, repository: repository)
    }

    /// Questions that differ only in case or surrounding spaces are the same.
    static func sameQuestion(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    func ask(_ query: String, repository: RedditRepository) {
        cancel()
        question = query
        let mine = generation
        phase = .streaming
        content = RedditAnswerContent()
        sources = [:]
        scrollAnchor = nil
        savedAnchor = nil
        task = Task { [weak self] in await self?.run(query, repository: repository, generation: mine) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }

    private func run(_ query: String, repository: RedditRepository, generation mine: Int) async {
        do {
            guard let web = await repository.answersWebSession() else { throw RedditAnswersError.needsWebSession }
            let conversation = UUID().uuidString.lowercased()
            var stream = RedditAnswerStream()
            var refreshed = false
            while true {
                let token = try await RedditAnswers.token(for: web, conversationID: conversation, forceRefresh: refreshed)
                do {
                    stream = RedditAnswerStream()
                    try await consume(query, conversation: conversation, token: token.value, into: &stream, generation: mine)
                    break
                } catch RedditAnswersError.unauthorized where !refreshed {
                    // A cached token Reddit no longer honours: mint one more.
                    refreshed = true
                    RedditAnswersTokenCache.shared.invalidate(for: web.username)
                }
            }
            guard mine == generation else { return }
            if let failure = stream.failure { throw failure }
            guard stream.isComplete else { throw RedditAnswersError.endedEarly }
            phase = .finished
            await loadSources(stream.content, repository: repository, generation: mine)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard mine == generation else { return }
            phase = .failed(error as? RedditAnswersError ?? .server(error.localizedDescription))
        }
    }

    /// Reads the event stream, publishing the answer after every event that
    /// changes it.
    private func consume(_ query: String, conversation: String, token: String,
                         into stream: inout RedditAnswerStream, generation mine: Int) async throws {
        guard let request = RedditAnswers.answerRequest(query: query, conversationID: conversation, token: token) else {
            throw RedditAnswersError.malformed
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        let urlSession = URLSession(configuration: configuration)
        defer { urlSession.finishTasksAndInvalidate() }

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw RedditAnswersError.malformed }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw RedditAnswersError.unauthorized
        case 429:
            let wait = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw RedditAnswersError.quotaExhausted(secondsUntilReset: wait ?? quota?.secondsUntilReset)
        default: throw RedditAnswersError.http(http.statusCode)
        }

        var parser = ServerSentEventParser()
        var line: [UInt8] = []
        func publish(_ events: [ServerSentEvent]) {
            guard !events.isEmpty, mine == generation else { return }
            for event in events { stream.handle(event) }
            content = stream.content
            if let latest = stream.quota { quota = latest }
        }
        for try await byte in bytes {
            line.append(byte)
            if byte == 0x0A {
                publish(parser.feed(line))
                line.removeAll(keepingCapacity: true)
            }
        }
        publish(parser.feed(line) + parser.finish())
    }

    private func loadSources(_ content: RedditAnswerContent, repository: RedditRepository, generation mine: Int) async {
        var ids = content.citations.map(\.id) + content.consultedPostIDs
        ids += content.consultedSubreddits.filter { $0.name == nil }.map(\.id)
        for block in content.blocks {
            switch block {
            case .subreddits(let found): ids += found
            case .references(_, let references): ids += references.map(\.id)
            default: break
            }
        }
        let found = await repository.fetchAnswerSources(ids: ids)
        guard mine == generation else { return }
        sources = found
    }
}
#endif
