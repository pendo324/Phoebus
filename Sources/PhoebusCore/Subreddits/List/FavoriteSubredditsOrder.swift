import Foundation

/// Edit-mode drag-to-reorder of the Subreddits root's Favorites section.
/// The order is the stored `FavoriteSubreddits` array itself (Apollo's native
/// key), so there is no separate order list to keep in step with it.
public enum FavoriteSubredditsOrder {
    /// `full` (the stored order) after moving rows of `visible` (the rows on
    /// screen, a subsequence of `full` when the filter field hides some).
    /// `source` and `destination` follow SwiftUI's `onMove` convention. The
    /// moved rows take the slots the visible rows held, so hidden favorites
    /// keep their places. A `visible` list that is not part of `full`
    /// changes nothing.
    public static func moved(full: [String], visible: [String],
                             from source: IndexSet, to destination: Int) -> [String] {
        let moving = source.filter { visible.indices.contains($0) }
        guard !moving.isEmpty else { return full }

        let fullKeys = full.map { $0.lowercased() }
        let visibleKeys = visible.map { $0.lowercased() }
        let visibleSet = Set(visibleKeys)
        guard visibleSet.count == visibleKeys.count,
              fullKeys.filter({ visibleSet.contains($0) }) == visibleKeys else { return full }

        var reordered = visibleKeys
        let items = moving.map { reordered[$0] }
        for index in moving.reversed() { reordered.remove(at: index) }
        let insertAt = destination - moving.filter { $0 < destination }.count
        reordered.insert(contentsOf: items, at: min(max(insertAt, 0), reordered.count))

        var slots = reordered[...]
        return zip(full, fullKeys).map { name, key in
            visibleSet.contains(key) ? slots.popFirst() ?? name : name
        }
    }
}
