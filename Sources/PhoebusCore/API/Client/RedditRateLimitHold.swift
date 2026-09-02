import Foundation

/// Reddit rate-limiting an API-Key-Free (web session) account (Reborn
/// #1220). Reddit meters each web session per ten-minute window and,
/// cookie-authenticated, never says how much is left; once spent it
/// answers 429 to everything, the feed included. After a 429 the optional
/// lookups (author avatars) stand down until the window resets, and the
/// user is told why (`.apolloRedditRateLimited`).
public final class RedditRateLimitHold: @unchecked Sendable {
    public static let shared = RedditRateLimitHold()
    private let lock = NSLock()
    private var until: TimeInterval = 0

    public init() {}

    /// How long to hold after a 429: the reset the response states
    /// (`x-ratelimit-reset`, else `Retry-After`), otherwise until the next
    /// ten-minute mark where Reddit's windows end; never under 30 s (a 429
    /// just before a mark shouldn't send everything straight back) and
    /// never over one window.
    public static func holdSeconds(reset: String?, retryAfter: String?, now: TimeInterval) -> TimeInterval {
        func seconds(_ value: String?) -> Double? {
            guard let value = value?.trimmingCharacters(in: .whitespaces), let s = Double(value), s > 0 else { return nil }
            return s
        }
        let wait = seconds(reset) ?? seconds(retryAfter) ?? (600 - now.truncatingRemainder(dividingBy: 600))
        return min(max(wait, 30), 600)
    }

    /// Records a 429. Returns the hold's length when this starts a new
    /// hold (so the notice shows once), nil when one was already running.
    @discardableResult
    public func record(reset: String?, retryAfter: String?, now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval? {
        let wait = Self.holdSeconds(reset: reset, retryAfter: retryAfter, now: now)
        lock.lock(); defer { lock.unlock() }
        let newlyLimited = until <= now
        until = max(until, now + wait)
        return newlyLimited ? wait : nil
    }

    /// Seconds left on the hold; 0 when none.
    public func remaining(now: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return max(0, until - now)
    }

    /// Test-facing.
    public func reset() {
        lock.lock(); until = 0; lock.unlock()
    }

    /// Reborn's toast detail.
    public static func detail(seconds: TimeInterval) -> String {
        seconds < 60 ? "Try again in under a minute" : "Try again in about \(Int((seconds / 60).rounded(.up))) min"
    }
}

public extension Notification.Name {
    /// The active web session hit Reddit's limit; `userInfo["seconds"]`.
    static let apolloRedditRateLimited = Notification.Name("ApolloRedditRateLimited")
}
