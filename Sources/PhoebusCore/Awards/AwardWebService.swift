import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AwardError: LocalizedError, Equatable {
    case requiresWebSession
    case sessionExpired
    /// Reddit answered with its bot check, or refused the request.
    case blocked
    case http(Int)
    /// The reply wasn't the markup or JSON this code knows.
    case unreadable
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .requiresWebSession:
            return "Awards need a Reddit web session. Sign in on the web under Accounts."
        case .sessionExpired:
            return "The Reddit web session expired. Sign in again and retry."
        case .blocked:
            return "Reddit answered with a browser check instead of the award details. Try again in a moment."
        case .http(let code):
            return "Reddit returned HTTP \(code)."
        case .unreadable:
            return "Reddit's award details couldn't be read. Its page may have changed."
        case .rejected(let message):
            return message
        }
    }
}

/// Reddit's current awards, over a web session. Everything here is a
/// Shreddit-internal partial or GraphQL operation: the thread's comment-tree
/// fragment (counts and the featured icon), the award dialog (what can be
/// given, the user's Gold, the signed leaderboard link), the leaderboard, and
/// `CreateAwardOrder`.
public enum AwardWebService {
    private static let origin = "https://www.reddit.com"

    // MARK: URLs

    /// Shreddit's sort enum for a Phoebus comment sort; nil leaves Reddit's default.
    static func shredditSort(_ sort: String) -> String? {
        switch sort.lowercased() {
        case "confidence", "best": return "CONFIDENCE"
        case "top": return "TOP"
        case "new", "live": return "NEW"
        case "controversial": return "CONTROVERSIAL"
        case "old": return "OLD"
        case "qa": return "QA"
        default: return nil
        }
    }

