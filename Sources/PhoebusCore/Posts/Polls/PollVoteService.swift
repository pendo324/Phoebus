import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reborn's poll voting: a GraphQL mutation (`UpdatePostPollVoteState`) at
/// `/svc/shreddit/graphql`. Needs the cookie web-session transport (CSRF
/// token parsed from the cookie header); unavailable for OAuth-only
/// sign-ins.
public enum PollVoteService {
    public enum VoteError: LocalizedError {
        case requiresWebSession
        case missingCSRFToken
        case network(Error)
        case rejected(String)
        /// HTTP 401: the cookie session is dead. Only this case may
        /// clear the stored session; 403 (refused vote) must not, since
        /// it says nothing about session validity.
        case sessionExpired

        public var errorDescription: String? {
            switch self {
            case .requiresWebSession:
                return "Poll voting requires signing in via a web session (Settings > Accounts)."
            case .missingCSRFToken:
                return "Phoebus could not find a CSRF token in this session."
            case .network(let error):
                return error.localizedDescription
            case .rejected(let message):
                return message
            case .sessionExpired:
                return "The Reddit web session expired. Sign in again and retry."
            }
        }
    }

    private static let operationName = "UpdatePostPollVoteState"

    /// - Parameters:
    ///   - postFullname: the post's real Reddit fullname, e.g. "t3_abc123".
    ///   - optionID: the `RedditPollOption.id` the user picked.
    ///   - session: the signed-in web session (cookie + optional modhash).
    public static func vote(postFullname: String, optionID: String, session: WebSessionCredential) async throws {
        guard let csrfToken = csrfToken(fromCookieHeader: session.cookieHeader) else {
            throw VoteError.missingCSRFToken
        }

        let input: [String: String] = ["postId": postFullname, "optionId": optionID]
        let body: [String: Any] = [
            "operation": operationName,
            "variables": ["input": input],
            "csrf_token": csrfToken
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw VoteError.network(URLError(.cannotCreateFile))
        }

        var request = URLRequest(url: URL(string: "https://www.reddit.com/svc/shreddit/graphql")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Csrf-Token")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("https://www.reddit.com", forHTTPHeaderField: "Origin")
        let baseID = postFullname.hasPrefix("t3_") ? String(postFullname.dropFirst(3)) : postFullname
        request.setValue("https://www.reddit.com/comments/\(baseID)", forHTTPHeaderField: "Referer")

        // `httpShouldSetCookies = false` is load-bearing: URLSession would
        // otherwise manage the Cookie header from its own empty storage and could
        // drop the session cookie, sending an unauthenticated vote that Reddit
        // answers 200 as a no-op.
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        // Never forward the session cookie across a cross-origin redirect: it
        // is either an auth/challenge flow or a server change, so fail closed.
        let redirectGuard = PollVoteRedirectGuard()
        let session_ = URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
        defer { session_.finishTasksAndInvalidate() }
        let (data, response) = try await session_.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        let cookieCount = session.cookieHeader.split(separator: ";").count
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let vote = (json?["data"] as? [String: Any])?["updatePostPollVoteState"]

        var mutationAccepted = false
        if let boolVote = vote as? Bool {
            mutationAccepted = boolVote
        } else if let dictVote = vote as? [String: Any] {
            mutationAccepted = (dictVote["ok"] as? Bool == true)
                && !Self.hasErrors(dictVote["errors"])
        }

        let topErrors = json?["errors"] as? [Any]
        let hasTopErrors = Self.hasErrors(json?["errors"])
        let ok = (200..<300).contains(status) && mutationAccepted && !hasTopErrors

        guard ok else {
            let serverMessage = (topErrors?.first as? [String: Any])?["message"] as? String
            let message: String
            switch status {
            case 429: message = "Reddit is rate limiting votes. Wait a moment before trying again."
            case 401: throw VoteError.sessionExpired
            case 403: message = serverMessage ?? "Reddit did not authorize this vote. Refresh the poll and try again."
            default:
                if let serverMessage {
                    message = serverMessage
                } else if (200..<300).contains(status) {
                    // Reddit accepts the request but reports no success. The shape of
                    // `data.updatePostPollVoteState` tells "not signed in for this
                    // mutation" (null) from "vote refused" (ok:false), so it goes in the error.
                    let shape: String
                    if vote == nil || vote is NSNull {
                        shape = "no vote state returned"
                    } else if let dict = vote as? [String: Any] {
                        let keys = dict.keys.sorted().joined(separator: ",")
                        shape = "vote state {\(keys)}"
                    } else {
                        shape = "vote state \(type(of: vote))"
                    }
                    message = "Reddit did not confirm the poll vote (\(shape), modhash \(session.isReadOnly ? "absent" : "present"), \(cookieCount) cookies)."
                } else {
                    message = "Reddit returned HTTP \(status)."
                }
            }
            throw VoteError.rejected(message)
        }
    }

    /// Whether a GraphQL `errors` value represents an actual error.
    /// Reddit answers an accepted vote with `{ "ok": true, "errors": null
    /// }`; `JSONSerialization` bridges JSON null to `NSNull`, not Swift
    /// `nil`, so the null case must be checked explicitly or a successful
    /// vote reads as a failure.
    public static func hasErrors(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        // A counted collection is an error only when non-empty; any other
        // non-null value is an error.
        if let array = value as? [Any] { return !array.isEmpty }
        if let dictionary = value as? [String: Any] { return !dictionary.isEmpty }
        return true
    }

    /// Parses `name=value` pairs out of a semicolon-delimited cookie header
    /// and returns the `csrf_token` value.
    public static func csrfToken(fromCookieHeader header: String) -> String? {
        for component in header.split(separator: ";") {
            guard let equalsIndex = component.firstIndex(of: "=") else { continue }
            let name = component[component.startIndex..<equalsIndex].trimmingCharacters(in: .whitespaces)
            if name == "csrf_token" {
                let value = component[component.index(after: equalsIndex)...]
                return value.isEmpty ? nil : String(value)
            }
        }
        return nil
    }
}


/// Blocks cross-origin redirects for the poll vote's isolated session.
/// Both poll endpoints are fixed HTTPS www.reddit.com URLs, so anything
/// else fails closed rather than forwarding a live account session.
final class PollVoteRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        let trusted = url?.scheme?.lowercased() == "https"
            && url?.host?.lowercased() == "www.reddit.com"
        completionHandler(trusted ? request : nil)
    }
}
