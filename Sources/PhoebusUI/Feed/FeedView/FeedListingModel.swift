import SwiftUI
import PhoebusCore

/// A feed's listing: the posts on screen, paging, and load state. Owned
/// by `FeedScreen`, which keeps the chrome (sheets, menus, header).
///
/// Only the newest load lands: each `load` bumps a generation, and a
/// first page or a next page from an older load is dropped.
@MainActor
final class FeedListingModel: ObservableObject {
    /// What to fetch.
    struct Request {
        let repository: RedditRepository
        let subreddit: String
        let multiredditPath: String?
        let sort: String
        let timeframe: String

        func fetch(after: String?) async throws -> RedditListing {
            if let multiredditPath {
                return try await repository.fetchMultiredditListing(path: multiredditPath, sort: sort, after: after)
            }
            return try await repository.fetchListing(subreddit: subreddit, sort: sort, timeframe: timeframe, after: after)
        }
    }

    @Published var posts: [RedditPost] = []
    @Published var isLoading = false
    /// Reddit's `after` cursor drives infinite scrolling for the feed.
    @Published var afterToken: String?
    @Published var isLoadingMore = false
    /// Set once Reddit returns a page with no `after` cursor, so we
    /// stop asking (Reddit signals end-of-listing with `after: null`).
    @Published var reachedEnd = false
    /// "Show Page Endings" (`AppearanceSettings.showPageEndings`, key
    /// `ShowPageEndings`): the last post ID of each fetched page, reset
    /// by `load` so a fresh listing carries no stale boundaries.
    @Published var pageBoundaryPostIDs: Set<String> = []
    @Published var errorMessage: String?

    private var generation = 0

    /// Fetches the first page, replacing the listing.
    ///
    /// - Parameters:
    ///   - filter: the feed's `FeedFilterPipeline` pass, applied to every page.
    ///   - errorText: the copy for a failure.
    func load(_ request: Request, filter: ([RedditPost]) async -> [RedditPost],
              errorText: (Error) -> String) async {
        generation += 1
        let current = generation
        // A failure shown from an earlier attempt goes as this one starts.
        errorMessage = nil
        isLoading = true
        // A stale `after` from a previous sort/listing must not carry over.
        afterToken = nil
        reachedEnd = false
        pageBoundaryPostIDs = []
        defer { if current == generation { isLoading = false } }
        do {
            let listing = try await request.fetch(after: nil)
            let fetched = await filter(await listing.postsInBackground())
            guard current == generation else { return }
            posts = fetched
            if let lastOfFirstPage = fetched.last {
                pageBoundaryPostIDs.insert(lastOfFirstPage.id)
            }
            afterToken = listing.data.after
            reachedEnd = listing.data.after == nil
        } catch {
            guard current == generation else { return }
            errorMessage = errorText(error)
        }
    }

    /// Fetches the next page with Reddit's `after` cursor and appends it,
    /// through the same filter as the first page.
    func loadMore(_ request: Request, filter: ([RedditPost]) async -> [RedditPost]) async {
        guard let after = afterToken, !isLoadingMore else { return }
        let current = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let listing = try await request.fetch(after: after)
            let fetched = await filter(await listing.postsInBackground())
            // A reload (new sort, refresh) started meanwhile: this page
            // belongs to the old listing.
            guard current == generation else { return }
            // Reddit can repeat a post across page boundaries (vote/rank
            // churn between requests); appending blindly would duplicate
            // SwiftUI ids.
            let existingIDs = Set(posts.map(\.id))
            let newPosts = fetched.filter { !existingIDs.contains($0.id) }
            posts.append(contentsOf: newPosts)
            if let lastOfPage = newPosts.last {
                pageBoundaryPostIDs.insert(lastOfPage.id)
            }
            afterToken = listing.data.after
            if listing.data.after == nil { reachedEnd = true }
        } catch {
            // A failed page must not kill the feed being read or wedge
            // paging: `afterToken` stays, so the next row that appears
            // retries.
        }
    }

    /// Restores a listing kept by `FeedSnapshotCache`.
    func restore(posts: [RedditPost], afterToken: String?, reachedEnd: Bool) {
        self.posts = posts
        self.afterToken = afterToken
        self.reachedEnd = reachedEnd
    }
}
