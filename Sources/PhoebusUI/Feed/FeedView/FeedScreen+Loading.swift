import SwiftUI
import PhoebusCore

/// Loading, paging, filtering and the feed's side effects (snapshot, highlights, subscription, swipes).
extension FeedScreen {
    func checkModeratorStatus() async {
        guard !subreddit.isEmpty else { return }
        // One fetch also backs the Subreddit Layout header (banner, subscriber
        // count, Join button).
        let info = try? await repository.fetchSubredditInfo(name: subreddit)
        isModerator = info?.userIsModerator == true
        subredditInfo = info
    }

    /// A subscription changed elsewhere (the ••• menu, the Subscriptions
    /// list, an interactive post): the pill follows (Reborn #1264).
    func applySubscriptionChange(_ note: Notification) {
        guard let change = SubscriptionChange.from(note),
              change.matches(name: subredditInfo?.displayName ?? subreddit, fullname: subredditInfo?.name) else { return }
        isSubscribedOverride = change.subscribed
    }

    func currentlySubscribedToHeaderSubreddit() -> Bool {
        isSubscribedOverride ?? (subredditInfo?.userIsSubscriber ?? false)
    }

    func toggleHeaderSubscribe() async {
        guard let subredditInfo else { return }
        let newValue = !currentlySubscribedToHeaderSubreddit()
        isSubscribedOverride = newValue
        do {
            try await repository.subscribe(subredditFullname: subredditInfo.name, subscribe: newValue)
        } catch {
            isSubscribedOverride = !newValue
        }
    }

    /// Optimistically mutates one post in the local `posts` snapshot by
    /// its stable `id`, used by the moderator distinguish/sticky/lock
    /// menu actions above since none of those endpoints return an
    /// updated post payload to refresh from.
    func updatePost(_ id: String, _ mutate: (inout RedditPost) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        mutate(&posts[index])
    }

    func expireForwardTargetIfNeeded(forRowOf post: RedditPost) {
        guard generalSettings.forwardSwipeForgetAfterScrolling else { return }
        guard forwardTarget != nil, let anchorIndex = forwardAnchorRowIndex else { return }
        guard let currentIndex = posts.firstIndex(where: { $0.id == post.id }) else { return }
        if abs(currentIndex - anchorIndex) >= Self.forwardExpiryRowThreshold {
            forwardTarget = nil
            forwardAnchorRowIndex = nil
        }
    }
    func loadMoreIfNeeded(currentPost post: RedditPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        // Doomscrolling guard (`infiniteScrollingEnabled`, key
        // `DoomscrollDefeater3`): off stops scroll-triggered continuation;
        // pull-to-refresh and sort changes still work. The decision lives in
        // `FeedPaginationPolicy` so smoke tests can assert it.
        guard FeedPaginationPolicy.shouldLoadMore(
            index: index,
            loadedCount: posts.count,
            infiniteScrollingEnabled: generalSettings.infiniteScrollingEnabled,
            reachedEnd: reachedEnd,
            isLoadingMore: isLoadingMore,
            isLoading: isLoading
        ) else { return }
        Task { await loadMore() }
    }

    /// "Exclude Subscribed from All/Popular" (`excludeSubscribedFromAllPopular`,
    /// key `ExcludeSubsFromAllPopular`): only applies to r/all and
    /// r/popular, not Home or a multireddit. Uses
    /// `SubscribedSubredditsCache` to avoid refetching the full
    /// subscription listing on every page load.
    /// Runs a fetched page through `FeedFilterPipeline`.
    func filtered(_ fetched: [RedditPost]) async -> [RedditPost] {
        var excluded: Set<String> = []
        let lowered = subreddit.lowercased()
        let isAllOrPopular = multiredditPath == nil && (lowered == "all" || lowered == "popular")
        if generalSettings.excludeSubscribedFromAllPopular, isAllOrPopular {
            excluded = await SubscribedSubredditsCache.shared.subscribedNames(repository: repository)
        }
        return FeedFilterPipeline.apply(fetched, .init(isAggregateFeed: isAggregateFeed,
                                                       isAllOrPopular: isAllOrPopular,
                                                       excludedSubreddits: excluded))
    }

    var listingRequest: FeedListingModel.Request {
        .init(repository: repository, subreddit: subreddit, multiredditPath: multiredditPath,
              sort: sort, timeframe: topTimeframe)
    }

    func loadMore() async {
        await listing.loadMore(listingRequest, filter: filtered)
    }

    func load() async {
        await autoHideReadPostsBeforeRefresh()
        let name = subreddit
        await listing.load(listingRequest, filter: filtered,
                           errorText: { Self.feedErrorMessage(for: $0, subreddit: name) })
        // Feeds the widget extension through the shared App Group
        // container; the pool, since the widgets rotate through it.
        if subreddit.isEmpty, multiredditPath == nil, !posts.isEmpty, listing.errorMessage == nil {
            SharedFeedCache.store(posts: posts)
        }
    }

    /// Per-listing failure copy, verbatim from Apollo: a private,
    /// quarantined or banned subreddit has its own sentence rather than
    /// the raw error.
    static func feedErrorMessage(for error: Error, subreddit: String) -> String {
            return "Couldn't load posts."
    }

    /// Per-listing empty-state copy, verbatim from Apollo
    /// ("No posts in Home", "No posts").
    var emptyStateText: String {
        if multiredditPath != nil { return "No posts" }
        switch subreddit.lowercased() {
        case "": return "No posts in Home"
        case "random": return "No posts in random subreddit"
        case "randnsfw": return "No posts in RandNSFW subreddit. Ensure account settings allow viewing."
        default: return "No posts"
        }
    }
}
