import Foundation

/// The eviction rules behind the short-lived comment-tree cache.
///
/// Extracted from `RecentCommentTreeCache` so the arithmetic can be tested
/// on the host. That cache exists to survive a view REBUILD: swiping
/// forward into a post reconstructs `PostDetailScreen`, whose `@StateObject`
/// comment store starts empty, so without the cache the comments would
/// blank and refetch, which reads as the post reloading.
///
/// It is deliberately NOT a general comment cache. The window is short
/// enough that a post returned to later fetches current comments, and
/// long enough that a swipe back and forth reuses what the user was
/// already looking at.
public enum RecentEntryPolicy {
    /// How long an entry stays usable after it was last touched.
    ///
    /// Comfortably longer than an interactive transition and the
    /// hesitation around it, far shorter than a browsing session.
    public static let lifetime: TimeInterval = 10

    /// How many posts are kept, so moving between a few posts is all
    /// instant without holding a whole session in memory.
    public static let capacity = 5

    /// Whether an entry stored (or last used) `age` seconds ago may
    /// still be served.
    public static func isFresh(age: TimeInterval) -> Bool {
        age >= 0 && age < lifetime
    }

    /// Which keys to drop, oldest first, once `count` entries are held.
    ///
    /// Ages are paired with their keys rather than sorted in place, so
    /// eviction is by age and never by dictionary order - which is not
    /// stable and would otherwise evict an arbitrary entry.
    public static func keysToEvict(agesByKey: [String: TimeInterval]) -> [String] {
        guard agesByKey.count > capacity else { return [] }
        return agesByKey
            .sorted { $0.value > $1.value }
            .prefix(agesByKey.count - capacity)
            .map(\.key)
    }
}