    private static func isSlug(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// The thread's comment-tree fragment: the same partial the web page
    /// requests for its comments.
    public static func threadFragmentURL(subreddit: String, postID: String, sort: String) -> URL? {
        let postID = postID.hasPrefix("t3_") ? String(postID.dropFirst(3)) : postID
        guard isSlug(subreddit), isSlug(postID) else { return nil }
        var query = ["render-mode=partial"]
        if let sort = shredditSort(sort) { query.append("sort=\(sort)") }
        return URL(string: origin + "/svc/shreddit/comments/r/\(subreddit)/\(postID)?" + query.joined(separator: "&"))
    }

    /// Where a "more comments" stub sits, as Shreddit's positional
    /// more-comments partial addresses it.
    public struct MorePosition: Sendable, Equatable {
        /// Child indexes from a top-level comment down to the stub's parent;
        /// empty for the thread's own trailing stub.
        public var parentPath: [Int]
        /// Replies of that parent already loaded.
        public var loaded: Int
        /// Comments Reddit says are left (top level only).
        public var remaining: Int

        public init(parentPath: [Int], loaded: Int, remaining: Int) {
            self.parentPath = parentPath
            self.loaded = loaded
            self.remaining = remaining
        }
    }

    /// The more-comments partial for `position`. The positions are the
    /// loaded tree's, so a tree that differs from Reddit's (filtered
    /// comments, a different sort) can return other comments than the stub
    /// stands for; awards are keyed by id, so that only costs coverage.
    public static func moreCommentsURL(subreddit: String, postID: String, sort: String,
                                       position: MorePosition) -> URL? {
        let postID = postID.hasPrefix("t3_") ? String(postID.dropFirst(3)) : postID
        guard isSlug(subreddit), isSlug(postID) else { return nil }
        var query: [String] = []
        if let sort = shredditSort(sort) { query.append("sort=\(sort)") }
        if position.parentPath.isEmpty {
            query += ["top-level=1", "comments-remaining=\(max(position.remaining, 1))",
                      "commentPositionOffset=\(position.loaded)"]
        } else {
            query.append("startingDepth=\(position.parentPath.count)")
            if position.loaded > 0 { query.append("commentPositionOffset=\(position.loaded)") }
            query.append("commentParentPositions=\(position.parentPath.map(String.init).joined(separator: ","))")
        }
        return URL(string: origin + "/svc/shreddit/more-comments/r/\(subreddit)/t3_\(postID)?" + query.joined(separator: "&"))
    }

    static func dialogURL(thingID: String) -> URL? {
        guard thingID.count > 3, thingID.hasPrefix("t1_") || thingID.hasPrefix("t3_"),
              isSlug(String(thingID.dropFirst(3))) else { return nil }
        return URL(string: origin + "/svc/shreddit/award-dialog/" + thingID)
    }

    // MARK: Reads

    /// The awards in the comment-tree fragment at `url`.
    public static func fetchFragment(url: URL, session: WebSessionCredential,
                                     urlSession: URLSession? = nil) async throws -> AwardHTML.Fragment {
        AwardHTML.fragment(try await get(url, session: session, urlSession: urlSession))
    }

    public static func fetchDialog(thingID: String, session: WebSessionCredential,
                                   urlSession: URLSession? = nil) async throws -> AwardDialog {
        guard let url = dialogURL(thingID: thingID) else { throw AwardError.unreadable }
        guard let dialog = AwardHTML.dialog(html: try await get(url, session: session, urlSession: urlSession)) else {
            throw AwardError.unreadable
        }
        return dialog
    }

    /// `url` is the signed link from `AwardDialog.leaderboardURL`; it only
    /// ever points at Reddit's own partials.
    public static func fetchLeaderboard(url: URL, session: WebSessionCredential,
                                        urlSession: URLSession? = nil) async throws -> AwardLeaderboard {
        guard url.host?.lowercased() == "www.reddit.com", url.path.hasPrefix("/svc/shreddit/partial/"),
              let board = AwardHTML.leaderboard(html: try await get(url, session: session, urlSession: urlSession))
        else { throw AwardError.unreadable }
        return board
    }

    private static func get(_ url: URL, session: WebSessionCredential, urlSession: URLSession?) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        // The desktop page's markup, which carries the award elements.
        request.setValue(BrowserUserAgent.desktopSafari, forHTTPHeaderField: "User-Agent")
        request.setValue("text/vnd.reddit.partial+html, text/html", forHTTPHeaderField: "Accept")
        request.setValue(origin + "/", forHTTPHeaderField: "Referer")
        let (data, response) = try await transport(urlSession).data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw AwardError.sessionExpired }
        if status == 403 || status == 429 { throw AwardError.blocked }
        guard (200..<300).contains(status) else { throw AwardError.http(status) }
        guard let html = String(data: data, encoding: .utf8) else { throw AwardError.unreadable }
        if CommentVoteInsightsClient.isChallengePage(html) { throw AwardError.blocked }
        return html
    }

    /// Without this, URLSession can drop the hand-set session cookie and the
    /// request goes out signed out; see `ModmailWebService.performOnce`.
    private static func transport(_ urlSession: URLSession?) -> URLSession {
        if let urlSession { return urlSession }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: PollVoteRedirectGuard(), delegateQueue: nil)
    }

    // MARK: Giving

    /// `CreateAwardOrder`'s variables, as the web client sends them.
    public static func orderVariables(thingID: String, awardID: String, isAnonymous: Bool,
                                      nonce: String = UUID().uuidString.lowercased()) -> [String: Any] {
        ["input": ["nonce": nonce, "thingId": thingID, "awardId": awardID, "isAnonymous": isAnonymous] as [String: Any]]
    }

    /// Gives an award with the Gold the user already has (or a free award).
    /// One attempt: the nonce makes a repeat safe for Reddit, but the user
    /// decides whether to try again.
    public static func giveAward(thingID: String, awardID: String, isAnonymous: Bool,
                                 session: WebSessionCredential) async throws -> AwardOrderResult {
        do {
            let json = try await ModmailWebService.perform(
                operation: "CreateAwardOrder",
                variables: orderVariables(thingID: thingID, awardID: awardID, isAnonymous: isAnonymous),
                session: session, referer: origin + "/", maxAttempts: 1)
            return try decodeOrder(from: json)
        } catch let error as ModmailWebService.ServiceError {
            throw AwardError(error)
        }
    }

    /// The confirmed award from a `CreateAwardOrder` reply. An `ok: true`
    /// that carries a warning, or no award, is not a success.
    public static func decodeOrder(from json: [String: Any]) throws -> AwardOrderResult {
        if let code = ModmailWebService.warningCode(in: json) {
            throw AwardError.rejected("Reddit accepted the request but did not give the award (\(code)).")
        }
        let payload = (json["data"] as? [String: Any])?["createAwardOrder"] as? [String: Any]
        guard let payload else { throw AwardError.unreadable }
        guard payload["ok"] as? Bool == true, !PollVoteService.hasErrors(payload["errors"]) else {
            let first = (payload["errors"] as? [Any])?.first as? [String: Any]
            throw AwardError.rejected(first?["message"] as? String ?? "Reddit declined the award.")
        }
        guard let award = (payload["awarding"] as? [String: Any])?["award"] as? [String: Any],
              let id = award["id"] as? String, !id.isEmpty else {
            throw AwardError.rejected("Reddit didn't confirm the award.")
        }
        let icon = ((award["staticIcon"] as? [String: Any])?["url"] as? String).flatMap(AwardHTML.secureURL)
        return AwardOrderResult(awardID: id, name: award["name"] as? String ?? id,
                                goldPrice: award["goldPrice"] as? Int ?? 0, iconURL: icon)
    }
}

extension AwardError {
    init(_ error: ModmailWebService.ServiceError) {
        switch error {
        case .requiresWebSession: self = .requiresWebSession
        case .missingCSRFToken: self = .rejected(error.localizedDescription)
        case .sessionExpired: self = .sessionExpired
        case .http(let code): self = .http(code)
        case .rateLimited: self = .blocked
        case .rejected(let message), .silentlyRejected(let message): self = .rejected(message)
        case .malformedResponse: self = .unreadable
        }
    }
}
