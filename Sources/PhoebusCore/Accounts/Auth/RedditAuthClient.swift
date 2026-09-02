import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reddit OAuth2 "installed client" flow, matching Apollo's
/// (ssl.reddit.com/api/v1/authorize with duration=permanent,
/// oauth.reddit.com token exchange).
///
/// IMPORTANT: this uses a placeholder client ID. You must register your own
/// app at https://www.reddit.com/prefs/apps to get a client ID — do not
/// reuse Apollo's original credentials, which belong to its developer.
public enum RedditOAuthConfig {
    /// Build-time fallback client ID/redirect URI. A user's saved
    /// `CustomAPISettings` (Settings > Custom API) overrides these at launch
    /// via `CustomAPISettingsStore.applyPersisted()`; the separate `default*`
    /// constants give "reset to default" a value to reset to.
    public static let defaultClientID = "REPLACE_WITH_YOUR_CLIENT_ID"
    public static let defaultRedirectURI = "phoebus://oauth-callback"
    public nonisolated(unsafe) static var clientID = RedditOAuthConfig.defaultClientID
    public nonisolated(unsafe) static var redirectURI = RedditOAuthConfig.defaultRedirectURI
    /// The "Reddit API Secret" field. Empty by default: Reddit's "installed
    /// app" type has no secret (only "web app"/confidential apps do).
    public nonisolated(unsafe) static var clientSecret = ""
    public static let authorizeURL = "https://ssl.reddit.com/api/v1/authorize.compact"
    public static let accessTokenURL = "https://www.reddit.com/api/v1/access_token"
    public static let scope = "identity edit flair history modconfig modflair modlog modposts modwiki mysubreddits privatemessages read report save submit subscribe vote wikiedit wikiread"
}

public struct RedditCredential: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiration: Date
    public var isPermanent: Bool

    public init(accessToken: String, refreshToken: String?, expiration: Date, isPermanent: Bool) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiration = expiration
        self.isPermanent = isPermanent
    }

    public var isExpired: Bool { Date() >= expiration }
}

