import Foundation

/// Manual ordering for the Subreddits list's "Following" section (Reborn
/// `FollowedUsersOrder`): an array of names in the user's dragged order.
///
/// Ordering rule: saved order first (case-insensitive name match), then any
/// new followed users in natural (alphabetical) order.
///
///  1. Matching is case-insensitive: Reddit preserves the case a username
///     was created with, and the API may return different casing than was
///     stored.
///  2. New users sort after all saved ones, so a newly followed user lands
///     at the end of the section rather than in the middle of a
///     hand-arranged list.
///
/// A name in the saved order that is no longer followed never matches and
/// is not pruned, so re-following someone restores their old position.
public enum FollowedUsersOrderStore {
    /// Reborn's key name, so a defaults import lines up.
    private static let key = "FollowedUsersOrder"

    public static let storage = DefaultsKey<[String]>(key, default: [])

    public static func load() -> [String] { storage.load() }

    public static func save(_ order: [String]) { storage.save(order) }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Applies the saved order to `names`, which must already be in natural
    /// (alphabetical) order. Pure so it can be checked directly.
    public static func apply(savedOrder: [String], to names: [String]) -> [String] {
        guard savedOrder.count > 0, names.count > 1 else { return names }
        var position: [String: Int] = [:]
        position.reserveCapacity(savedOrder.count)
        for (index, name) in savedOrder.enumerated() {
            // First occurrence wins, so a duplicated saved name cannot move an
            // entry to a later slot.
            if position[name.lowercased()] == nil {
                position[name.lowercased()] = index
            }
        }
        let naturalBase = savedOrder.count
        let ranked: [(rank: Int, offset: Int, name: String)] = names.enumerated().map { offset, name in
            (position[name.lowercased()] ?? (naturalBase + offset), offset, name)
        }
        // `offset` is the tiebreak so equal-ranked entries stay in natural order.
        let sorted = ranked.sorted { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.offset < rhs.offset
        }
        return sorted.map { $0.name }
    }

    /// Convenience for the common call site.
    public static func ordered(_ names: [String]) -> [String] {
        apply(savedOrder: load(), to: names)
    }
}
