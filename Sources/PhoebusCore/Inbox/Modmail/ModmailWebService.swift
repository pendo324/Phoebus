import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native modmail over a cookie/web session, since `RedditRepository`'s
/// OAuth-only modmail endpoint 403s for cookie-authenticated requests.
/// Reaches modmail the same way Reddit's own web client does, through
/// the Shreddit GraphQL endpoint, which needs no OAuth app.
///
/// `csrf_token` travels in the JSON body, not a header.
public enum ModmailWebService {
    /// Mailbox categories, GraphQL enum values that differ from the
    /// REST API's lowercase `state` strings (`ModmailInboxTab.apiState`),
    /// so the mapping is stated explicitly rather than derived.
    public enum MailboxCategory: String, Sendable, CaseIterable {
        case all = "ALL"
        case new = "NEW"
        case inProgress = "IN_PROGRESS"
        case archived = "ARCHIVED"
        case highlighted = "HIGHLIGHTED"
        case modDiscussions = "MOD_DISCUSSIONS"
        case notifications = "NOTIFICATIONS"
        case filtered = "FILTERED"
        case appeals = "APPEALS"
        case joinRequests = "JOIN_REQUESTS"

        /// Maps the REST `state` string onto the GraphQL enum.
        public init(restState: String) {
            switch restState.lowercased() {
            case "mod": self = .modDiscussions
            case "inprogress": self = .inProgress
            case "archived": self = .archived
            case "highlighted": self = .highlighted
            case "notifications": self = .notifications
            case "new": self = .new
            case "filtered": self = .filtered
            case "appeals": self = .appeals
            case "join_requests", "joinrequests": self = .joinRequests
            default: self = .all
            }
        }

        /// Maps Apollo's 5-tab inbox onto Reddit's categories.
        /// `.modDiscussions` matters: a moderator messaging their own
        /// subreddit produces an `INTERNAL` conversation that appears
        /// only here, never in `ALL`.
        public init(tab: ModmailInboxTab) {
            switch tab {
            case .notifications: self = .notifications
            case .modDiscussions: self = .modDiscussions
            case .highlighted: self = .highlighted
            case .archived: self = .archived
            case .inProgress: self = .inProgress
            }
        }
    }

    public enum SortOrder: String, Sendable {
        case recent = "RECENT"
        case unread = "UNREAD"
        case mod = "MOD"
        case user = "USER"
    }

    public enum ServiceError: LocalizedError, Equatable {
        case requiresWebSession
        case missingCSRFToken
        case http(Int)
        case rejected(String)
        /// Reddit answered, but refused the operation while still
        /// reporting `ok: true`. See `warningCode` below.
        case silentlyRejected(String)
        case sessionExpired
        case malformedResponse
        /// Reddit answered 200 with a bot-check page and a `Retry-After`
        /// header instead of JSON.
        case rateLimited(retryAfterSeconds: Int?)

        public var errorDescription: String? {
            switch self {
            case .requiresWebSession:
                return "Mod Mail over a web session requires signing in via Settings > Accounts."
            case .missingCSRFToken:
                return "Phoebus could not find a CSRF token in this session."
            case .http(let code):
                return "Reddit returned HTTP \(code)."
            case .rejected(let message):
                return message
            case .silentlyRejected(let message):
                return message
            case .sessionExpired:
                return "The Reddit web session expired. Sign in again and retry."
            case .malformedResponse:
                return "Reddit's reply could not be read."
            case .rateLimited(let seconds):
                if let seconds {
                    return "Reddit is rate limiting Mod Mail. Try again in \(seconds)s."
                }
                return "Reddit is rate limiting Mod Mail. Wait a moment and try again."
            }
        }
    }

    // MARK: Transport

    private static let endpoint = URL(string: "https://www.reddit.com/svc/shreddit/graphql")!

