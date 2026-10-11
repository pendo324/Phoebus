import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reddit Answers, the fourth "Search With" engine (Phoebus-only): the
/// request builders, token cache and stream state behind the answer screen.
/// The wire format is what reddit.com's own Answers page speaks: a short-lived
/// bearer token minted from the web session, then one POST whose
/// `text/event-stream` reply patches a single document into shape.
public enum RedditAnswers {
    static let tokenURL = URL(string: "https://www.reddit.com/svc/shreddit/token")!
    static let answersBase = "https://answers.reddit.com/v1/answers/"

    /// The search box's `source` value. The one Reddit's page sent in the
    /// capture this was built from; others are unverified.
    public static let source = "TYPEAHEAD_EXPANDED_SEARCH_BAR"

    /// The `ra:*` elements the answer screen draws natively. Anything not
    /// listed (carousels, image and video cards, products, retailers, quote
    /// cards) is left for Reddit to leave out; one that still arrives
    /// degrades to its text and links.
    public static let supportedFeatures = [
        "ra:reasoning", "ra:thinking_step", "ra:post_sources", "ra:post_source",
        "ra:subreddit_sources", "ra:subreddit_source", "ra:subreddit_source_bar",
        "ra:source", "ra:subreddit",
    ]

    /// A bearer token and when it stops working.
    public struct Token: Equatable, Sendable {
        public var value: String
        public var expires: Date

        public init(value: String, expires: Date) {
            self.value = value
            self.expires = expires
        }
    }

    /// Mints a token with the web session's cookies and CSRF token. Nil when
    /// the session carries no `csrf_token` cookie.
    public static func tokenRequest(session: WebSessionCredential, conversationID: String) -> URLRequest? {
        guard let csrf = PollVoteService.csrfToken(fromCookieHeader: session.cookieHeader),
              let body = try? JSONSerialization.data(withJSONObject: ["csrf_token": csrf]) else { return nil }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(RedditAPIClient.webBrowserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.reddit.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.reddit.com/answers/\(conversationID)", forHTTPHeaderField: "Referer")
        return request
    }

    /// `{"token": "...", "expires": <ms since epoch>}`.
    public static func parseToken(_ data: Data) -> Token? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let value = object["token"] as? String, !value.isEmpty,
              let expires = (object["expires"] as? NSNumber)?.doubleValue else { return nil }
        return Token(value: value, expires: Date(timeIntervalSince1970: expires / 1000))
    }

    /// The question's request. `conversationID` is the UUID in the URL; the
    /// correlation id is that UUID and the send time.
    public static func answerRequest(query: String, conversationID: String, token: String, now: Date = Date()) -> URLRequest? {
        guard let url = URL(string: answersBase + conversationID) else { return nil }
        let body: [String: Any] = [
            "format": "RTJSON",
            "query": query,
            "source": source,
            "correlationId": correlationID(conversationID: conversationID, now: now),
            "supportedFeatures": supportedFeatures,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("web3x", forHTTPHeaderField: "X-Reddit-App-Name")
        request.setValue(RedditAPIClient.webBrowserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.reddit.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.reddit.com/", forHTTPHeaderField: "Referer")
        return request
    }

    /// The cached token for the session's account, or a freshly minted one
    /// (kept in `cache`). `forceRefresh` skips the cache after a 401.
    public static func token(for session: WebSessionCredential, conversationID: String,
                             forceRefresh: Bool = false, cache: RedditAnswersTokenCache = .shared,
                             urlSession: URLSession = .shared) async throws -> Token {
        if !forceRefresh, let cached = cache.token(for: session.username) { return cached }
        guard let request = tokenRequest(session: session, conversationID: conversationID) else {
            throw RedditAnswersError.needsWebSession
        }
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            cache.invalidate(for: session.username)
            throw RedditAnswersError.tokenRefused(status)
        }
        guard let token = parseToken(data) else { throw RedditAnswersError.malformed }
        cache.store(token, for: session.username)
        return token
    }

    /// Whether the active account has a reddit.com web session to mint a
    /// token with.
    public static var hasWebSession: Bool {
        guard let username = FavoriteSubredditsAccountContext.currentUsernameProvider() else { return false }
        return WebSessionRegistry.featureSession(for: username) != nil
    }

    public static func correlationID(conversationID: String, now: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(conversationID)__\(formatter.string(from: now))"
    }
}

/// The tokens minted so far, per account, kept until shortly before they
/// expire.
public final class RedditAnswersTokenCache: @unchecked Sendable {
    public static let shared = RedditAnswersTokenCache()
    /// A token this close to expiring is minted again.
    static let margin: TimeInterval = 60

    private let lock = NSLock()
    private var tokens: [String: RedditAnswers.Token] = [:]

    public init() {}

    public func token(for username: String, now: Date = Date()) -> RedditAnswers.Token? {
        lock.lock(); defer { lock.unlock() }
        guard let token = tokens[username.lowercased()], token.expires.timeIntervalSince(now) > Self.margin else { return nil }
        return token
    }

    public func store(_ token: RedditAnswers.Token, for username: String) {
        lock.lock(); defer { lock.unlock() }
        tokens[username.lowercased()] = token
    }

