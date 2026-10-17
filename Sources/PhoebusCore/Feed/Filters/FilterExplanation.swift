import Foundation

/// Names the rule that hid or blurred a post, for the Filters tester. It runs
/// the same evaluators in the same order as `FeedFilterPipeline`, so what the
/// tester says and what the feed does cannot disagree.
public enum PostFilterOutcome: Equatable, Sendable {
    case shown
    /// A Post Rule matched but stickied and your own posts are never hidden by one.
    case exempt(PostFilterExemption)
    case hidden(PostFilterMatch)
    /// Tag Filters blur: the post is still shown, only its title and media are covered.
    case blurred(TagBlurReason)

    /// The tester's result line.
    public var description: String {
        switch self {
        case .shown: return "Shown"
        case .exempt(let reason): return reason.description
        case .hidden(let match): return match.description
        case .blurred(let reason): return reason.description
        }
    }
}

/// Why Post Rules left a post alone.
public enum PostFilterExemption: Equatable, Sendable {
    case stickied
    case ownPost

    public var description: String {
        switch self {
        case .stickied: return "Shown: stickied posts are never filtered"
        case .ownPost: return "Shown: your own posts are never filtered"
        }
    }
}

/// Which Reborn "Tag Filters" tag covered a post. A blurred post is still in
/// the feed, so this is reported after every hiding rule.
public enum TagBlurReason: Equatable, Sendable {
    case nsfw
    case spoiler

    public var description: String {
        switch self {
        case .nsfw: return "Blurred: NSFW tag filter"
        case .spoiler: return "Blurred: spoiler tag filter"
        }
    }
}

/// The rule a hidden post matched.
public enum PostFilterMatch: Equatable, Sendable {
    /// Apollo's "Filtered Subreddits" list.
    case subreddit(String)
    case keyword(value: String, field: KeywordField)
    case author(String)
    case domain(String)
    /// Reborn "Post Filters": a keyword scoped to one subreddit.
    case subredditKeyword(subreddit: String, keyword: String)
    /// Reborn "Post Filters": a flair scoped to one subreddit.
    case subredditFlair(subreddit: String, flair: String)
    /// Reborn "Filter Subreddits by Name" (a substring of the subreddit name).
    case subredditNameFragment(String)
    /// Phoebus "Post Rules": score, comments, awards, tag-only or title regex.
    case postRule(String)
    /// The match came from the crosspost's original post, which the feed tests too.
    indirect case crosspostParent(PostFilterMatch)

    /// Which text field Apollo's keyword filter matched.
    public enum KeywordField: String, Equatable, Sendable {
        case title
        case link
        case flair

        var noun: String {
            switch self {
            case .title: return "title"
            case .link: return "link"
            case .flair: return "flair"
            }
        }
    }

    /// The tester's result line.
    public var description: String {
        switch self {
        case .subreddit(let name): return "Hidden: r/\(name) is filtered"
        case .keyword(let value, let field): return "Hidden by keyword \(Self.quoted(value)) in the \(field.noun)"
        case .author(let name): return "Hidden: u/\(name) is filtered"
        case .domain(let value): return "Hidden by domain \(Self.quoted(value))"
        case .subredditKeyword(let subreddit, let keyword):
            return "Hidden by keyword \(Self.quoted(keyword)) in r/\(subreddit)"
        case .subredditFlair(let subreddit, let flair):
            return "Hidden by flair \(Self.quoted(flair)) in r/\(subreddit)"
        case .subredditNameFragment(let fragment):
            return "Hidden: subreddit names containing \(Self.quoted(fragment)) are filtered"
        case .postRule(let name): return "Hidden by Post Rule \(Self.quoted(name))"
        case .crosspostParent(let match):
            return "Hidden: the crosspost's original is filtered (\(match.ruleName))"
        }
    }

    /// The matched rule in a few words, for the crosspost wrapper's line.
    var ruleName: String {
        switch self {
        case .subreddit(let name): return "r/\(name)"
        case .keyword(let value, let field): return "keyword \(Self.quoted(value)) in the \(field.noun)"
        case .author(let name): return "u/\(name)"
        case .domain(let value): return "domain \(Self.quoted(value))"
        case .subredditKeyword(let subreddit, let keyword):
            return "keyword \(Self.quoted(keyword)) in r/\(subreddit)"
        case .subredditFlair(let subreddit, let flair):
            return "flair \(Self.quoted(flair)) in r/\(subreddit)"
        case .subredditNameFragment(let fragment): return "subreddit name \(Self.quoted(fragment))"
        case .postRule(let name): return "Post Rule \(Self.quoted(name))"
        case .crosspostParent(let match): return match.ruleName
        }
    }

