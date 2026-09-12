import SwiftUI
import PhoebusCore

/// Loading, paging, filtering and the feed's side effects (snapshot, highlights, subscription, swipes).
extension FeedScreen {
    /// Fetches the subreddit's pinned posts for the highlights
    /// carousel. Its own `hot` request, not a filter over the posts
    /// already on screen, since highlights are sort-independent and a
    /// New/Top/Rising feed wouldn't contain the stickied posts.
    /// Records what this screen currently shows, so an immediate
    /// forward swipe can restore it instead of refetching.
    func storeSnapshot() {
        guard !posts.isEmpty else { return }
        FeedSnapshotCache.shared.store(
            key: snapshotKey,
            posts: posts,
            highlights: highlightPosts,
            scrapedHighlights: scrapedHighlights,
            subredditInfo: subredditInfo,
            isModerator: isModerator,
            signedInUsername: signedInUsername,
            afterToken: afterToken,
            reachedEnd: reachedEnd)
    }

    /// Shows the subreddit's cached highlights at once, then re-checks them
    /// when they're older than `CommunityHighlights.cacheTTL` (or always, for
    /// pull-to-refresh), rebuilding the carousel only if they changed.
    func loadCommunityHighlights(force: Bool = false) async {
        let mode = subredditLayoutSettings.communityHighlights
        guard mode != .off else {
            highlightPosts = []
            scrapedHighlights = []
            return
        }
        guard !subreddit.isEmpty else { return }
        let name = subreddit
        let cache = CommunityHighlightsCache.shared
        if let cached = cache.entry(subreddit: name, mode: mode) {
            apply(posts: cached.posts, scraped: cached.scraped)
            if !force, !CommunityHighlights.isStale(fetchedAt: cached.fetchedAt) { return }
        }
        guard let listing = try? await repository.fetchListing(
            subreddit: name, sort: "hot", timeframe: nil, after: nil) else { return }
        let decoded = await listing.postsInBackground()
        let fresh = CommunityHighlights.highlights(from: decoded)
        let keptScrape = cache.entry(subreddit: name, mode: mode)?.scraped ?? []
        apply(posts: fresh, scraped: keptScrape)
        cache.store(.init(posts: fresh, scraped: keptScrape, fetchedAt: Date()), subreddit: name, mode: mode)

        // Full mode adds the web scrape on top of the REST result, after the
        // REST cards are already on screen. A blocked or timed-out scrape
        // leaves the existing cards.
        guard mode == .full else { return }
        let fetch = CommunityHighlightsWebFetch()
        highlightsWebFetch = fetch
        fetch.start(subreddit: name) { items in
            guard !items.isEmpty else { return }
            apply(posts: highlightPosts, scraped: items)
            if var entry = cache.entry(subreddit: name, mode: mode) {
                entry.scraped = items
                cache.store(entry, subreddit: name, mode: mode)
            }
        }
    }

    /// Sets the carousel's content only when it differs, so an unchanged
    /// refresh doesn't rebuild it.
    private func apply(posts: [RedditPost], scraped: [ScrapedHighlight]) {
        if CommunityHighlights.signature(of: posts) != CommunityHighlights.signature(of: highlightPosts) {
            highlightPosts = posts
        }
        if scraped != scrapedHighlights { scrapedHighlights = scraped }
    }

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

    func handleSwipeAction(_ action: SwipeAction, on post: RedditPost) async {
        await ContentActions.perform(action, on: post, repository: repository, hooks: SwipeActionHooks(
            // Opens the post so its composer is reachable.
            onReply: { replyTarget = post },
            onShare: { shareTarget = post },
            onHide: { posts.removeAll { $0.id == post.id } },
            onHidePostsAbove: { await hidePosts(above: post) },
            author: post.author, subreddit: post.subreddit
        ))
    }

    /// Stock's Hide Posts Above: hides every post above `post` in the feed.
    func hidePosts(above post: RedditPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }), index > 0 else { return }
        let above = Array(posts[..<index])
        posts.removeAll { candidate in above.contains { $0.id == candidate.id } }
        for item in above { _ = await ContentActions.hide(item, repository: repository) }
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
        // A deliberate reload always beats the cache. Every intentional
        // path (pull-to-refresh, sort, timeframe, subreddit or sign-in
        // change) funnels through here.
        FeedSnapshotCache.shared.invalidate(key: snapshotKey)
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
        guard case let RedditAPIError.httpError(status, body) = error else {
            return "Couldn't load posts."
        }
        return FeedErrorCopy.message(status: status, body: body, subreddit: subreddit)
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