    public func invalidate(for username: String) {
        lock.lock(); defer { lock.unlock() }
        tokens[username.lowercased()] = nil
    }
}

/// How many questions are left, from the stream's `userQuota` event.
public struct RedditAnswerQuota: Equatable, Sendable {
    public var remaining: Int
    public var secondsUntilReset: Int

    public init(remaining: Int, secondsUntilReset: Int) {
        self.remaining = remaining
        self.secondsUntilReset = secondsUntilReset
    }

    /// "49 questions left"; "No questions left" at zero.
    public var summary: String {
        switch remaining {
        case ..<1: return "No questions left"
        case 1: return "1 question left"
        default: return "\(remaining) questions left"
        }
    }

    /// "11 min"; "under a minute".
    public var resetDescription: String { Self.duration(secondsUntilReset) }

    static func duration(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "under a minute"
        case ..<3600: return "\(Int((Double(seconds) / 60).rounded(.up))) min"
        default:
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
        }
    }
}

public enum RedditAnswersError: Error, Equatable, LocalizedError {
    /// No reddit.com web session to mint a token with.
    case needsWebSession
    /// Reddit refused the token request (HTTP status).
    case tokenRefused(Int)
    /// Reddit turned the bearer token away; one fresh token is worth a try.
    case unauthorized
    case quotaExhausted(secondsUntilReset: Int?)
    case http(Int)
    /// An `error` event.
    case server(String)
    case malformed
    /// The stream closed before its `success` event.
    case endedEarly

    public var errorDescription: String? {
        switch self {
        case .needsWebSession:
            return "Reddit Answers needs a reddit.com sign-in."
        case .tokenRefused(let status):
            return status == 401 || status == 403
                ? "Reddit didn't accept the saved reddit.com sign-in. Sign in again to keep asking."
                : "Reddit wouldn't start an Answers session (HTTP \(status))."
        case .unauthorized:
            return "Reddit Answers turned the request away. Try again."
        case .quotaExhausted(let seconds):
            guard let seconds else { return "You're out of Reddit Answers questions for now." }
            return "You're out of Reddit Answers questions for now. You can ask again in \(RedditAnswerQuota.duration(seconds))."
        case .http(let status):
            return "Reddit Answers answered with HTTP \(status)."
        case .server(let message):
            return message
        case .malformed:
            return "Reddit Answers sent something Phoebus couldn't read."
        case .endedEarly:
            return "The answer stopped early."
        }
    }

    /// Whether signing in to reddit.com again is the fix.
    public var needsSignIn: Bool {
        switch self {
        case .needsWebSession: return true
        case .tokenRefused(let status): return status == 401 || status == 403
        default: return false
        }
    }
}

/// The answer as the stream builds it: `userQuota`, `patch` and `success` /
/// `error` events folded into one document.
public struct RedditAnswerStream: Sendable {
    public private(set) var json: JSONValue = .object([:])
    public private(set) var quota: RedditAnswerQuota?
    public private(set) var isComplete = false
    public private(set) var failure: RedditAnswersError?
    /// Patches that didn't apply; the document keeps what it had.
    public private(set) var skippedPatches = 0

    public init() {}

    public var document: RedditAnswerDocument { RedditAnswerDocument(json: json) }
    public var content: RedditAnswerContent { RedditAnswerContent(document: document) }

    public mutating func handle(_ event: ServerSentEvent) {
        let payload = try? JSONDecoder().decode(JSONValue.self, from: Data(event.data.utf8))
        switch event.event {
        case "userQuota":
            if case .object(let object)? = payload, case .number(let remaining)? = object["queriesRemaining"] {
                var reset = 0
                if case .number(let seconds)? = object["timeUntilResetSeconds"] { reset = Int(seconds) }
                quota = RedditAnswerQuota(remaining: Int(remaining), secondsUntilReset: reset)
            }
        case "patch":
            guard let payload else { skippedPatches += 1; return }
            var next = json
            do {
                try JSONPatch.apply(payload, to: &next)
                json = next
            } catch {
                skippedPatches += 1
            }
        case "success":
            isComplete = true
        case "error":
            failure = Self.failure(from: payload, raw: event.data, quota: quota)
        default:
            break
        }
    }

    static func failure(from payload: JSONValue?, raw: String, quota: RedditAnswerQuota?) -> RedditAnswersError {
        var message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var code = ""
        if case .object(let object)? = payload {
            for key in ["message", "error", "detail", "description"] {
                if case .string(let text)? = object[key], !text.isEmpty { message = text; break }
            }
            for key in ["code", "type", "status"] {
                switch object[key] {
                case .string(let text)?: code = text
                case .number(let number)?: code = String(Int(number))
                default: continue
                }
                break
            }
        }
        let haystack = (code + " " + message).lowercased()
        if haystack.contains("quota") || haystack.contains("rate limit") || haystack.contains("rate_limit")
            || haystack.contains("too many") || code == "429" {
            return .quotaExhausted(secondsUntilReset: quota?.secondsUntilReset)
        }
        return .server(message.isEmpty ? "Reddit Answers hit an error." : message)
    }
}
