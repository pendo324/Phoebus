import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProfileSocialLinksError: Error, LocalizedError, Equatable, Sendable {
    case requiresWebSession
    case rateLimited
    case rejected(String)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .requiresWebSession:
            return "Editing social links needs a Reddit web sign-in."
        case .rateLimited:
            return "Reddit is rate limiting this. Wait a moment and try again."
        case .rejected(let message):
            return message
        case .unreadable:
            return "Reddit's reply about your social links could not be read."
        }
    }
}

/// Your profile's social links, over the Shreddit GraphQL endpoint reddit.com's
/// own profile settings page uses, through a web session. The current links
/// and the platforms on offer are read from that page; `SetProfileSocialLinks`
/// adds the links it is given and `DeleteProfileSocialLinks` removes by id, and
/// both answer with the full list as it now stands.
public enum ProfileSocialLinksService {
    static let referer = "https://www.reddit.com/settings/profile"
    static let pageURL = URL(string: referer)!

    /// Loads reddit.com/settings/profile with the web session's cookie and
    /// reads the links and platforms out of it.
    public static func fetchPage(session: WebSessionCredential, urlSession: URLSession? = nil) async throws -> ProfileSettingsPage {
        var request = URLRequest(url: pageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(RedditAPIClient.webBrowserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let owned: URLSession
        if let urlSession {
            owned = urlSession
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.urlCache = nil
            owned = URLSession(configuration: config, delegate: PollVoteRedirectGuard(), delegateQueue: nil)
        }
        defer { if urlSession == nil { owned.finishTasksAndInvalidate() } }

        let (data, response) = try await owned.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 { throw ModmailWebService.ServiceError.sessionExpired }
        guard (200..<300).contains(status) else { throw ModmailWebService.ServiceError.http(status) }
        let html = String(decoding: data, as: UTF8.self)
        if let page = ProfileSettingsPage.parse(html: html) { return page }
        // A bot-check page answers 200 like the real one, as modmail's calls see.
        if http?.value(forHTTPHeaderField: "Retry-After") != nil || html.contains("Prove your humanity") {
            throw ProfileSocialLinksError.rateLimited
        }
        throw ProfileSocialLinksError.unreadable
    }

    /// Adds one link; returns the list as it now is.
    public static func add(_ draft: SocialLinkDraft, session: WebSessionCredential,
                           urlSession: URLSession? = nil) async throws -> [ProfileSocialLink] {
        guard let input = draft.input else {
            throw ProfileSocialLinksError.rejected(draft.issues.first?.message ?? "This link isn't complete.")
        }
        let json = try await perform(operation: "SetProfileSocialLinks",
                                     variables: ["input": ["socialLinks": [input]]],
                                     session: session, urlSession: urlSession)
        return try decode(json, field: "setSocialLinks")
    }

    /// Removes links by Reddit's ids; returns the list as it now is.
    public static func remove(ids: [String], session: WebSessionCredential,
                              urlSession: URLSession? = nil) async throws -> [ProfileSocialLink] {
        let json = try await perform(operation: "DeleteProfileSocialLinks",
                                     variables: ["input": ["socialLinkIds": ids]],
                                     session: session, urlSession: urlSession)
        return try decode(json, field: "deleteSocialLinks")
    }

    private static func perform(operation: String, variables: [String: Any], session: WebSessionCredential,
                                urlSession: URLSession?) async throws -> [String: Any] {
        do {
            return try await ModmailWebService.perform(operation: operation, variables: variables, session: session,
                                                       referer: referer, urlSession: urlSession)
        } catch ModmailWebService.ServiceError.rateLimited {
            throw ProfileSocialLinksError.rateLimited
        }
    }

    /// `data.<field>`: `{ok, errors, socialLinks[]}`.
    public static func decode(_ json: [String: Any], field: String) throws -> [ProfileSocialLink] {
        guard let payload = (json["data"] as? [String: Any])?[field] as? [String: Any] else {
            throw ProfileSocialLinksError.unreadable
        }
        guard payload["ok"] as? Bool == true, !PollVoteService.hasErrors(payload["errors"]) else {
            let first = (payload["errors"] as? [Any])?.first
            let said = CommentSubmitFailure.sentence((first as? [String: Any])?["message"] as? String ?? (first as? String) ?? "")
            throw ProfileSocialLinksError.rejected(said.isEmpty ? "Reddit didn't accept the change to your social links." : said)
        }
        guard let links = payload["socialLinks"] as? [[String: Any]] else { throw ProfileSocialLinksError.unreadable }
        return links.compactMap(ProfileSocialLink.init(json:))
    }
}
