import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Generic Reddit REST client (getPath/postPath/postListingTask style, as in
/// Apollo's RedditKit).
public actor RedditAPIClient {
    private let auth: RedditAuthClient
    private let session: URLSession
    /// Reddit's OAuth API host. Overridable only so the app can be pointed at
    /// a local mock server for end-to-end checks (e.g. feed pagination) that
    /// otherwise need a signed-in account and live network. Never assigned in
    /// normal operation.
    nonisolated(unsafe) public static var baseURLOverride: URL?

    private var baseURL: URL { Self.baseURLOverride ?? URL(string: "https://oauth.reddit.com")! }

    /// Set from `CustomAPISettingsStore` when the user configures a
    /// personalized User-Agent (Settings > Custom API); `nil` falls back to
    /// the build-time default. A shared default User-Agent is a fingerprinting
    /// risk for anyone using their own Reddit API app (Reborn's README).
    public nonisolated(unsafe) static var userAgentOverride: String?

    public init(auth: RedditAuthClient, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    private func authorizedRequest(path: String, method: String, parameters: [String: String]) async throws -> URLRequest {
        // Apollo-Reborn's "Web JSON" transport: when the user signed
        // in via `WebSessionLoginScreen` instead of OAuth, requests are
        // re-pointed at www.reddit.com with a `Cookie:` header (and
        // `X-Modhash:` for writes) instead of an oauth.reddit.com
        // bearer token.
        if let webSession = await auth.webSession {
            return webJSONRequest(path: path, method: method, parameters: parameters, session: webSession)
        }

        try await auth.refreshIfNeeded()
        guard let credential = await auth.credential else {
            throw RedditAPIError.notAuthenticated
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var request: URLRequest

        if method == "GET" {
            // Without `raw_json=1`, Reddit's API HTML-entity-escapes
            // string fields (titles, thumbnail URLs: `&` becomes
            // `&amp;`), which breaks thumbnail loading since the CDN
            // then sees a garbage query-param name and 403s.
            var queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
            queryItems.append(URLQueryItem(name: "raw_json", value: "1"))
            components.queryItems = queryItems
            request = URLRequest(url: components.url!)
        } else {
            request = URLRequest(url: components.url!)
            // `raw_json=1` is needed on POSTs too: `/api/morechildren` otherwise
            // returns comments in Reddit's legacy HTML-embedded shape.
            var bodyParameters = parameters
            bodyParameters["raw_json"] = "1"
            let body = FormEncoding.encode(bodyParameters)
            request.httpBody = body.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        request.httpMethod = method
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.oauthUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Builds a `www.reddit.com`-targeted, cookie-authenticated request.
    /// Authorization header omitted, `Cookie` set explicitly with
    /// `httpShouldHandleCookies = false` (this exact harvested snapshot
    /// wins over any system cookie jar), and `X-Modhash` +
    /// `Origin`/`Referer` attached for state-changing requests.
    public static var oauthUserAgent: String {
        userAgentOverride ?? "Phoebus/1.0 (by /u/your_username)"
    }

    public static let webBrowserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36"

    private func webJSONRequest(path: String, method: String, parameters: [String: String], session: WebSessionCredential) -> URLRequest {
        // Unlike `oauth.reddit.com`, which serves JSON for every path,
        // `www.reddit.com` only serves JSON for listing pages when the
        // path carries an explicit ".json" suffix, otherwise it returns
        // the HTML page. `/api/*` paths are already JSON-native on both
        // hosts and must not get a ".json" suffix appended.
        var effectivePath = path
        // A handful of GET `/api/*` read endpoints 404 on www.reddit.com
        // without the suffix, whereas write endpoints appear bare.
        // `/api/v1/user/<name>/trophies` needs the suffix too and is
        // matched by prefix/suffix since the username is dynamic.
        let apiPathsNeedingJSONSuffix = [
            "/api/subreddit_autocomplete_v2",
            "/api/search_reddit_names",
            "/api/info",
            "/api/multi/mine",
            "/api/user_data_by_account_ids",
        ]
        let isUserTrophiesPath = effectivePath.hasPrefix("/api/v1/user/") && effectivePath.hasSuffix("/trophies")
        let isMeTrophiesPath = effectivePath == "/api/v1/me/trophies"
        if apiPathsNeedingJSONSuffix.contains(effectivePath) || isUserTrophiesPath || isMeTrophiesPath {
            effectivePath += ".json"
        } else if !effectivePath.hasPrefix("/api/"), !effectivePath.hasSuffix(".json") {
            while effectivePath.hasSuffix("/"), effectivePath.count > 1 {
                effectivePath.removeLast()
            }
            effectivePath = effectivePath.isEmpty || effectivePath == "/" ? "/.json" : effectivePath + ".json"
        }
        // `baseURLOverride` also redirects the web-session transport, so a
        // local mock server can stand in for both hosts during verification.
        let webBase = Self.baseURLOverride ?? URL(string: "https://www.reddit.com")!
        var components = URLComponents(url: webBase.appendingPathComponent(effectivePath), resolvingAgainstBaseURL: false)!
        var request: URLRequest

        if method == "GET" {
            // Same `raw_json=1` need as the OAuth transport.
            var queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
            queryItems.append(URLQueryItem(name: "raw_json", value: "1"))
            components.queryItems = queryItems
            request = URLRequest(url: components.url!)
        } else {
            request = URLRequest(url: components.url!)
            // Same `raw_json=1` need as the OAuth POST branch.
            var bodyParameters = parameters
            bodyParameters["raw_json"] = "1"
            let body = FormEncoding.encode(bodyParameters)
            request.httpBody = body.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            if let modhash = session.modhash, !modhash.isEmpty {
                request.setValue(modhash, forHTTPHeaderField: "X-Modhash")
            }
            request.setValue("https://www.reddit.com", forHTTPHeaderField: "Origin")
            request.setValue("https://www.reddit.com/", forHTTPHeaderField: "Referer")
        }

        request.httpMethod = method
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = false
        // A browser User-Agent, never the OAuth one: reusing the OAuth
        // identity on cookie-authenticated www.reddit.com requests
        // makes Reddit classify them as third-party Data API traffic
        // and answer with a 403 "blocked by network security" page.
        request.setValue(Self.webBrowserUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    public func get(path: String, parameters: [String: String] = [:]) async throws -> Data {
        try await send(path: path, method: "GET", parameters: parameters)
    }

    /// Sends an authorized request. A 401 on the OAuth transport means
    /// the access token died early (Reddit revokes it on a password
    /// change), so the token is refreshed once and the request retried;
    /// a refused refresh surfaces as `sessionExpired`.
    private func send(path: String, method: String, parameters: [String: String]) async throws -> Data {
        let request = try await authorizedRequest(path: path, method: method, parameters: parameters)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429, await auth.webSession != nil,
           let wait = RedditRateLimitHold.shared.record(reset: http.value(forHTTPHeaderField: "x-ratelimit-reset"),
                                                        retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
            // Only web sessions: an API-key account's 429s are per-request
            // and carry their own headers.
            await MainActor.run {
                NotificationCenter.default.post(name: .apolloRedditRateLimited, object: nil, userInfo: ["seconds": wait])
            }
        }
        if (response as? HTTPURLResponse)?.statusCode == 401, await auth.webSession == nil {
            try await auth.refresh(replacing: Self.bearerToken(of: request))
            let retry = try await authorizedRequest(path: path, method: method, parameters: parameters)
            let (retryData, retryResponse) = try await session.data(for: retry)
            try Self.validate(retryResponse, data: retryData)
            return retryData
        }
        try Self.validate(response, data: data)
        return data
    }

    /// Whether the current sign-in is a cookie-authed web session, as
    /// opposed to a real OAuth bearer token. Exposed so higher-level
    /// callers can route around endpoints that behave differently
    /// under the two transports.
    public var isUsingWebSession: Bool {
        get async { await auth.webSession != nil }
    }

    /// The active web session, when signed in via that transport.
    /// Exposed for `PollVoteService`, which needs the raw cookie header
    /// and CSRF token directly rather than through `get`/`post`.
    public var webSessionCredential: WebSessionCredential? {
        get async { await auth.webSession }
    }

    /// Forwards to `RedditAuthClient.clearWebSessionIfMatching`, so a
    /// 401 on a poll vote can retire the dead transport session without
    /// `RedditRepository` reaching past this client into `auth`.
    public func clearWebSessionIfMatching(username: String) async {
        await auth.clearWebSessionIfMatching(username: username)
    }

    @discardableResult
    public func post(path: String, parameters: [String: String] = [:]) async throws -> Data {
        try await send(path: path, method: "POST", parameters: parameters)
    }

    /// Posts a raw JSON body rather than form-encoded parameters:
    /// `/api/submit_gallery_post.json` requires this.
    @discardableResult
    public func postJSON(path: String, body: [String: Any]) async throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: body)
        let request = try await jsonRequest(path: path, payload: payload)
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401, await auth.webSession == nil {
            try await auth.refresh(replacing: Self.bearerToken(of: request))
            let (retryData, retryResponse) = try await session.data(for: try await jsonRequest(path: path, payload: payload))
            try Self.validate(retryResponse, data: retryData)
            return retryData
        }
        try Self.validate(response, data: data)
        return data
    }

    private static func bearerToken(of request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) }
    }

    private func jsonRequest(path: String, payload: Data) async throws -> URLRequest {
        // Keyless accounts: the same endpoint on www.reddit.com with the
        // cookie and modhash, as the form-encoded path does.
        if let webSession = await auth.webSession {
            var request = webJSONRequest(path: path, method: "POST", parameters: [:], session: webSession)
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return request
        }
        try await auth.refreshIfNeeded()
        guard let credential = await auth.credential else {
            throw RedditAPIError.notAuthenticated
        }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "raw_json", value: "1")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.oauthUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Reddit's multireddit update/rename endpoint
    /// (`PUT /api/multi/<path>`) uses PUT rather than POST, unlike
    /// almost everything else in the API.
    @discardableResult
    public func put(path: String, parameters: [String: String] = [:]) async throws -> Data {
        try await send(path: path, method: "PUT", parameters: parameters)
    }

    /// Per-subreddit multireddit removal
    /// (`DELETE /api/multi/<multipath>/r/<srname>`).
    @discardableResult
    public func delete(path: String, parameters: [String: String] = [:]) async throws -> Data {
        try await send(path: path, method: "DELETE", parameters: parameters)
    }

    /// Reddit listings are paginated via `after`/`before` fullname cursors.
    public func getListing(path: String, parameters: [String: String] = [:], after: String? = nil, limit: Int = 25) async throws -> RedditListing {
        var params = parameters
        params["limit"] = String(limit)
        if let after { params["after"] = after }
        let account = SiriContentCapture.activeAccount
        let data = try await get(path: path, parameters: params)
        let listing = try JSONDecoder.reddit.decode(RedditListing.self, from: data)
        // Reborn "Siri & Spotlight" (#1299): loaded posts and subscriptions feed the index.
        SiriContentCapture.listingLoaded(listing, requestedBy: account)
        return listing
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw RedditAPIError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}

/// `application/x-www-form-urlencoded` bodies. `.urlQueryAllowed` leaves
/// `&`, `=` and `+` alone, which would truncate "A & B" and turn `\w+`
/// into `\w `. Only the RFC 3986 unreserved characters pass through.
public enum FormEncoding {
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Keys sorted, so a body is stable for a given dictionary.
    public static func encode(_ parameters: [String: String]) -> String {
        parameters.sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }
}

public enum RedditAPIError: Error {
    case notAuthenticated
    /// Reddit refused the account's refresh token; the user must sign
    /// in to this account again.
    case sessionExpired
    case httpError(status: Int, body: String)
    case decodingFailed(String)
}

extension JSONDecoder {
    public static let reddit: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
