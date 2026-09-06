import Foundation

/// Whether scrolling to a given row should load the next page of a feed,
/// as a pure function.
public enum FeedPaginationPolicy {
    /// How many rows from the end the user must reach before the next page
    /// starts loading, so it is usually in place before they get there.
    public static let loadMoreThreshold = 5

    /// Whether appearing at `index` should start the next page fetch.
    /// `infiniteScrollingEnabled` is the "Infinite Scrolling" setting: when off,
    /// scroll-triggered continuation stops but manual reloads are unaffected.
    /// `reachedEnd` means Reddit sent a null `after` cursor.
    public static func shouldLoadMore(
        index: Int,
        loadedCount: Int,
        infiniteScrollingEnabled: Bool,
        reachedEnd: Bool,
        isLoadingMore: Bool,
        isLoading: Bool
    ) -> Bool {
        guard infiniteScrollingEnabled else { return false }
        guard !reachedEnd, !isLoadingMore, !isLoading else { return false }
        return index >= loadedCount - loadMoreThreshold
    }

    /// Whether the feed should offer a manual "load next page" row (Apollo's
    /// "Double tap to load next page" cell). Without it, turning off Infinite
    /// Scrolling would dead-end the feed.
    public static func shouldOfferManualNextPage(
        infiniteScrollingEnabled: Bool,
        reachedEnd: Bool,
        isLoadingMore: Bool,
        isLoading: Bool,
        loadedCount: Int
    ) -> Bool {
        guard !infiniteScrollingEnabled else { return false }
        guard !reachedEnd, !isLoading, loadedCount > 0 else { return false }
        // Stays while a page is in flight, showing a spinner, so the list
        // doesn't reflow under a finger.
        return true
    }

    /// The 1-based page number the manual row would load next, at 25 items per
    /// page (Reddit's default, and what this app requests).
    public static func nextPageNumber(loadedCount: Int, pageSize: Int = 25) -> Int {
        max(2, (loadedCount / max(1, pageSize)) + 1)
    }

    /// How many loaded posts make a feed long enough for Apollo's end-of-feed
    /// beast, which only appears when you have reached the end of everything
    /// Reddit will hand out. The threshold is a multiple of the 25-item page.
    public static let longFeedThreshold = 100

    /// Merges a freshly fetched page into the shown posts, dropping
    /// duplicates: Reddit repeats posts across page boundaries, and appending
    /// blindly would create duplicate SwiftUI ids.
    public static func mergePage<ID: Hashable>(existing: [ID], incoming: [ID]) -> [ID] {
        let seen = Set(existing)
        return existing + incoming.filter { !seen.contains($0) }
    }
}