    private static func quoted(_ value: String) -> String { "\u{201c}\(value)\u{201d}" }
}

/// What the comment filters and the Blocked Users list do to one comment.
public enum CommentFilterOutcome: Equatable, Sendable {
    case shown
    case hidden(reason: String)
    case collapsed(reason: String)

    /// The tester's result line.
    public var description: String {
        switch self {
        case .shown: return "Shown"
        case .hidden(let reason): return "Hidden: \(reason)"
        case .collapsed(let reason): return "Collapsed: \(reason)"
        }
    }
}

/// One function that says which filter hides a post or comment, and it uses
/// `ContentFilterStore`, `PostFilterRules` and `PostRuleStore`'s own matching,
/// so the Filters tester can't drift from the feed.
public enum FilterExplanation {
    /// Names what hides or blurs `post`, running the feed's evaluators in the
    /// feed's order: content filters (post, then crosspost parent), Post
    /// Filters, Post Rules with their stickied/own-post exemptions, then Tag
    /// Filters' blur. Hide Read Posts and "No Subscribed in All/Popular" are
    /// feed context rather than user filters, so they are left out here.
    public static func explain(post: RedditPost, filters: [ContentFilter], postFilters: PostFilterRules,
                               postRules: [PostRule], tagFilters: TagFilterSettings,
                               feed: PostRuleFeed, username: String?) -> PostFilterOutcome {
        if let match = contentMatch(post, filters: filters) { return .hidden(match) }
        if let match = postFilterMatch(post, postFilters: postFilters) { return .hidden(match) }
        switch PostRuleStore.outcome(for: post, active: PostRuleStore.activeRules(postRules, feed: feed),
                                     username: username) {
        case .hidden(let match): return .hidden(match)
        case .exempt(let reason): return .exempt(reason)
        case .shown, .blurred: break   // Post Rules only hide.
        }
        if let reason = tagBlurReason(post, tagFilters: tagFilters) { return .blurred(reason) }
        return .shown
    }

    /// Apollo's global content filters, first match wins. Shared with
    /// `ContentFilterStore.shouldHide` so both use one matcher per filter kind.
    static func contentMatch(_ post: RedditPost, filters: [ContentFilter]) -> PostFilterMatch? {
        for filter in filters {
            if let match = filter.match(post: post) { return match }
        }
        return nil
    }

    /// Reborn's Post Filters over the post, then its crosspost parent. Shared
    /// with `ContentFilterStore.shouldHide`.
    static func postFilterMatch(_ post: RedditPost, postFilters: PostFilterRules) -> PostFilterMatch? {
        if let match = postFilters.match(subreddit: post.subreddit, title: post.title,
                                         url: post.url, flair: post.linkFlairText) {
            return match
        }
        // The parent carries no url or flair, so only its subreddit and title are testable.
        if let parent = post.crosspostParent,
           let match = postFilters.match(subreddit: parent.subreddit, title: parent.title,
                                         url: nil, flair: nil) {
            return .crosspostParent(match)
        }
        return nil
    }

    static func tagBlurReason(_ post: RedditPost, tagFilters: TagFilterSettings) -> TagBlurReason? {
        tagFilters.blurReason(subreddit: post.subreddit, isNSFW: post.over18, isSpoiler: post.spoiler)
    }

    /// Names what the comment filters and the Blocked Users list do to
    /// `comment`. Blocked Users runs first in the tree: Hide removes the
    /// comment, Collapse starts it collapsed, and a comment filter's own
    /// reason wins when both collapse.
    public static func explain(comment: RedditComment, subreddit: String, ownUsername: String?,
                               focusedCommentID: String? = nil, filters: [CommentFilter],
                               blockedUsers: Set<String>, blockedUsersHide: Bool) -> CommentFilterOutcome {
        let decision = CommentFilterPolicy.decision(for: comment, subreddit: subreddit,
                                                    ownUsername: ownUsername,
                                                    focusedCommentID: focusedCommentID, filters: filters)
        let lowercasedBlocked = Set(blockedUsers.map { $0.lowercased() })
        guard lowercasedBlocked.contains(comment.author.lowercased()) else { return decision }
        if blockedUsersHide { return .hidden(reason: "Blocked user") }
        if case .collapsed = decision { return decision }
        return .collapsed(reason: "Blocked user")
    }
}
