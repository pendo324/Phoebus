import Foundation

/// Backs Apollo's "No Subscribed in All/Popular" setting
/// (`ExcludeSubsFromAllPopular`): when on, posts from subreddits the user
/// already subscribes to are hidden in r/all and r/popular.
///
/// `SubredditsRootScreen` already fetches the full subscription list, and
/// refetching a multi-page listing on every All/Popular load is wasteful
/// under Reddit's rate limits. This actor caches the display-name set in
/// memory for the process lifetime and refetches only after `invalidate()`
/// (called on subscribe/unsubscribe) or on first use per launch.
public actor SubscribedSubredditsCache {
    public static let shared = SubscribedSubredditsCache()

    private var subscribedNames: Set<String>?
    private var inFlight: Task<Set<String>?, Never>?
    /// Bumped by `invalidate()`, so a fetch started for the previous
    /// account (or before a subscription change) cannot store its
    /// result afterwards.
    private var generation = 0

    private init() {}

    /// Lowercased subreddit display names the signed-in user
    /// subscribes to. Returns an empty set (rather than throwing) on
    /// fetch failure, a network hiccup filtering r/all should never
    /// crash or blank the feed, it should just fail open and show
    /// everything, matching how every other filter in `FeedScreen`
    /// (`ContentFilterStore`, `ReadPostStore`) degrades.
    public func subscribedNames(repository: RedditRepository) async -> Set<String> {
        if let subscribedNames { return subscribedNames }
        if let inFlight { return await inFlight.value ?? [] }
        let started = generation
        let task = Task<Set<String>?, Never> {
            guard let subreddits = try? await repository.fetchSubscribedSubreddits() else { return nil }
            return Set(subreddits.map { $0.displayName.lowercased() })
        }
        inFlight = task
        let result = await task.value
        guard started == generation else { return result ?? [] }
        inFlight = nil
        // A failure is not cached: the next feed load tries again
        // instead of showing everything for the rest of the session.
        subscribedNames = result
        return result ?? []
    }

    /// Called after a subscribe/unsubscribe action so a since-changed
    /// membership doesn't keep using the stale cached set for the
    /// rest of the session.
    public func invalidate() {
        generation += 1
        subscribedNames = nil
        inFlight = nil
    }
}
