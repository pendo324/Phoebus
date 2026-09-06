import Foundation

/// Apollo's `NewCommentsTracker`: remembers which comment IDs were present
/// at the last visit to a post so the next visit can highlight genuinely
/// new ones. Local-only (UserDefaults), since Reddit has no per-user
/// "seen comments" concept.
public enum NewCommentsTracker {
    private static let key = "com.pendo324.Phoebus.seenCommentIDs"
    /// Caps total tracked (post -> [commentIDs]) entries to keep
    /// UserDefaults bounded; oldest-inserted posts are evicted first.
    private static let maxTrackedPosts = 200

    private static func loadAll() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveAll(_ dict: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Comment IDs not present at the last visit. Empty on a post's first
    /// visit, so nothing is highlighted then (as in Apollo).
    public static func newCommentIDs(postID: String, currentIDs: [String]) -> Set<String> {
        guard let previouslySeen = loadAll()[postID] else { return [] }
        let previousSet = Set(previouslySeen)
        return Set(currentIDs.filter { !previousSet.contains($0) })
    }

    /// Records the current full set of comment IDs as "seen" for this
    /// post, to be diffed against on the next visit.
    public static func markSeen(postID: String, commentIDs: [String]) {
        var all = loadAll()
        all[postID] = commentIDs
        if all.count > maxTrackedPosts {
            // Drop an arbitrary entry: Dictionary has no insertion order and this
            // is a local cache.
            if let keyToDrop = all.keys.first(where: { $0 != postID }) {
                all.removeValue(forKey: keyToDrop)
            }
        }
        saveAll(all)
    }

    // MARK: - Total-count snapshots (unread comments badge)
    // Apollo also keeps the total `numComments` seen at the last visit under
    // `PostCommentsSnapshots`: a feed row has no comment IDs to diff, so its
    // badge is `numComments - lastSeen`.

    private static let countKey = "com.pendo324.Phoebus.PostCommentsSnapshots"

    private static func loadCounts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: countKey) as? [String: Int] ?? [:]
    }

    /// The post's total comment count at its last visit, or `nil` if
    /// it has never been opened - in which case there is nothing to
    /// call "new" and the badge must stay hidden.
    public static func lastSeenCommentCount(postID: String) -> Int? {
        loadCounts()[postID]
    }

    /// Records the total comment count for a post being viewed.
    public static func recordCommentCount(postID: String, count: Int) {
        var all = loadCounts()
        all[postID] = count
        if all.count > maxTrackedPosts, let keyToDrop = all.keys.first(where: { $0 != postID }) {
            all.removeValue(forKey: keyToDrop)
        }
        UserDefaults.standard.set(all, forKey: countKey)
    }

    /// How many comments have appeared since the last visit, or 0
    /// when the post is unvisited or has not grown.
    public static func newCommentCount(postID: String, currentCount: Int) -> Int {
        guard let seen = lastSeenCommentCount(postID: postID) else { return 0 }
        return max(0, currentCount - seen)
    }

    /// Apollo's `PostCommentsSnapshots`: a JSON array alternating a bare
    /// post id and `{"totalComments": N, "timestamp": T}`.
    public static func decodeApolloSnapshots(_ data: Data) -> [String: Int] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [:] }
        var result: [String: Int] = [:]
        var index = 0
        while index + 1 < array.count {
            if let id = array[index] as? String,
               let entry = array[index + 1] as? [String: Any],
               let total = (entry["totalComments"] as? NSNumber)?.intValue {
                result[id] = total
            }
            index += 2
        }
        return result
    }

    /// Adds imported counts without overwriting posts this install has
    /// already visited.
    public static func importCommentCounts(_ counts: [String: Int]) {
        var all = loadCounts()
        for (id, count) in counts where all[id] == nil { all[id] = count }
        while all.count > maxTrackedPosts, let key = all.keys.first(where: { counts[$0] != nil }) {
            all.removeValue(forKey: key)
        }
        UserDefaults.standard.set(all, forKey: countKey)
    }
}
