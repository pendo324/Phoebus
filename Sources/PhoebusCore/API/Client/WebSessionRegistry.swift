import Foundation

/// Per-account web-session resolution (Reborn's web session store). A single
/// global cookie/modhash/username would divert the entire request pipeline
/// to cookie transport, so an OAuth account and a cookie account could never
/// coexist, and poll voting would be impossible for OAuth accounts (which
/// have no transport session).
///
/// Storage reuses `AccountStore`, which already persists a `webSession` per
/// `StoredAccount`. Reborn's primary/auxiliary split is encoded by
/// `StoredAccount.isKeyless`:
///
///  - **primary**: `webSession != nil && oauthCredential == nil`; the
///    account authenticates by cookie (the API-Key-Free case).
///  - **auxiliary**: `webSession != nil && oauthCredential != nil`; the
///    account authenticates by OAuth and the cookie exists only so
///    web-only features (Polls, Chat, modern Modmail) work.
///
/// The two lookups below keep that split enforceable, separating the
/// transport/identity spine from web-only features.
public enum WebSessionRegistry {
    /// Resolves the account holding `username`. Injected by
    /// `AccountManager` at startup, matching the existing
    /// `FavoriteSubredditsAccountContext.currentUsernameProvider`
    /// pattern (there is no shared `AccountStore` singleton).
    nonisolated(unsafe) public static var accountProvider: (String) -> StoredAccount? = { _ in nil }

    /// Removes the stored session for an account. Injected alongside
    /// `accountProvider`.
    nonisolated(unsafe) public static var removeHandler: (String) -> Void = { _ in }

    /// The PRIMARY (transport) session for `username`, or `nil` when
    /// that account authenticates via OAuth.
    ///
    /// An auxiliary session is intentionally never returned here: this
    /// is the transport/identity spine, and a poll credential stored
    /// alongside a live OAuth account must not surface as its transport
    /// session.
    public static func primarySession(for username: String) -> WebSessionCredential? {
        guard let account = accountProvider(username.lowercased()), account.isKeyless else { return nil }
        return account.webSession
    }

    /// Any stored session usable by Reddit's web-only features —
    /// primary or auxiliary. Polls, Chat and modern Modmail use this;
    /// nothing on the transport spine may.
    public static func featureSession(for username: String) -> WebSessionCredential? {
        accountProvider(username.lowercased())?.webSession
    }

    /// Removes the stored session for `username` — on account delete,
    /// before re-harvesting, or when Reddit reports the session dead
    /// (HTTP 401 only; see `PollVoteService.VoteError.sessionExpired`).
    public static func remove(username: String) {
        removeHandler(username.lowercased())
    }
}
