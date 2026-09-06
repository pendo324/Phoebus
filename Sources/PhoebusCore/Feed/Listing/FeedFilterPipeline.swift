import Foundation

/// The client-side filters every feed page goes through, in order:
/// content filters (subreddit/keyword/author/domain), Hide Read Posts, and
/// "No Subscribed in All/Popular". One function so the first page and every
/// later page are filtered alike.
public enum FeedFilterPipeline {
    public struct Context: Sendable {
        public var isAggregateFeed: Bool
        /// r/all or r/popular, where Filtered Subreddits apply.
        public var isAllOrPopular: Bool
        /// Subscribed names (lowercased) to drop, for All/Popular with
        /// the setting on; empty otherwise.
        public var excludedSubreddits: Set<String>

        public init(isAggregateFeed: Bool, isAllOrPopular: Bool = false, excludedSubreddits: Set<String> = []) {
            self.isAggregateFeed = isAggregateFeed
            self.isAllOrPopular = isAllOrPopular
            self.excludedSubreddits = excludedSubreddits
        }
    }

    public static func apply(_ posts: [RedditPost], _ context: Context) -> [RedditPost] {
        var result = ContentFilterStore.apply(posts, isAllOrPopular: context.isAllOrPopular)
        result = ReadPostStore.apply(result, isSpecificSubreddit: !context.isAggregateFeed)
        if !context.excludedSubreddits.isEmpty {
            result = result.filter { !context.excludedSubreddits.contains($0.subreddit.lowercased()) }
        }
        return result
    }
}
