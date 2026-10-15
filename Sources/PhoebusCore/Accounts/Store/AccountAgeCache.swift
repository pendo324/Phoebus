import Foundation

/// Reborn's "New Account Highlight" (`HighlightAccountAge`).
///
/// Reddit's listing endpoints do not include the author's account-creation
/// date on the `t1`/`t3` object; only a per-user lookup (`/user/<name>/about`,
/// i.e. `RedditRepository.fetchUserProfile`) returns `created_utc`. Like
/// `AvatarCache`, this does a per-username lookup cached in memory with a TTL
/// so a scrolling comment thread doesn't refetch the same author's account
/// age on every row appearance.
///
/// The "NEW" badge in `CommentTreeScreen` only appears once the lookup has
/// resolved for that author; there is no guessed fallback. A pending lookup,
/// or an account that is suspended, shadowbanned or deleted (`/about` 404 or
/// 403), shows no badge. Rows by the same author share one lookup, including
/// rows that appear while it is still running.
public actor AccountAgeCache {
    public static let shared = AccountAgeCache()

    /// Reborn's exact threshold for "new account" is unknown. 30 days is the
    /// usual "very new account" cutoff in Reddit clients and moderation tooling
    /// (e.g. AutoModerator's `account_age` rules).
    public static let newAccountThreshold: TimeInterval = 30 * 24 * 60 * 60

    /// Pure decision function (kept separate/static so it's trivially
    /// unit-testable without an actor or network access) — `true` when
    /// `createdAt` is within `newAccountThreshold` of `referenceDate`.
    public static func isNewAccount(createdAt: Date, referenceDate: Date = Date()) -> Bool {
        referenceDate.timeIntervalSince(createdAt) < newAccountThreshold
    }

    /// Authors with no account page to look up: deleted users and the
    /// AutoModerator bot.
    public static func isLookupCandidate(username: String) -> Bool {
        !username.isEmpty && username != "[deleted]" && username != "AutoModerator"
    }

    private struct Entry {
        let createdAt: Date?
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var lookups: [String: Task<Date?, Never>] = [:]

    public func removeAll() { entries.removeAll() }
    /// Account-creation date never changes, so this could cache forever, but a
    /// TTL shared with `AvatarCache` keeps behavior consistent and bounds
    /// memory for very long scrolling sessions.
    private let ttl: TimeInterval = 3600

    private init() {}

    /// Returns the cached creation date for a username if present and
    /// fresh, without triggering a fetch. `nil` covers both "unknown"
    /// and "lookup failed" — callers distinguish via `hasFreshEntry`
    /// exactly like `AvatarCache`.
    public func cachedCreatedDate(for username: String) -> Date? {
        guard let entry = entries[username.lowercased()], isFresh(entry) else { return nil }
        return entry.createdAt
    }

    public func hasFreshEntry(for username: String) -> Bool {
        guard let entry = entries[username.lowercased()] else { return false }
        return isFresh(entry)
    }

    /// The creation date for `username`: the fresh cached value, the lookup
    /// already running for it, or a new `fetch`. A failed fetch is cached as
    /// "unavailable" so a failing author is not re-queried on every row.
    public func createdDate(for username: String, fetch: @escaping @Sendable () async throws -> Date) async -> Date? {
        let key = username.lowercased()
        if let entry = entries[key], isFresh(entry) { return entry.createdAt }
        if let running = lookups[key] { return await running.value }
        let lookup = Task<Date?, Never> { try? await fetch() }
        lookups[key] = lookup
        let createdAt = await lookup.value
        lookups[key] = nil
        entries[key] = Entry(createdAt: createdAt, fetchedAt: Date())
        return createdAt
    }

    public func store(createdAt: Date?, for username: String) {
        entries[username.lowercased()] = Entry(createdAt: createdAt, fetchedAt: Date())
    }

    public func clear() {
        entries.removeAll()
    }

    private func isFresh(_ entry: Entry) -> Bool {
        Date().timeIntervalSince(entry.fetchedAt) < ttl
    }
}