    /// Performs a call, retrying through Reddit's transient throttle.
    /// The throttle is self-clearing, so surfacing it straight to the
    /// user would make normal use look broken.
    public static func perform(
        operation: String,
        variables: [String: Any],
        session: WebSessionCredential,
        referer: String = "https://www.reddit.com/mail/all",
        urlSession: URLSession? = nil,
        maxAttempts: Int = 4
    ) async throws -> [String: Any] {
        var lastError: Error = ServiceError.malformedResponse
        for attempt in 0..<max(1, maxAttempts) {
            do {
                return try await performOnce(
                    operation: operation, variables: variables, session: session,
                    referer: referer, urlSession: urlSession)
            } catch let error as ServiceError {
                guard case .rateLimited(let retryAfter) = error, attempt < maxAttempts - 1 else {
                    throw error
                }
                lastError = error
                // Retry-After is treated as a floor, not a promise:
                // Reddit sends `Retry-After: 0` here, which taken
                // literally would burn every attempt without waiting.
                let backoff = pow(2.0, Double(attempt)) * 1.5
                let seconds = max(Double(retryAfter ?? 0), backoff)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
        throw lastError
    }

    private static func performOnce(
        operation: String,
        variables: [String: Any],
        session: WebSessionCredential,
        referer: String,
        urlSession: URLSession?
    ) async throws -> [String: Any] {
        guard let csrfToken = PollVoteService.csrfToken(fromCookieHeader: session.cookieHeader) else {
            throw ServiceError.missingCSRFToken
        }
        let body: [String: Any] = [
            "operation": operation,
            "variables": variables,
            "csrf_token": csrfToken,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw ServiceError.malformedResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        // Load-bearing: without a browser User-Agent, Reddit answers
        // HTTP 200 with a "Prove your humanity" bot-check page instead
        // of JSON, which would read as a parse failure, not a bot check.
        request.setValue(RedditAPIClient.webBrowserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.reddit.com", forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        // Same hardening as `PollVoteService`: without this,
        // URLSession can discard the hand-set session cookie, sending
        // the request out unauthenticated (Reddit answers 200 no-op).
        let owned: URLSession
        if let urlSession {
            owned = urlSession
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            owned = URLSession(configuration: config, delegate: PollVoteRedirectGuard(), delegateQueue: nil)
        }
        defer { if urlSession == nil { owned.finishTasksAndInvalidate() } }

        let (data, response) = try await owned.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw ServiceError.sessionExpired }
        guard (200..<300).contains(status) else {
            // A missing required variable answers 500 as plain text,
            // not JSON, so surface the status rather than parse it.
            throw ServiceError.http(status)
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<\(data.count) bytes>"
            let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            // Reddit throttles by answering 200 with a bot-check page
            // and Retry-After rather than a 429; distinguish from a
            // genuine parse failure.
            if retryAfter != nil || preview.contains("Prove your humanity") {
                throw ServiceError.rateLimited(retryAfterSeconds: retryAfter.flatMap(Int.init))
            }
            throw ServiceError.rejected("Unreadable reply (HTTP \(status)): \(preview.prefix(120))")
        }
        if PollVoteService.hasErrors(json["errors"]) {
            let message = ((json["errors"] as? [Any])?.first as? [String: Any])?["message"] as? String
            throw ServiceError.rejected(message ?? "Reddit refused the request.")
        }
        return json
    }

    /// Whether a mutation genuinely succeeded. A rejected mutation can
    /// still answer `ok: true, errors: null`; the real failure hides in
    /// `extensions.warnings[].extensions.code`.
    public static func warningCode(in json: [String: Any]) -> String? {
        guard let extensions = json["extensions"] as? [String: Any],
              let warnings = extensions["warnings"] as? [[String: Any]],
              let first = warnings.first else { return nil }
        if let inner = first["extensions"] as? [String: Any],
           let code = inner["code"] as? String {
            return code
        }
        return first["message"] as? String
    }

    /// Reads `data.<field>.ok`, then applies the warning rule above.
    private static func requireOK(_ json: [String: Any], field: String) throws {
        let payload = (json["data"] as? [String: Any])?[field] as? [String: Any]
        let ok = payload?["ok"] as? Bool ?? false
        if let code = warningCode(in: json) {
            throw ServiceError.silentlyRejected(
                "Reddit accepted the request but did not apply it (\(code))."
            )
        }
        guard ok, !PollVoteService.hasErrors(payload?["errors"]) else {
            throw ServiceError.rejected("Reddit refused the request.")
        }
    }

    // MARK: Reads

    /// Fetches one mailbox category. `subredditIds: []` is required,
    /// not optional: omitting it answers 500 Internal Server Error.
    /// The empty array means "every subreddit I moderate".
    public static func fetchConversations(
        category: MailboxCategory,
        sort: SortOrder = .recent,
        limit: Int = 25,
        subredditIDs: [String] = [],
        session: WebSessionCredential,
        urlSession: URLSession? = nil
    ) async throws -> [ModmailWebConversation] {
        let json = try await perform(
            operation: "ModmailConversations",
            variables: [
                "mailboxCategory": category.rawValue,
                "sort": sort.rawValue,
                "first": limit,
                "subredditIds": subredditIDs,
            ],
            session: session,
            urlSession: urlSession
        )
        return try decodeConversations(from: json)
    }

    /// Envelope: `data.modmailConversationsV2.edges[].node`.
    public static func decodeConversations(from json: [String: Any]) throws -> [ModmailWebConversation] {
        guard let data = json["data"] as? [String: Any],
              let container = data["modmailConversationsV2"] as? [String: Any],
              let edges = container["edges"] as? [[String: Any]] else {
            throw ServiceError.malformedResponse
        }
        return edges.compactMap { edge in
            guard let node = edge["node"] as? [String: Any] else { return nil }
            return ModmailWebConversation(node: node)
        }
    }

    /// Per-category unread counts, from the live response's own keys.
    public static func fetchUnreadCounts(
        session: WebSessionCredential,
        urlSession: URLSession? = nil
    ) async throws -> [MailboxCategory: Int] {
        let json = try await perform(
            operation: "ModmailUnreadCounts",
            variables: ["subredditIds": []],
            session: session,
            urlSession: urlSession
        )
        guard let identity = (json["data"] as? [String: Any])?["identity"] as? [String: Any],
              let modMail = identity["modMail"] as? [String: Any],
              let counts = modMail["unreadConversationCounts"] as? [String: Any] else {
            throw ServiceError.malformedResponse
        }
        var result: [MailboxCategory: Int] = [:]
        for (key, value) in counts {
            guard let category = MailboxCategory(rawValue: key), let count = value as? Int else { continue }
            result[category] = count
        }
        return result
    }

    /// Fetches a thread's messages and mod actions, interleaved in one
    /// `messagesAndActions` connection discriminated by `__typename`.
    /// entries the web client shows inline. Paged 25 newest-first, so
    /// a busy audit trail can push the only message past page 1.
    public static func fetchThread(
        conversationID: String,
        limit: Int = 100,
        session: WebSessionCredential,
        urlSession: URLSession? = nil
    ) async throws -> [ModmailWebThreadEntry] {
        let json = try await perform(
            operation: "ModmailConversationMessagesAndActions",
            variables: ["conversationId": Self.prefixed(conversationID), "first": limit],
            session: session,
            referer: "https://www.reddit.com/mail/all",
            urlSession: urlSession
        )
        return try decodeThread(from: json)
    }

    public static func decodeThread(from json: [String: Any]) throws -> [ModmailWebThreadEntry] {
        guard let data = json["data"] as? [String: Any],
              let full = data["modmailFullConversation"] as? [String: Any],
              let container = full["messagesAndActions"] as? [String: Any],
              let edges = container["edges"] as? [[String: Any]] else {
            throw ServiceError.malformedResponse
        }
        let entries = edges.compactMap { ModmailWebThreadEntry(node: $0["node"] as? [String: Any]) }
        // Reddit returns newest-first; a thread reads oldest-first.
        return entries.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    // MARK: Writes

    /// Sends a new modmail from a user to a subreddit.
    public static func sendToSubreddit(
        subredditID: String,
        subject: String,
        body: String,
        session: WebSessionCredential,
        urlSession: URLSession? = nil
    ) async throws {
        let json = try await perform(
            operation: "SendMessageToSubreddit",
            variables: ["input": ["subject": subject, "body": body, "subredditId": subredditID]],
            session: session,
            referer: "https://www.reddit.com/message/compose/",
            urlSession: urlSession
        )
        try requireOK(json, field: "sendMessageToSubreddit")
    }

    /// Resolves a subreddit name to the `t5_` id the send requires.
    public static func subredditID(
        name: String,
        session: WebSessionCredential,
        urlSession: URLSession? = nil
    ) async throws -> String {
        let json = try await perform(
            operation: "GetMessageRecipientSubredditInfo",
            variables: ["subredditName": name],
            session: session,
            referer: "https://www.reddit.com/message/compose/",
            urlSession: urlSession
        )
        guard let data = json["data"] as? [String: Any],
              let info = data["subredditInfoByName"] as? [String: Any],
              let id = info["id"] as? String, !id.isEmpty else {
            throw ServiceError.rejected("Hmm, that community doesn't exist. Try checking the spelling.")
        }
        return id
    }

    /// Replies within an existing conversation. Success requires `ok`
    /// AND a non-empty `messageId`; Reddit's client treats an empty id
    /// as failure even when `ok` is true.
    public static func reply(
        conversationID: String,
        authorID: String,
        body: String,
        isInternal: Bool,
        isAuthorHidden: Bool = false,
        session: WebSessionCredential,
        urlSession: URLSession? = nil
    ) async throws {
        let json = try await perform(
            operation: "AddModmailMessage",
            variables: [
                "input": [
                    "conversationId": Self.prefixed(conversationID),
                    "authorId": authorID,
                    "message": [
                        "content": ["markdown": body],
                        "participatingAs": "MODERATOR",
                        "isInternal": isInternal,
                        "isAuthorHidden": isAuthorHidden,
                    ],
                ]
            ],
            session: session,
            urlSession: urlSession
        )
        try requireOK(json, field: "addModmailMessage")
        let payload = (json["data"] as? [String: Any])?["addModmailMessage"] as? [String: Any]
        let messageID = payload?["messageId"] as? String
        guard let messageID, !messageID.isEmpty else {
            throw ServiceError.silentlyRejected("Reddit accepted the reply but returned no message.")
        }
    }


    /// Marks an entire mailbox read, scoped to a `mailboxCategory` plus
    /// `subredditIds`. "Mark all as read" in Archived must not clear
    /// Notifications.
    public static func markAllRead(
        category: MailboxCategory,
        subredditIDs: [String] = [],
        session: WebSessionCredential,
        urlSession: URLSession? = nil
    ) async throws {
        let json = try await perform(
            operation: "MarkAllModmailConversationsAsRead",
            variables: ["input": ["mailboxCategory": category.rawValue, "subredditIds": subredditIDs]],
            session: session,
            urlSession: urlSession)
        try requireOK(json, field: "markAllModmailConversationsAsRead")
    }

    // MARK: Quick actions

    /// Conversation ids are prefixed in every GraphQL call:
    /// `ModmailConversation_<id>`. Passing a bare id fails.
    public static func prefixed(_ id: String) -> String {
        id.hasPrefix("ModmailConversation_") ? id : "ModmailConversation_\(id)"
    }

    private static func setStatus(
        operation: String,
        field: String,
        key: String,
        value: Bool,
        conversationIDs: [String],
        session: WebSessionCredential,
        urlSession: URLSession?
    ) async throws {
        let json = try await perform(
            operation: operation,
            variables: ["input": ["conversationIds": conversationIDs.map(Self.prefixed), key: value]],
            session: session,
            urlSession: urlSession
        )
        try requireOK(json, field: field)
    }

    public static func setHighlighted(
        _ highlighted: Bool, conversationIDs: [String],
        session: WebSessionCredential, urlSession: URLSession? = nil
    ) async throws {
        try await setStatus(
            operation: "SetModmailConversationsHighlightStatus",
            field: "setModmailConversationsHighlightStatus",
            key: "highlight", value: highlighted,
            conversationIDs: conversationIDs, session: session, urlSession: urlSession)
    }

    /// Archiving is unavailable for some conversations (mod
    /// discussions); surfaced as `.silentlyRejected` instead of a
    /// false success.
    public static func setArchived(
        _ archived: Bool, conversationIDs: [String],
        session: WebSessionCredential, urlSession: URLSession? = nil
    ) async throws {
        try await setStatus(
            operation: "SetModmailConversationsArchiveStatus",
            field: "setModmailConversationsArchiveStatus",
            key: "archive", value: archived,
            conversationIDs: conversationIDs, session: session, urlSession: urlSession)
    }

    public static func setRead(
        _ read: Bool, conversationIDs: [String],
        session: WebSessionCredential, urlSession: URLSession? = nil
    ) async throws {
        try await setStatus(
            operation: "SetModmailConversationsReadStatus",
            field: "setModmailConversationsReadStatus",
            key: "markRead", value: read,
            conversationIDs: conversationIDs, session: session, urlSession: urlSession)
    }

    public static func setFiltered(
        _ filtered: Bool, conversationIDs: [String],
        session: WebSessionCredential, urlSession: URLSession? = nil
    ) async throws {
        try await setStatus(
            operation: "SetModmailConversationsFilterStatus",
            field: "setModmailConversationsFilterStatus",
            key: "filter", value: filtered,
            conversationIDs: conversationIDs, session: session, urlSession: urlSession)
    }
}
