import Foundation

/// A web session could not produce a bearer for the endpoints that refuse
/// its cookie.
public struct WebBearerUnavailableError: Error, LocalizedError {
    public init() {}
    public var errorDescription: String? {
        "Couldn't get a token from your Reddit web session. Try again, or sign in to the account again."
    }
}

/// The web bearer of each web-session account: its own `token_v2` while that
/// lasts, else one minted through the browser (`RedditChatClient.browserMinter`).
/// Reddit Chat and `RedditAPIClient`'s moderator requests
/// (`WebBearerRouting`) share it, so an account mints once. Minting costs a
/// round trip and the token is good for a day; expiry is read out of the JWT.
public actor WebBearerCache {
    public static let shared = WebBearerCache()

    public typealias Minter = @Sendable (_ cookieHeader: String) async throws -> String

    private let mint: Minter
    private var bearers: [String: String] = [:]
    private var minting: [String: Task<String, Error>] = [:]

    public init(mint: @escaping Minter = { try await RedditChatClient.mintBearer(cookieHeader: $0) }) {
        self.mint = mint
    }

    /// A usable bearer for `session`'s account. `forceMint` skips the cache
    /// and the session's own `token_v2`: both were just rejected.
    public func bearer(for session: WebSessionCredential, forceMint: Bool = false, now: Date = Date()) async throws -> String {
        let account = session.username.lowercased()
        if !forceMint {
            if let cached = bearers[account], !RedditChatClient.isExpired(cached, now: now) { return cached }
            if let stored = RedditChatClient.storedBearer(cookieHeader: session.cookieHeader, now: now) {
                bearers[account] = stored
                return stored
            }
        }
        // Concurrent callers share one mint; it is a full browser page load.
        if let inFlight = minting[account] { return try await inFlight.value }
        let cookieHeader = session.cookieHeader
        let mint = self.mint
        let task = Task<String, Error> {
            let token = try await mint(cookieHeader)
            // A signed-out cookie is minted an anonymous token (subject
            // "loid…") that cannot act as the account (Reborn #1292).
            if (RedditChatClient.claims(ofJWT: token)?["sub"] as? String)?.hasPrefix("loid") == true {
                throw RedditChatClient.ChatError.mintFailed
            }
            return token
        }
        minting[account] = task
        defer { minting[account] = nil }
        let token = try await task.value
        bearers[account] = token
        return token
    }

    /// Drops the account's cached bearer after Reddit rejected it.
    public func clear(account: String) {
        bearers[account.lowercased()] = nil
    }
}
