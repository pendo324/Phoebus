import Foundation

/// Reborn's "User Profile Pictures": a small avatar next to usernames in
/// feeds and comments. Reddit's listings don't embed the author's avatar
/// URL, so this needs a per-username lookup (`/user/<name>/about`, the same
/// endpoint `RedditRepository.fetchUserProfile` calls); this actor adds an
/// in-memory cache with a TTL so scrolling a feed doesn't re-fetch the
/// same author's avatar on every row appearance.
public actor AvatarCache {
    public static let shared = AvatarCache()

    private struct Entry {
        let url: String?
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    /// An hour is long enough that a scrolling session never re-fetches,
    /// short enough that a changed avatar shows up within a launch or two.
    private let ttl: TimeInterval = 3600

    private init() {}

    /// Returns the cached avatar URL for a username if present and
    /// fresh, without triggering a fetch. `nil` covers both "unknown"
    /// and "known to have no avatar" — callers distinguish by calling
    /// `hasEntry` if needed.
    public func cachedURL(for username: String) -> String? {
        guard let entry = entries[username.lowercased()], isFresh(entry) else { return nil }
        return entry.url
    }

    public func hasFreshEntry(for username: String) -> Bool {
        guard let entry = entries[username.lowercased()] else { return false }
        return isFresh(entry)
    }

    public func store(url: String?, for username: String) {
        entries[username.lowercased()] = Entry(url: url, fetchedAt: Date())
    }

    public func clear() {
        entries.removeAll()
    }

    // MARK: Batched prefetch (Reborn #1220)

    /// A batch in flight, by lowercased username, so a row whose author
    /// is already queued waits for it instead of racing its own lookup.
    private var pending: [String: Task<Void, Never>] = [:]

    public func awaitPending(_ username: String) async {
        await pending[username.lowercased()]?.value
    }

    /// Looks every uncached author up in batches of 100 via
    /// `user_data_by_account_ids`, instead of one `/about` each: one per
    /// comment author would spend an API-Key-Free session's whole Reddit
    /// budget. Skipped while rate-limited.
    public func prefetch(authors: [(username: String, fullname: String)], repository: RedditRepository) {
        guard RedditRateLimitHold.shared.remaining() == 0 else { return }
        var seen = Set<String>()
        let wanted = authors.filter { author in
            let key = author.username.lowercased()
            guard author.fullname.hasPrefix("t2_"), key != "[deleted]", !seen.contains(key),
                  pending[key] == nil, entries[key].map(isFresh) != true else { return false }
            seen.insert(key)
            return true
        }
        guard !wanted.isEmpty else { return }
        for start in stride(from: 0, to: wanted.count, by: 100) {
            let chunk = Array(wanted[start..<min(start + 100, wanted.count)])
            let task = Task {
                guard let found = try? await repository.fetchUserData(accountIDs: chunk.map(\.fullname)) else { return }
                for author in chunk {
                    // Returned without a picture: a known "no avatar".
                    // Missing entirely (suspended): left for the fallback.
                    if let record = found[author.fullname] { self.store(url: record.profileImage, for: author.username) }
                }
            }
            for author in chunk { pending[author.username.lowercased()] = task }
            Task {
                await task.value
                for author in chunk { self.pending[author.username.lowercased()] = nil }
            }
        }
    }

    private func isFresh(_ entry: Entry) -> Bool {
        Date().timeIntervalSince(entry.fetchedAt) < ttl
    }
}