public actor RedditAuthClient {
    private let session: URLSession
    private let credentialStore: CredentialStore
    private let webSessionStore: WebSessionStore
    public private(set) var credential: RedditCredential?
    /// Reborn's "Web JSON" OAuth-free transport (see `WebSessionCredential`):
    /// when set, `RedditAPIClient` routes requests to `www.reddit.com` with
    /// `Cookie`/`X-Modhash` headers instead of an OAuth bearer token. Mutually
    /// exclusive with `credential` in normal use, but both may coexist
    /// (Reborn's "Switch to API Key" / "Switch to Keyless" keep the unused
    /// credential stored but dormant).
    public private(set) var webSession: WebSessionCredential?

    public init(session: URLSession = .shared, credentialStore: CredentialStore = .platformDefault, webSessionStore: WebSessionStore = .platformDefault) {
        self.session = session
        self.credentialStore = credentialStore
        self.webSessionStore = webSessionStore
        self.credential = credentialStore.load()
        self.webSession = webSessionStore.load()
    }

    /// Stores a web session harvested by `WebSessionLoginScreen`, completing
    /// Reborn's OAuth-free sign-in flow.
    public func setWebSession(_ session: WebSessionCredential) {
        webSession = session
        try? webSessionStore.save(session)
    }

    /// Clears the live transport session only when it belongs to
    /// `username`. Used after Reddit reports HTTP 401 on a web-feature
    /// request: a keyless account's dead cookie must stop being used
    /// for transport too, but an auxiliary (poll-only) session dying on
    /// an OAuth account must never disturb that account's transport.
    public func clearWebSessionIfMatching(username: String) {
        guard webSession?.username == username.lowercased() else { return }
        signOutWebSession()
    }

    public func signOutWebSession() {
        webSession = nil
        webSessionStore.clear()
    }

    /// Build the browser-facing authorize URL (state should be a random
    /// per-request nonce you verify on callback — CSRF protection).
    public func buildAuthorizeURL(state: String) -> URL {
        var components = URLComponents(string: RedditOAuthConfig.authorizeURL)!
        components.queryItems = [
            .init(name: "client_id", value: RedditOAuthConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "state", value: state),
            .init(name: "redirect_uri", value: RedditOAuthConfig.redirectURI),
            .init(name: "duration", value: "permanent"),
            .init(name: "scope", value: RedditOAuthConfig.scope),
        ]
        return components.url!
    }

    /// Exchange an authorization `code` (from the redirect callback) for
    /// access + refresh tokens.
    public func exchangeCode(_ code: String) async throws {
        var request = URLRequest(url: URL(string: RedditOAuthConfig.accessTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let auth = "\(RedditOAuthConfig.clientID):\(RedditOAuthConfig.clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")

        let body = FormEncoding.encode(["grant_type": "authorization_code", "code": code,
                                        "redirect_uri": RedditOAuthConfig.redirectURI])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RedditAPIError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        isSessionExpired = false
        credential = RedditCredential(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiration: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            isPermanent: token.refreshToken != nil
        )
        try? credentialStore.save(credential!)
    }

    /// Set when Reddit refuses this account's refresh token (a password
    /// change revokes it: `invalid_grant`). Requests then fail fast with
    /// `sessionExpired` instead of retrying the dead token, until a new
    /// credential is signed in (Reborn #1200).
    public private(set) var isSessionExpired = false

    public func refreshIfNeeded() async throws {
        guard let credential, credential.isExpired else { return }
        try await refresh()
    }

    /// The refresh in flight, shared by every caller so concurrent requests
    /// don't each refresh and a refused duplicate doesn't expire the session.
    private var refreshTask: Task<Void, Error>?

    /// Forces a refresh, used when Reddit answers 401 to a token that
    /// has not reached its expiry yet. Passing the token that got the
    /// 401 skips the refresh when another caller already replaced it.
    public func refresh(replacing failedToken: String? = nil) async throws {
        if let failedToken, let current = credential?.accessToken, current != failedToken { return }
        if let refreshTask {
            try await refreshTask.value
            return
        }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func performRefresh() async throws {
        if isSessionExpired { throw RedditAPIError.sessionExpired }
        guard let credential, let refreshToken = credential.refreshToken else {
            if self.credential != nil { isSessionExpired = true; throw RedditAPIError.sessionExpired }
            return
        }

        var request = URLRequest(url: URL(string: RedditOAuthConfig.accessTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let auth = "\(RedditOAuthConfig.clientID):\(RedditOAuthConfig.clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.httpBody = FormEncoding.encode(["grant_type": "refresh_token", "refresh_token": refreshToken]).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if TokenRefreshOutcome.classify(status: status, body: data) == .revoked {
            isSessionExpired = true
            NotificationCenter.default.post(name: .apolloSessionExpired, object: nil)
            throw RedditAPIError.sessionExpired
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.credential = RedditCredential(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            expiration: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            isPermanent: true
        )
        try? credentialStore.save(self.credential!)
    }

    /// Clears stored credential (sign out). Also clears any web session: sign-out
    /// logs the account out entirely, whichever transport it used.
    public func signOut() {
        credential = nil
        credentialStore.clear()
        signOutWebSession()
    }

    /// True if a persisted credential was found at launch (allows the
    /// app to skip the login screen without a network round-trip). A
    /// harvested web session counts as a fully signed-in state.
    public var isSignedIn: Bool {
        credential != nil || webSession != nil
    }
}

extension CredentialStore where Self == KeychainCredentialStoreBox {
    /// Type-erased default so `RedditAuthClient`'s initializer doesn't
    /// need to name a concrete platform type at every call site.
    public static var platformDefault: KeychainCredentialStoreBox { KeychainCredentialStoreBox() }
}

/// Type-erasing box so callers can write `.platformDefault` regardless
/// of which concrete store (Keychain vs in-memory fallback) backs it.
public struct KeychainCredentialStoreBox: CredentialStore {
    private let box: any CredentialStore
    public init() {
        #if canImport(Security)
        box = KeychainCredentialStore()
        #else
        box = InMemoryCredentialStore()
        #endif
    }
    public func save(_ credential: RedditCredential) throws { try box.save(credential) }
    public func load() -> RedditCredential? { box.load() }
    public func clear() { box.clear() }
}

/// What a token-refresh response means. Reddit answers a revoked
/// refresh token (password change, app access removed) with HTTP 400 or
/// 401 and `{"error": "invalid_grant"}`; rate limits and outages are not
/// revocations and must not sign the account out.
public enum TokenRefreshOutcome: Equatable, Sendable {
    case ok, revoked, transient

    public static func classify(status: Int, body: Data) -> TokenRefreshOutcome {
        if (200..<300).contains(status) {
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let error = json["error"] as? String, error == "invalid_grant" {
                return .revoked
            }
            return .ok
        }
        if status == 400 || status == 401 { return .revoked }
        return .transient
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let scope: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case refreshToken = "refresh_token"
    }
}
