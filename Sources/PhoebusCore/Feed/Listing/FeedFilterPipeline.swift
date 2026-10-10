import Foundation

/// The client-side filters every feed page goes through, in order:
/// content filters (subreddit/keyword/author/domain), Post Rules, Hide Read
/// Posts, and "No Subscribed in All/Popular". One function so the first page and every
/// later page are filtered alike.
public enum FeedFilterPipeline {
    public struct Context: Sendable {
        public var isAggregateFeed: Bool
        /// r/all or r/popular, where Filtered Subreddits apply.
        public var isAllOrPopular: Bool
        /// Subscribed names (lowercased) to drop, for All/Popular with
        /// the setting on; empty otherwise.
        public var excludedSubreddits: Set<String>
        /// The feed Post Rules are scoped against; nil skips them.
        public var postRuleFeed: PostRuleFeed?
        /// The signed-in user, whose own posts Post Rules never hide.
        public var username: String?

        public init(isAggregateFeed: Bool, isAllOrPopular: Bool = false, excludedSubreddits: Set<String> = [],
                    postRuleFeed: PostRuleFeed? = nil, username: String? = nil) {
            self.isAggregateFeed = isAggregateFeed
            self.isAllOrPopular = isAllOrPopular
            self.excludedSubreddits = excludedSubreddits
            self.postRuleFeed = postRuleFeed
            self.username = username
        }
    }

    public static func apply(_ posts: [RedditPost], _ context: Context) -> [RedditPost] {
        apply(posts, context, postRules: PostRuleStore.load())
    }

    /// Testable variant taking the Post Rules explicitly.
    public static func apply(_ posts: [RedditPost], _ context: Context, postRules: [PostRule]) -> [RedditPost] {
        var result = ContentFilterStore.apply(posts, isAllOrPopular: context.isAllOrPopular)
        if let feed = context.postRuleFeed {
            result = PostRuleStore.apply(result, rules: postRules, feed: feed, username: context.username)
        }
        result = ReadPostStore.apply(result, isSpecificSubreddit: !context.isAggregateFeed)
        if !context.excludedSubreddits.isEmpty {
            result = result.filter { !context.excludedSubreddits.contains($0.subreddit.lowercased()) }
        }
        return result
    }
}
