import Foundation

/// Why a `/user/<name>/about` lookup (avatar, account age) failed, and so
/// whether to remember it. Only an account that Reddit says is gone
/// (suspended, deleted, shadowbanned) is a real miss worth the cache's TTL;
/// a dropped connection, a 429 or a 5xx says nothing about the account, so
/// its avatar and NEW badge must come back once Reddit does.
public enum ProfileLookupFailure: Equatable, Sendable {
    /// 403/404/410: the account has no page.
    case noSuchAccount
    /// 429: Reddit's window is spent; `RedditRateLimitHold` says when to ask again.
    case rateLimited
    /// The lookup was abandoned (the row scrolled away).
    case cancelled
    /// Offline, timed out, 5xx, undecodable.
    case transient

    public init(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            self = .cancelled
        } else if error is RedditRateLimitHold.Held {
            self = .rateLimited
        } else if case RedditAPIError.httpError(let status, _) = error {
            switch status {
            case 403, 404, 410: self = .noSuchAccount
            case 429: self = .rateLimited
            default: self = .transient
            }
        } else {
            self = .transient
        }
    }

    /// Whether the cache may store "no avatar / no date" for the account.
    public var isDefinitiveMiss: Bool { self == .noSuchAccount }
}
