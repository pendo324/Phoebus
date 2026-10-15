import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// --- Hide Blocked User Comments (hideBlockedUserComments) ---
@MainActor func checkHideBlockedUserCommentsDeadToggle() async throws {
    check("filteringBlockedAuthors with an empty set is a no-op", tree.filteringBlockedAuthors([]).count == 2)
    let blockedTopLevel = tree.filteringBlockedAuthors(["a3"])
    check("filteringBlockedAuthors removes a blocked top-level comment", blockedTopLevel.count == 1 && blockedTopLevel[0].comment.id == "c1")
    let blockedParent = tree.filteringBlockedAuthors(["a1"])
    check("filteringBlockedAuthors removes a blocked comment's entire subtree", blockedParent.map(\.comment.id) == ["c3"])
    let blockedNested = tree.filteringBlockedAuthors(["a2"])
    check("filteringBlockedAuthors keeps a non-blocked parent while dropping only its blocked child", blockedNested.count == 2 && blockedNested[0].children.isEmpty)
    check("filteringBlockedAuthors is case-insensitive", tree.filteringBlockedAuthors(["A3"]).count == 1)
}

// --- Comment Filters (Phoebus's own; commentFilters) ---
private func makeFilterComment(id: String, author: String = "someone", body: String = "hello",
                               score: Int = 10, scoreHidden: Bool = false, stickied: Bool = false) -> RedditComment {
    let json = """
    {"id":"\(id)","name":"t1_\(id)","author":"\(author)","body":"\(body)","score":\(score),
     "created_utc":0,"parent_id":"t3_x","link_id":"t3_x","saved":false,
     "score_hidden":\(scoreHidden),"stickied":\(stickied)}
    """.data(using: .utf8)!
    return try! JSONDecoder.reddit.decode(RedditComment.self, from: json)
}

@MainActor func checkCommentFilters() async throws {
    func verdict(_ comment: RedditComment, _ filters: [CommentFilter], subreddit: String = "AskReddit",
                 own: String? = "me", focused: String? = nil) -> CommentFilterVerdict {
        CommentFilterPolicy.verdict(for: comment, subreddit: subreddit, ownUsername: own,
                                    focusedCommentID: focused, filters: filters)
    }
    let minFive = CommentFilter(name: "Low", minScore: 5)
    check("comment filter: score below the minimum collapses with its reason",
          verdict(makeFilterComment(id: "a", score: 4), [minFive]) == .collapse(reason: "Filtered: score below 5"))
    check("comment filter: score at the minimum is shown",
          verdict(makeFilterComment(id: "a", score: 5), [minFive]) == .show)
    let maxHundred = CommentFilter(name: "High", maxScore: 100, displayMode: .hide)
    check("comment filter: score above the maximum hides",
          verdict(makeFilterComment(id: "a", score: 101), [maxHundred]) == .hide)
    check("comment filter: score at the maximum is shown",
          verdict(makeFilterComment(id: "a", score: 100), [maxHundred]) == .show)
    check("comment filter: negative minimum works",
          verdict(makeFilterComment(id: "a", score: -6), [CommentFilter(name: "Neg", minScore: -5)]) != .show)
    check("comment filter: a hidden score is never filtered by score",
          verdict(makeFilterComment(id: "a", score: 1, scoreHidden: true), [minFive]) == .show)
    check("comment filter: a pinned comment is not filtered by score",
          verdict(makeFilterComment(id: "a", score: 1, stickied: true), [minFive]) == .show)

    let words = CommentFilter(name: "Words", excludedWords: ["Spoil"])
    check("comment filter: words match case-insensitively as substrings",
          verdict(makeFilterComment(id: "a", body: "Huge SPOILER ahead"), [words]) == .collapse(reason: "Filtered: contains \u{201c}spoil\u{201d}"))
    check("comment filter: a body without the word is shown",
          verdict(makeFilterComment(id: "a", body: "nothing here"), [words]) == .show)
    let pinnedWord = makeFilterComment(id: "a", body: "spoilers", stickied: true)
    check("comment filter: words still apply to pinned comments", verdict(pinnedWord, [words]) != .show)

    let users = CommentFilter(name: "Users", excludedUsers: [CommentFilter.normalizedUsername(" u/AutoModerator ")], displayMode: .hide)
    check("comment filter: user list strips u/", users.excludedUsers == ["AutoModerator"])
    check("comment filter: users match case-insensitively",
          verdict(makeFilterComment(id: "a", author: "automoderator"), [users]) == .hide)
    check("comment filter: other users are shown",
          verdict(makeFilterComment(id: "a", author: "someone"), [users]) == .show)

    let scoped = CommentFilter(name: "Scoped", minScore: 5, subreddits: [CommentFilter.normalizedSubreddit("/r/AskReddit")])
    check("comment filter: subreddit scope normalises r/ and case", scoped.subreddits == ["askreddit"])
    check("comment filter: applies in its subreddit, any case",
          verdict(makeFilterComment(id: "a", score: 1), [scoped], subreddit: "AskReddit") != .show)
    check("comment filter: does not apply in another subreddit",
          verdict(makeFilterComment(id: "a", score: 1), [scoped], subreddit: "swift") == .show)
    check("comment filter: an empty scope applies everywhere", minFive.applies(in: "anything"))

    check("comment filter: your own comment is never filtered",
          verdict(makeFilterComment(id: "a", author: "Me", score: -50), [minFive], own: "me") == .show)
    check("comment filter: the focused comment is never filtered (id)",
          verdict(makeFilterComment(id: "a", score: -50), [minFive], focused: "a") == .show)
    check("comment filter: the focused comment is never filtered (fullname)",
          verdict(makeFilterComment(id: "a", score: -50), [minFive], focused: "t1_a") == .show)
    check("comment filter: Hide wins over Collapse",
          verdict(makeFilterComment(id: "a", author: "AutoModerator", score: 1), [minFive, users]) == .hide)

    // Tree: hide drops the subtree, collapse keeps replies and still filters them.
    let lowReply = CommentTreeNode(comment: makeFilterComment(id: "r1", score: 1), depth: 1)
    let goodReply = CommentTreeNode(comment: makeFilterComment(id: "r2", score: 50), depth: 1)
    let lowRoot = CommentTreeNode(comment: makeFilterComment(id: "p1", score: 1), depth: 0, children: [goodReply])
    let goodRoot = CommentTreeNode(comment: makeFilterComment(id: "p2", score: 50), depth: 0, children: [lowReply])
    let forest = [lowRoot, goodRoot]
    let collapsed = forest.applyingCommentFilters([minFive], subreddit: "x", ownUsername: nil, focusedCommentID: nil)
    check("comment filter tree: collapse starts the comment collapsed with its reason",
          collapsed[0].isCollapsed && collapsed[0].filterReason == "Filtered: score below 5")
    check("comment filter tree: a collapsed comment keeps its replies", collapsed[0].children.map(\.id) == ["r2"])
    check("comment filter tree: nested replies are filtered too",
          collapsed[1].children[0].isCollapsed && !collapsed[1].isCollapsed)
    var hideMin = minFive
    hideMin.displayMode = .hide
    let hidden = forest.applyingCommentFilters([hideMin], subreddit: "x", ownUsername: nil, focusedCommentID: nil)
    check("comment filter tree: hide removes the comment with its replies",
          hidden.map(\.id) == ["p2"] && hidden[0].children.isEmpty)
    let focusedTree = forest.applyingCommentFilters([hideMin], subreddit: "x", ownUsername: nil, focusedCommentID: "r2")
    check("comment filter tree: a focused comment's ancestors are kept",
          focusedTree.first?.id == "p1" && focusedTree.first?.children.map(\.id) == ["r2"])
    check("comment filter tree: no filters is a no-op",
          forest.applyingCommentFilters([], subreddit: "x", ownUsername: nil, focusedCommentID: nil) == forest)

    // Persistence and backups.
    let full = CommentFilter(name: "All", minScore: 5, maxScore: 1000, excludedWords: ["a"],
                             excludedUsers: ["b"], displayMode: .hide, subreddits: ["c"])
    let decoded = try? JSONDecoder().decode([CommentFilter].self, from: JSONEncoder().encode([full]))
    check("comment filter: round-trips through Codable", decoded == [full])
    let sparse = try? JSONDecoder().decode(CommentFilter.self, from: Data(#"{"name":"Old"}"#.utf8))
    check("comment filter: decoding tolerates missing fields",
          sparse?.name == "Old" && sparse?.displayMode == .collapse && sparse?.minScore == nil && sparse?.subreddits == [])
    check("comment filters are in settings backups",
          SettingsDomainSnapshot.isBackedUp(CommentFilterStore.storage.key))
    let defaults = UserDefaults(suiteName: "CommentFilterBackupTest")!
    defaults.removePersistentDomain(forName: "CommentFilterBackupTest")
    CommentFilterStore.storage.save([full], to: defaults)
    let snapshot = try! JSONDecoder().decode([String: JSONValue].self,
                                             from: JSONEncoder().encode(SettingsDomainSnapshot.capture(from: defaults)))
    let restored = UserDefaults(suiteName: "CommentFilterBackupRestore")!
    restored.removePersistentDomain(forName: "CommentFilterBackupRestore")
    SettingsDomainSnapshot.restore(snapshot, into: restored)
    check("comment filters survive a backup round trip", CommentFilterStore.storage.load(from: restored) == [full])
    defaults.removePersistentDomain(forName: "CommentFilterBackupTest")
    restored.removePersistentDomain(forName: "CommentFilterBackupRestore")
}

// --- Collapse / flatten logic ---
@MainActor func checkCollapseFlattenLogic() async throws {
    let leaf = CommentTreeNode(comment: makeComment(id: "child"), depth: 1)
    let root = CommentTreeNode(comment: makeComment(id: "root"), depth: 0, children: [leaf])
    check("visibleFlattened uncollapsed", root.visibleFlattened().map(\.id) == ["root", "child"])
    let collapsedRoot = root.togglingCollapse(id: "root")
    check("visibleFlattened after collapsing root", collapsedRoot.visibleFlattened().map(\.id) == ["root"])
    let leaf2 = CommentTreeNode(comment: makeComment(id: "leaf"), depth: 1)
    let root2 = CommentTreeNode(comment: makeComment(id: "root2"), depth: 0, children: [leaf2])
    let toggledLeaf = root2.togglingCollapse(id: "leaf")
    check("root unaffected when toggling leaf", toggledLeaf.isCollapsed == false)
    check("only leaf toggled", toggledLeaf.children[0].isCollapsed == true)
}

// --- CommentTreeStore.resolveMoreStub: genuinely deleted "more" comments ---
// A "more" marker whose comments were deleted server-side resolves to a real
// Reddit response with zero t1 comments and no further "more" pagination.
// This checks that buildResolved's output signals that case (empty roots, nil
// moreStub) so CommentTreeStore.resolveMoreStub (PhoebusUI, not unit-testable
// here) can tell it from a real empty batch that is merely paginated further.
@MainActor func checkCommentTreeStoreResolveMoreStubRealGenuinelyDeletedMore() async throws {
    let emptyMoreJSON = "[]".data(using: .utf8)!
    let emptyMoreJSONValues = try! JSONDecoder().decode([JSONValue].self, from: emptyMoreJSON)
    let emptyResolvedBuild = CommentTreeBuilder.buildResolved(from: emptyMoreJSONValues, stub: resolvingStub)
    check("buildResolved returns empty roots for a genuinely-deleted more-stub (real /api/morechildren empty response)", emptyResolvedBuild.roots.isEmpty)
    check("buildResolved returns a nil moreStub for a genuinely-deleted more-stub (distinguishing it from further pagination)", emptyResolvedBuild.moreStub == nil)
}

// --- RedditPost round-trip Codable (needed for SharedFeedCache App
// Group persistence between the app and widget extension) ---
@MainActor func checkRedditPostRoundTripCodableNeededFor() async throws {
    let encodedPost = try! JSONEncoder.reddit.encode(post)
    let decodedPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: encodedPost)
    check("post round-trips through Codable", decodedPost.id == post.id && decodedPost.title == post.title)
}

// --- RedditURLTarget parsing (share extension / deep link routing) ---
@MainActor func checkRedditURLTargetParsingShareExtensionDeepLink() async throws {
    let postURL = URL(string: "https://www.reddit.com/r/swift/comments/abc123/some_title/")!
    check("parses post URL", RedditURLTarget.parse(postURL) == .post(subreddit: "swift", id: "abc123"))

    let subredditURL = URL(string: "https://reddit.com/r/swift")!
    check("parses subreddit URL", RedditURLTarget.parse(subredditURL) == .subreddit("swift"))
    check("a post on a user's profile opens the post, in u_<name>",
          RedditURLTarget.parse(URL(string: "https://www.reddit.com/user/someone/comments/abc12/a_title/")!)
            == .post(subreddit: "u_someone", id: "abc12"))
    check("a comment on a user's profile post opens that comment",
          RedditURLTarget.parse(URL(string: "https://www.reddit.com/u/someone/comments/abc12/a_title/def34/")!)
            == .comment(subreddit: "u_someone", postID: "abc12", commentID: "def34"))
    check("a plain profile link still opens the profile",
          RedditURLTarget.parse(URL(string: "https://www.reddit.com/user/someone/comments/")!) == .user("someone")
            && RedditURLTarget.parse(URL(string: "https://www.reddit.com/user/someone/")!) == .user("someone"))

    let userURL = URL(string: "https://www.reddit.com/u/someuser")!
    check("parses user URL", RedditURLTarget.parse(userURL) == .user("someuser"))

    let appSchemeURL = URL(string: "phoebus://open?url=https://www.reddit.com/r/swift/comments/abc123/x/")!
    check("parses app-scheme deep link", RedditURLTarget.parseAppScheme(appSchemeURL) == .post(subreddit: "swift", id: "abc123"))

    // The OpenMultireddit SiriKit intent's URL target.
    let multiredditURL = URL(string: "https://www.reddit.com/user/someuser/m/coolstuff")!
    check("parses multireddit URL", RedditURLTarget.parse(multiredditURL) == .multireddit("coolstuff"))
}

// --- RedGifs live network round-trip: the keyless temp-token flow and
// the /v2/gifs/<id> decode, against the real API ---
@MainActor func checkRedGifsLiveNetworkRoundTripThe() async throws {
    if runsLiveChecks { do {
        let client = RedGifsClient()
        let url = try await client.resolvePlayableURL(forID: "agedunsungurva")
        check("resolves a real RedGifs ID to a playable .mp4 URL", url.absoluteString.hasSuffix(".mp4"))
    } catch {
        check("RedGifs live network check (failed: \(error))", false)
    } }
}

// --- Streamable ID extraction + live network round-trip ---
@MainActor func checkStreamableIDExtractionLiveNetworkRound() async throws {
    let streamableURL = URL(string: "https://streamable.com/moo")!
    check("extracts streamable ID from URL", StreamableClient.extractID(from: streamableURL) == "moo")
    check("returns nil for non-streamable URL", StreamableClient.extractID(from: nonRedgifsURL) == nil)
    if runsLiveChecks { do {
        let client = StreamableClient()
        let url = try await client.resolvePlayableURL(forID: "moo")
        check("resolves a real Streamable ID to a playable .mp4 URL", url.absoluteString.contains(".mp4"))
    } catch {
        check("Streamable live network check (failed: \(error))", false)
    } }
}

// --- Swipe action settings ---
// Per-screen (Posts/Comments/Inbox), each with its own default.
@MainActor func checkSwipeActionSettingsApolloSSettingsGesturesViewController() async throws {
    let defaultSettings = SwipeActionSettings.postsDefault
    check("default Posts swipe settings has non-none actions", defaultSettings.leftShort != .none && defaultSettings.rightShort != .none)
    check("default Posts swipe settings matches the real gestures.png table (left short=Upvote, left long=Downvote, right short=Reply, right long=Save)",
          defaultSettings.leftShort == .upvote && defaultSettings.leftLong == .downvote
          && defaultSettings.rightShort == .reply && defaultSettings.rightLong == .save)

    let commentsDefault = SwipeActionSettings.commentsDefault
    check("default Comments swipe settings matches gestures.png (right short=Collapse Top, right long=Reply)",
          commentsDefault.rightShort == .collapseTop && commentsDefault.rightLong == .reply)

    let inboxDefault = SwipeActionSettings.inboxDefault
    check("default Inbox swipe settings matches gestures.png (right short=Mark Read, right long=Reply)",
          inboxDefault.rightShort == .markRead && inboxDefault.rightLong == .reply)

    let encodedSettings = try! JSONEncoder().encode(defaultSettings)
    let decodedSettings = try! JSONDecoder().decode(SwipeActionSettings.self, from: encodedSettings)
    check("swipe settings round-trip through Codable", decodedSettings == defaultSettings)

    check("SwipeAction covers stock's row actions", SwipeAction.allCases.count == 15)
    check("Comments offers stock's ten actions in order", SwipeActionScreen.comments.availableActions ==
          [.upvote, .downvote, .save, .reply, .collapseTop, .collapse, .parentComment, .author, .selectText, .share])

    check("SwipeActionStore persists independently per screen", {
        SwipeActionStore.save(.init(leftShort: .save, leftLong: .save, rightShort: .save, rightLong: .save), for: .posts)
        SwipeActionStore.restoreDefaults(for: .comments)
        let posts = SwipeActionStore.load(for: .posts)
        let comments = SwipeActionStore.load(for: .comments)
        SwipeActionStore.restoreDefaults(for: .posts) // cleanup
        return posts.leftShort == .save && comments.rightShort == .collapseTop
    }())
}

// --- Content filters ---
@MainActor func checkContentFiltersApolloSSettingsFiltersViewController() async throws {
    let subredditFilter = ContentFilter(kind: .subreddit, value: "test")
    check("subreddit filter matches post in that subreddit", subredditFilter.matches(post: post))
    let noMatchFilter = ContentFilter(kind: .subreddit, value: "other")
    check("subreddit filter does not match different subreddit", !noMatchFilter.matches(post: post))
    let authorFilter = ContentFilter(kind: .author, value: "SOMEUSER")
    check("author filter matches case-insensitively", authorFilter.matches(post: post))
    let keywordFilter = ContentFilter(kind: .keyword, value: "Test")
    check("keyword filter matches substring in title", keywordFilter.matches(post: post))
    check("keyword filter also matches the link", ContentFilter(kind: .keyword, value: "EXAMPLE.COM").matches(post: post))
    check("Filter Subreddits by Name matches inside a name (search too)",
          PostFilterRules(nameSubstrings: ["circlejerk"]).hidesSubredditName("CarsCirclejerk")
              && !PostFilterRules(nameSubstrings: ["circlejerk"]).hidesSubredditName("cars"))
    let domainFilter = ContentFilter(kind: .domain, value: "example.com")
    check("domain filter matches post URL host", domainFilter.matches(post: post))
    check("posts filtered out when matching a stored filter", ContentFilterStore.apply([post], filters: [subredditFilter]).isEmpty)
    check("posts kept when no filter matches", ContentFilterStore.apply([post], filters: [noMatchFilter]).count == 1)

    let encodedFilter = try! JSONEncoder().encode(subredditFilter)
    let decodedFilter = try! JSONDecoder().decode(ContentFilter.self, from: encodedFilter)
    check("ContentFilter round-trips through Codable", decodedFilter.value == subredditFilter.value && decodedFilter.kind == subredditFilter.kind)
}

// --- Post Rules (Phoebus-only numeric/tag/title-regex filters) ---
@MainActor func checkPostRules() async throws {
    func rulePost(_ id: String, title: String = "A cat photo", author: String = "someone", score: Int = 100,
                  comments: Int = 10, awards: Int? = nil, nsfw: Bool = false, spoiler: Bool = false,
                  stickied: Bool = false) -> RedditPost {
        var json = #"{"id":"\#(id)","name":"t3_\#(id)","title":"\#(title)","author":"\#(author)","subreddit":"pics","permalink":"/r/pics/comments/\#(id)/","score":\#(score),"num_comments":\#(comments),"created_utc":0,"is_self":false,"over_18":\#(nsfw),"spoiler":\#(spoiler),"stickied":\#(stickied),"saved":false"#
        if let awards { json += #","total_awards_received":\#(awards)"# }
        return try! JSONDecoder.reddit.decode(RedditPost.self, from: Data((json + "}").utf8))
    }
    func kept(_ posts: [RedditPost], _ rule: PostRule, feed: PostRuleFeed = .home, username: String? = nil) -> [String] {
        PostRuleStore.apply(posts, rules: [rule], feed: feed, username: username).map(\.id)
    }
    let scored = [rulePost("low", score: 999), rulePost("edge", score: 1000), rulePost("high", score: 1001)]
    check("Post Rules: minimum score is inclusive",
          kept(scored, PostRule(minScore: 1000)) == ["edge", "high"])
    check("Post Rules: maximum score is inclusive",
          kept(scored, PostRule(maxScore: 1000)) == ["low", "edge"])
    check("Post Rules: a negative minimum score keeps downvoted posts above it",
          kept([rulePost("neg", score: -5), rulePost("worse", score: -20)], PostRule(minScore: -10)) == ["neg"])
    let commented = [rulePost("c5", comments: 5), rulePost("c10", comments: 10), rulePost("c50", comments: 50)]
    check("Post Rules: comment bounds are inclusive at both ends",
          kept(commented, PostRule(minComments: 10, maxComments: 50)) == ["c10", "c50"])
    let awarded = [rulePost("none"), rulePost("two", awards: 2), rulePost("nine", awards: 9)]
    check("Post Rules: awards count a missing total as zero",
          kept(awarded, PostRule(minAwards: 1, maxAwards: 5)) == ["two"]
              && kept(awarded, PostRule(maxAwards: 0)) == ["none"])
    let tagged = [rulePost("plain"), rulePost("nsfw", nsfw: true), rulePost("spoil", spoiler: true)]
    check("Post Rules: NSFW Only keeps only NSFW posts",
          kept(tagged, PostRule(onlyNSFW: true)) == ["nsfw"])
    check("Post Rules: Spoiler Only keeps only spoiler posts",
          kept(tagged, PostRule(onlySpoiler: true)) == ["spoil"])
    check("Post Rules: NSFW Only with Spoiler Only keeps either",
          kept(tagged, PostRule(onlyNSFW: true, onlySpoiler: true)) == ["nsfw", "spoil"])
    let titled = [rulePost("cat", title: "My CAT sleeping"), rulePost("dog", title: "Dog at the beach"),
                  rulePost("q", title: "Question 42")]
    check("Post Rules: hide-titles regex is case-insensitive",
          kept(titled, PostRule(titleExcludesRegex: "\\bcat\\b")) == ["dog", "q"])
    check("Post Rules: only-titles regex keeps matches",
          kept(titled, PostRule(titleRequiresRegex: "\\d+$")) == ["q"])
    check("Post Rules: an invalid regex is ignored, not hiding everything",
          kept(titled, PostRule(titleExcludesRegex: "(unclosed")).count == 3
              && kept(titled, PostRule(titleRequiresRegex: "[")).count == 3)
    check("Post Rules: the editor flags an invalid regex and accepts an empty one",
          !PostRule.isValidTitleRegex("(unclosed") && PostRule.isValidTitleRegex("") && PostRule.isValidTitleRegex("^\\[OC\\]"))
    check("Post Rules: a rule with no conditions hides nothing",
          kept(scored, PostRule()).count == 3)
    check("Post Rules: a disabled rule hides nothing",
          kept(scored, PostRule(isEnabled: false, minScore: 5000)).count == 3)
    check("Post Rules: any one rule hiding a post hides it",
          PostRuleStore.apply(scored, rules: [PostRule(minScore: 1000), PostRule(maxScore: 1000)],
                              feed: .home, username: nil).map(\.id) == ["edge"])
    check("Post Rules: stickied posts are exempt",
          kept([rulePost("pin", score: 1, stickied: true), rulePost("x", score: 1)], PostRule(minScore: 1000)) == ["pin"])
    check("Post Rules: the signed-in user's own posts are exempt (case-insensitively)",
          kept([rulePost("mine", author: "Me", score: 1), rulePost("x", score: 1)], PostRule(minScore: 1000),
               username: "me") == ["mine"])

    // Scope.
    let picsOnly = PostRule(minScore: 1000, feeds: ["r/pics"])
    check("Post Rules: a subreddit-scoped rule applies on that subreddit (case-insensitively)",
          kept(scored, picsOnly, feed: PostRuleFeed(subreddit: "Pics", multiredditPath: nil)) == ["edge", "high"])
    check("Post Rules: a subreddit-scoped rule does not apply on Home or another subreddit",
          kept(scored, picsOnly, feed: .home).count == 3
              && kept(scored, picsOnly, feed: PostRuleFeed(subreddit: "funny", multiredditPath: nil)).count == 3)
    check("Post Rules: an unscoped rule applies everywhere",
          [PostRuleFeed.home, .popular, .all, .subreddit("x"), .multireddit("y")].allSatisfy { PostRule(minScore: 1).applies(to: $0) })
    check("Post Rules: feed screens map to Home, Popular, All, subreddits and multireddits",
          PostRuleFeed(subreddit: "", multiredditPath: nil) == .home
              && PostRuleFeed(subreddit: "Popular", multiredditPath: nil) == .popular
              && PostRuleFeed(subreddit: "all", multiredditPath: nil) == .all
              && PostRuleFeed(subreddit: "home", multiredditPath: nil) == .subreddit("home")
              && PostRuleFeed(subreddit: "", multiredditPath: "/user/bob/m/Tech/") == .multireddit("tech"))
    check("Post Rules: feed tokens round-trip",
          [PostRuleFeed.home, .popular, .all, .subreddit("pics"), .multireddit("tech")].allSatisfy { PostRuleFeed(token: $0.token) == $0 }
              && PostRuleFeed(token: "nonsense") == nil && PostRuleFeed(token: "R/Pics") == .subreddit("pics"))
    check("Post Rules: a multireddit-scoped rule applies only there",
          PostRule(minScore: 1, feeds: ["m/tech"]).applies(to: .multireddit("tech"))
              && !PostRule(minScore: 1, feeds: ["m/tech"]).applies(to: .subreddit("tech")))

    // Pipeline.
    let piped = FeedFilterPipeline.apply(scored, .init(isAggregateFeed: false, postRuleFeed: .subreddit("pics")),
                                         postRules: [picsOnly])
    check("Post Rules run in the feed filter pipeline", piped.map(\.id) == ["edge", "high"])
    check("the feed pipeline skips Post Rules without a feed (other listings)",
          FeedFilterPipeline.apply(scored, .init(isAggregateFeed: false), postRules: [picsOnly]).count == 3)
    check("a page the filters empty is skipped while there is a next page, up to the cap",
          FeedPaginationPolicy.shouldSkipFilteredPage(keptCount: 0, hasNextPage: true, pagesFetched: 1)
              && !FeedPaginationPolicy.shouldSkipFilteredPage(keptCount: 1, hasNextPage: true, pagesFetched: 1)
              && !FeedPaginationPolicy.shouldSkipFilteredPage(keptCount: 0, hasNextPage: false, pagesFetched: 1)
              && !FeedPaginationPolicy.shouldSkipFilteredPage(keptCount: 0, hasNextPage: true,
                                                              pagesFetched: FeedPaginationPolicy.maxFilteredPagesSkipped + 1))

    // Editor helpers.
    check("Post Rules: bounds parse digits, a leading minus only where allowed, empty as no limit",
          PostRule.parseBound("1,000", allowsNegative: false) == 1000
              && PostRule.parseBound("-50", allowsNegative: true) == -50
              && PostRule.parseBound("-50", allowsNegative: false) == 50
              && PostRule.parseBound("", allowsNegative: true) == nil
              && PostRule.parseBound("-", allowsNegative: true) == nil)
    check("Post Rules: a minimum above its maximum is flagged",
          PostRule(minScore: 10, maxScore: 5).hasInvertedRange && !PostRule(minScore: 5, maxScore: 5).hasInvertedRange)

    // Persistence: tolerant decoding and a backup round trip.
    let handWritten = #"[{"minScore":1000,"feeds":["r/pics"]}]"#
    let decoded = try? JSONDecoder().decode([PostRule].self, from: Data(handWritten.utf8))
    check("Post Rules: a hand-written rule decodes with defaults",
          decoded?.first?.minScore == 1000 && decoded?.first?.isEnabled == true
              && decoded?.first?.feeds == ["r/pics"] && decoded?.first?.onlyNSFW == false)
    let suite = UserDefaults(suiteName: "phoebus.smoke.postRules")!
    suite.removePersistentDomain(forName: "phoebus.smoke.postRules")
    let saved = [PostRule(name: "Big pics", minScore: 1000, maxComments: 500, onlySpoiler: true,
                          titleExcludesRegex: "^\\[meta\\]", feeds: ["r/pics", "home"])]
    PostRuleStore.storage.save(saved, to: suite)
    check("Post Rules are in settings backups", SettingsDomainSnapshot.isBackedUp(PostRuleStore.storage.key))
    let snapshot = SettingsDomainSnapshot.capture(from: suite)
    let roundTripped = try! JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(snapshot))
    let restored = UserDefaults(suiteName: "phoebus.smoke.postRulesRestore")!
    restored.removePersistentDomain(forName: "phoebus.smoke.postRulesRestore")
    SettingsDomainSnapshot.restore(roundTripped, into: restored)
    check("Post Rules survive a backup round trip", PostRuleStore.storage.load(from: restored) == saved)
    suite.removePersistentDomain(forName: "phoebus.smoke.postRules")
    restored.removePersistentDomain(forName: "phoebus.smoke.postRulesRestore")
}

// --- Mark read / hide read posts ---
@MainActor func checkMarkReadHideReadPostsSettingsMarkReadHidingPostsViewController() async throws {
    let readSettingsDefault = MarkReadSettings.default
    check("default mark-read settings enables mark-on-open", readSettingsDefault.markReadOnOpen)
    check("Hide Posts… defaults to Permanently, as Apollo", readSettingsDefault.hideReadPosts)
    // The Temporarily mode migrates to Permanently once.
    let markReadSuite = UserDefaults(suiteName: "phoebus.smoke.markRead")!
    markReadSuite.removePersistentDomain(forName: "phoebus.smoke.markRead")
    markReadSuite.set(try! JSONEncoder().encode(MarkReadSettings(markReadOnOpen: true, hideReadPosts: false)),
                      forKey: ReadPostStore.settingsStorage.key)
    let migratedOnce = ReadPostStore.settingsStorage.load(from: markReadSuite).hideReadPosts
    ReadPostStore.settingsStorage.save(MarkReadSettings(markReadOnOpen: true, hideReadPosts: false), to: markReadSuite)
    markReadSuite.set(try! JSONEncoder().encode(MarkReadSettings(markReadOnOpen: true, hideReadPosts: false, autoHideReadPosts: false, disableAutoHideInSubreddits: false, markReadOnScroll: true)),
                      forKey: ReadPostStore.settingsStorage.key)
    check("an old Temporarily becomes Permanently once, then a chosen Temporarily sticks",
          migratedOnce && !ReadPostStore.settingsStorage.load(from: markReadSuite).hideReadPosts)
    markReadSuite.removePersistentDomain(forName: "phoebus.smoke.markRead")
    let encodedReadSettings = try! JSONEncoder().encode(readSettingsDefault)
    let decodedReadSettings = try! JSONDecoder().decode(MarkReadSettings.self, from: encodedReadSettings)
    check("MarkReadSettings round-trips through Codable", decodedReadSettings == readSettingsDefault)
}

// --- Gallery posts ---
@MainActor func checkGalleryPostsApolloSMediaPageViewController() async throws {
    let galleryJSON = """
    {
        "id": "gal1", "name": "t3_gal1", "title": "Gallery Post",
        "author": "someuser", "subreddit": "test", "selftext": "",
        "url": "https://www.reddit.com/gallery/gal1",
        "permalink": "/r/test/comments/gal1/gallery_post/",
        "score": 10, "upvote_ratio": 0.9, "num_comments": 1,
        "created_utc": 1700000000, "is_self": false, "over_18": false,
        "spoiler": false, "stickied": false, "saved": false, "likes": null,
        "is_gallery": true,
        "gallery_data": { "items": [ {"media_id": "img2"}, {"media_id": "img1"} ] },
        "media_metadata": {
            "img1": {"status": "valid", "s": {"u": "https://preview.redd.it/img1.png?width=100&amp;auto=webp", "x": 100, "y": 100}},
            "img2": {"status": "valid", "s": {"u": "https://preview.redd.it/img2.png?width=100&amp;auto=webp", "x": 100, "y": 100}}
        }
    }
    """.data(using: .utf8)!
    let galleryPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: galleryJSON)
    check("gallery post decodes is_gallery", galleryPost.isGallery == true)
    check("gallery image URLs follow gallery_data order, not dictionary order", galleryPost.galleryImageURLs.map(\.absoluteString) == [
        "https://preview.redd.it/img2.png?width=100&auto=webp",
        "https://preview.redd.it/img1.png?width=100&auto=webp"
    ])
    check("gallery URLs are unescaped (&amp; -> &)", !galleryPost.galleryImageURLs[0].absoluteString.contains("&amp;"))
    check("non-gallery post has empty galleryImageURLs", post.galleryImageURLs.isEmpty)
}

// --- Reddit markdown rendering (bodyMarkdown/markdownNode) ---
// AttributedString.MarkdownParsingOptions is Darwin-only (not in
// Linux's FoundationEssentials), so RedditMarkdown.render falls back
// to linkified-but-unparsed text there. These checks only assert the
// linkification pre-processing, which runs on every platform; the
// actual markdown parse (bold/links rendering) is exercised by the
// iOS build succeeding, not this Linux-hosted executable.
@MainActor func checkRedditMarkdownRenderingBodyMarkdownMarkdownNode() async throws {
    let subredditLinkified = RedditMarkdown.linkifySubredditsAndUsers("check out r/swift today")
    check("linkify turns bare r/ mention into a markdown link", subredditLinkified.contains("[r/swift](https://reddit.com/r/swift)"))

    let userLinkified = RedditMarkdown.linkifySubredditsAndUsers("thanks u/johndoe for the help")
    check("linkify turns bare u/ mention into a markdown link", userLinkified.contains("[u/johndoe](https://reddit.com/u/johndoe)"))

    let plainLinkified = RedditMarkdown.linkifySubredditsAndUsers("no mentions here at all")
    check("linkify passes through text with no mentions unchanged", plainLinkified == "no mentions here at all")

    let renderedPlain = RedditMarkdown.render("no markdown here at all")
    check("render doesn't crash on plain text", String(renderedPlain.characters).contains("no markdown here at all"))
}

// --- Saved categories ---
// Clean up any leftover state from a prior run first, since
// UserDefaults persists across smoke test invocations.
@MainActor func checkSavedCategoriesApolloSSavedItemsCategoriesDatabase() async throws {
    SavedCategoryStore.saveCategories(SavedCategoryStore.loadCategories().filter { $0.name != "SmokeTestCategoryA" })
    check("addCategory succeeds for a new name", SavedCategoryStore.addCategory(named: "SmokeTestCategoryA"))
    check("addCategory rejects a duplicate name (case-insensitive)", !SavedCategoryStore.addCategory(named: "smoketestcategorya"))
    check("loadCategories includes the added category", SavedCategoryStore.loadCategories().contains { $0.name == "SmokeTestCategoryA" })

    SavedCategoryStore.assign(fullname: "t3_smoketest1", category: "SmokeTestCategoryA")
    check("category(for:) returns the assigned category", SavedCategoryStore.category(for: "t3_smoketest1") == "SmokeTestCategoryA")
    SavedCategoryStore.clearCategory(for: "t3_smoketest1")
    check("clearCategory removes the assignment", SavedCategoryStore.category(for: "t3_smoketest1") == nil)
    check("unassigned fullname has no category", SavedCategoryStore.category(for: "t3_neverassigned") == nil)
    // Clean up so repeated runs stay idempotent.
    SavedCategoryStore.saveCategories(SavedCategoryStore.loadCategories().filter { $0.name != "SmokeTestCategoryA" })
}

// --- Saved category rename/delete (Apollo-Reborn's editable Saved Categories) ---
@MainActor func checkSavedCategoryRenameDeleteApolloReborn() async throws {
    SavedCategoryStore.saveCategories(SavedCategoryStore.loadCategories().filter { !["SmokeRenameA", "SmokeRenameB"].contains($0.name) })
    SavedCategoryStore.addCategory(named: "SmokeRenameA")
    SavedCategoryStore.assign(fullname: "t3_renametest", category: "SmokeRenameA")
    check("renameCategory succeeds for a valid new name", SavedCategoryStore.renameCategory("SmokeRenameA", to: "SmokeRenameB"))
    check("renameCategory updates the category list", SavedCategoryStore.loadCategories().contains { $0.name == "SmokeRenameB" } && !SavedCategoryStore.loadCategories().contains { $0.name == "SmokeRenameA" })
    check("renameCategory re-points existing assignments", SavedCategoryStore.category(for: "t3_renametest") == "SmokeRenameB")
    SavedCategoryStore.addCategory(named: "SmokeRenameA")
    check("renameCategory rejects a name already used by another category", !SavedCategoryStore.renameCategory("SmokeRenameB", to: "SmokeRenameA"))
    SavedCategoryStore.deleteCategory("SmokeRenameB")
    check("deleteCategory removes the category", !SavedCategoryStore.loadCategories().contains { $0.name == "SmokeRenameB" })
    check("deleteCategory clears assignments pointing to it", SavedCategoryStore.category(for: "t3_renametest") == nil)
    SavedCategoryStore.saveCategories(SavedCategoryStore.loadCategories().filter { !["SmokeRenameA", "SmokeRenameB"].contains($0.name) })
}

// --- General settings ---
@MainActor func checkGeneralSettingsApolloSSettingsGeneralViewController() async throws {
    let defaultGeneral = GeneralSettings.default
    check("default general settings disables auto-collapse", !defaultGeneral.autoCollapseChildComments)
    check("default general settings disables auto-collapse-pinned", !defaultGeneral.autoCollapsePinnedComments)
    check("default general settings uses top sort (confirmed via Defaults.plist)", defaultGeneral.defaultCommentSort == "top")
    check("default general settings puts thumbnails on left (confirmed via Defaults.plist)", defaultGeneral.thumbnailsOnLeft)
    check("default thumbnail position is Left", defaultGeneral.thumbnailPosition == .left)
    var rightThumbnails = defaultGeneral
    rightThumbnails.thumbnailPosition = .right
    check("Thumbnail Position Right stores CompactModeLeftThumbnails as false", !rightThumbnails.thumbnailsOnLeft && rightThumbnails.thumbnailPosition == .right)
    rightThumbnails.thumbnailPosition = .left
    check("Thumbnail Position Left stores CompactModeLeftThumbnails as true", rightThumbnails.thumbnailsOnLeft)
    check("default general settings uses small thumbnails (confirmed via Defaults.plist)", defaultGeneral.thumbnailSize == .small)
    check("ThumbnailSize has 4 cases (hidden/small/medium/large - hidden added after a real on-device screenshot showed a compact row with thumbnails off)", ThumbnailSize.allCases.count == 4)
    check("thumbnail sizes are strictly increasing", ThumbnailSize.small.pointSize < ThumbnailSize.medium.pointSize && ThumbnailSize.medium.pointSize < ThumbnailSize.large.pointSize)
    let encodedGeneral = try! JSONEncoder().encode(defaultGeneral)
    let decodedGeneral = try! JSONDecoder().decode(GeneralSettings.self, from: encodedGeneral)
    check("GeneralSettings round-trips through Codable", decodedGeneral == defaultGeneral)
    check("default general settings plays YouTube inline, not in native app (confirmed via Defaults.plist)", !defaultGeneral.openVideosInYouTubeApp)
    check("YouTubeURLParser builds native app URL from video ID", YouTubeURLParser.nativeAppURL(forVideoID: "dQw4w9WgXcQ")?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    check("YouTubeURLParser native app URL carries the start time", YouTubeURLParser.nativeAppURL(forVideoID: "dQw4w9WgXcQ", startSeconds: 42)?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42" && YouTubeURLParser.nativeAppURL(forVideoID: "dQw4w9WgXcQ", startSeconds: 0)?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
}

// --- Comment age mode (Phoebus-only, inspired by RedReader) ---
@MainActor func checkCommentAgeMode() async throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let post = now.addingTimeInterval(-86400)
    let parent = post.addingTimeInterval(3 * 3600)
    let reply = parent.addingTimeInterval(120)
    check("comment age defaults to Since Posted", GeneralSettings.default.commentAgeMode == .sincePosted)
    check("Since Posted shows the plain age",
          CommentAgeFormatter.label(created: reply, postCreated: post, parentCreated: parent, mode: .sincePosted, now: now) == "20h")
    check("Since Posted shows 'now' under a minute",
          CommentAgeFormatter.label(created: now.addingTimeInterval(-30), postCreated: nil, parentCreated: nil, mode: .sincePosted, now: now) == "now")
    check("Relative to Post counts from the post",
          CommentAgeFormatter.label(created: reply, postCreated: post, parentCreated: parent, mode: .relativeToPost, now: now) == "+3h")
    check("Relative to Parent counts from the parent comment",
          CommentAgeFormatter.label(created: reply, postCreated: post, parentCreated: parent, mode: .relativeToParent, now: now) == "2m later")
    check("Relative to Parent falls back to the post for a top-level comment",
          CommentAgeFormatter.label(created: parent, postCreated: post, parentCreated: nil, mode: .relativeToParent, now: now) == "+3h")
    check("relative modes fall back to the plain age without the post",
          CommentAgeFormatter.label(created: reply, postCreated: nil, parentCreated: nil, mode: .relativeToPost, now: now) == "20h")
    check("a sub-minute gap reads in seconds",
          CommentAgeFormatter.label(created: parent.addingTimeInterval(45), postCreated: post, parentCreated: parent, mode: .relativeToParent, now: now) == "45s later")
    check("clock skew before the parent clamps to zero",
          CommentAgeFormatter.label(created: parent.addingTimeInterval(-5), postCreated: post, parentCreated: parent, mode: .relativeToParent, now: now) == "0s later")

    let treeJSON = Data(#"""
    [{"kind": "t1", "data": {"id": "a1", "name": "t1_a1", "author": "a", "body": "top", "score": 1,
      "created_utc": 1000, "parent_id": "t3_x", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false,
      "replies": {"kind": "Listing", "data": {"children": [
        {"kind": "t1", "data": {"id": "a2", "name": "t1_a2", "author": "b", "body": "reply", "score": 1,
          "created_utc": 4600, "parent_id": "t1_a1", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false}}
      ]}}}}]
    """#.utf8)
    let roots = CommentTreeBuilder.build(from: try! JSONDecoder().decode([JSONValue].self, from: treeJSON))
    let byName = CommentAgeFormatter.commentsByFullname(roots)
    check("commentsByFullname indexes nested replies", byName.count == 2 && byName["t1_a1"]?.id == "a1")
    if let replyComment = byName["t1_a2"] {
        check("a reply's parentID finds its parent in the index",
              CommentAgeFormatter.label(comment: replyComment, post: nil, parent: byName[replyComment.parentID],
                                        mode: .relativeToParent, now: now) == "1h later")
    } else {
        check("the reply decodes", false)
    }

    check("an unknown stored comment age mode decodes as Since Posted",
          (try? JSONDecoder().decode([CommentAgeMode].self, from: Data(#"["sideways"]"#.utf8)))?.first == .sincePosted)
    check("a GeneralSettings blob without commentAgeMode decodes as Since Posted",
          (try? JSONDecoder().decode(GeneralSettings.self, from: Data(#"{"defaultCommentSort":"top"}"#.utf8)))?.commentAgeMode == .sincePosted)
    // Settings backups carry the whole GeneralSettings blob.
    let source = UserDefaults(suiteName: "CommentAgeBackupSource")!
    source.removePersistentDomain(forName: "CommentAgeBackupSource")
    var ageSettings = GeneralSettings.default
    ageSettings.commentAgeMode = .relativeToParent
    GeneralSettingsStore.storage.save(ageSettings, to: source)
    let snapshot = try! JSONDecoder().decode([String: JSONValue].self,
                                             from: try! JSONEncoder().encode(SettingsDomainSnapshot.capture(from: source)))
    let target = UserDefaults(suiteName: "CommentAgeBackupTarget")!
    target.removePersistentDomain(forName: "CommentAgeBackupTarget")
    SettingsDomainSnapshot.restore(snapshot, into: target)
    check("comment age mode survives a settings backup round trip",
          GeneralSettingsStore.storage.load(from: target).commentAgeMode == .relativeToParent)
}

// --- Highlight own and followed users (Phoebus-only, inspired by RedReader and Continuum) ---
/// A stand-in friends list for `FollowedUsernames.friendsFetcher`, keyed by
/// the account active when the fetch finishes. While held, a fetch waits
/// for `release()`, so a check can act while one is in flight without
/// depending on how long anything takes.
private final class SmokeFriendsList: @unchecked Sendable {
    var byAccount: [String: [String]] = [:]
    var failing = false
    private let lock = NSLock()
    private var isHeld = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func hold() {
        lock.withLock { isHeld = true }
    }

    func release() {
        let resumed = lock.withLock {
            isHeld = false
            defer { waiting = [] }
            return waiting
        }
        for continuation in resumed { continuation.resume() }
    }

    func fetch() async -> [String]? {
        await withCheckedContinuation { continuation in
            let proceed = lock.withLock {
                if isHeld { waiting.append(continuation) }
                return !isHeld
            }
            if proceed { continuation.resume() }
        }
        if failing { return nil }
        return byAccount[FavoriteSubredditsAccountContext.currentUsernameProvider() ?? ""] ?? []
    }
}

@MainActor func checkAuthorHighlight() async throws {
    let followed: Set<String> = ["alice"]
    func resolve(_ author: String, _ distinguished: String? = nil, own: Bool = true, follow: Bool = true) -> AuthorHighlight {
        AuthorHighlight.resolve(author: author, distinguished: distinguished, ownUsername: "Me",
                                followedUsernames: followed, highlightOwn: own, highlightFollowed: follow)
    }
    check("your own name highlights, case-insensitively", resolve("me") == .own)
    check("a followed user highlights, case-insensitively", resolve("Alice") == .followed)
    check("anyone else is plain", resolve("bob") == .none)
    check("moderator distinguish wins over your own name", resolve("me", "moderator") == .moderator)
    check("admin distinguish wins over a followed user", resolve("alice", "admin") == .admin)
    check("own highlight off leaves your name plain", resolve("me", own: false) == .none)
    check("followed highlight off leaves followed users plain", resolve("alice", follow: false) == .none)
    check("[deleted] never highlights", resolve("[deleted]") == .none)
    check("your own name wins over following yourself",
          AuthorHighlight.resolve(author: "me", distinguished: nil, ownUsername: "me", followedUsernames: ["me"],
                                  highlightOwn: true, highlightFollowed: true) == .own)
    check("signed out, nothing is your own",
          AuthorHighlight.resolve(author: "me", distinguished: nil, ownUsername: nil, followedUsernames: [],
                                  highlightOwn: true, highlightFollowed: true) == .none)
    check("followed users come from u_ subscriptions",
          FollowedUsernames.from(subredditNames: ["u_Alice", "pics", "U_bob", "u_"]) == ["alice", "bob"])
    check("own highlight defaults on, followed off",
          GeneralSettings.default.highlightOwnUsername && !GeneralSettings.default.highlightFollowedUsers)
    check("a GeneralSettings blob without the highlight keys decodes their defaults",
          (try? JSONDecoder().decode(GeneralSettings.self, from: Data(#"{"defaultCommentSort":"top"}"#.utf8)))
              .map { $0.highlightOwnUsername && !$0.highlightFollowedUsers } == true)

    // The followed set is the u_ subscriptions plus the friends list, each
    // refreshed without dropping the other, per account.
    let savedProvider = FavoriteSubredditsAccountContext.currentUsernameProvider
    let savedFetcher = FollowedUsernames.friendsFetcher
    let friends = SmokeFriendsList()
    FollowedUsernames.friendsFetcher = { await friends.fetch() }
    FollowedUsernames.invalidate()
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smokehighlight" }
    func saveSubscriptions(_ names: [String]) {
        SubredditListCache.save(.init(subscriptions: names.compactMap(RedditSubreddit.named),
                                      multireddits: [], moderated: [], accountUsername: "smokehighlight"))
    }
    friends.byAccount = ["smokehighlight": ["Frank"]]
    saveSubscriptions(["u_Carol", "swift"])
    await FollowedUsernames.refreshFriends()
    check("the followed set is u_ subscriptions plus friends", FollowedUsernames.current() == ["carol", "frank"])
    friends.failing = true
    saveSubscriptions(["u_Gina"])
    await FollowedUsernames.refreshFriends()
    check("a subscriptions refresh replaces u_ names and keeps friends", FollowedUsernames.current() == ["gina", "frank"])
    friends.failing = false
    friends.byAccount = ["smokehighlight": ["Hank"]]
    await FollowedUsernames.refreshFriends()
    check("a friends refresh replaces friends and keeps u_ names", FollowedUsernames.current() == ["gina", "hank"])
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "someoneelse" }
    _ = FollowedUsernames.current()
    await FollowedUsernames.refreshFriends()
    check("another account does not inherit the followed set", FollowedUsernames.current().isEmpty)
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smokehighlight" }
    _ = FollowedUsernames.current()
    await FollowedUsernames.refreshFriends()
    check("switching back reloads both parts for that account", FollowedUsernames.current() == ["gina", "hank"])
    var highlightSettings = GeneralSettings.default
    highlightSettings.highlightFollowedUsers = true
    check("current() resolves own and followed for the active account",
          AuthorHighlight.current(author: "SmokeHighlight", distinguished: nil, settings: highlightSettings) == .own
              && AuthorHighlight.current(author: "hank", distinguished: nil, settings: highlightSettings) == .followed)

    nonisolated(unsafe) var changePosts = 0
    let changeObserver = NotificationCenter.default.addObserver(
        forName: FollowedUsernames.didChangeNotification, object: nil, queue: nil) { _ in changePosts += 1 }
    FollowedUsernames.setFollowed("Ivy", followed: true)
    check("following someone adds them to the set at once", FollowedUsernames.current() == ["gina", "hank", "ivy"])
    FollowedUsernames.setFollowed("HANK", followed: false)
    check("unfollowing someone removes them at once, case-insensitively", FollowedUsernames.current() == ["gina", "ivy"])
    check("follow and unfollow each announce the change", changePosts == 2)
    NotificationCenter.default.removeObserver(changeObserver)

    // The subscriptions refresh starts a friends fetch, held until the
    // follows below are made. The check waits for that fetch's own result
    // (its change notification): a refresh after the release could start a
    // second, newer fetch instead.
    friends.hold()
    saveSubscriptions(["u_Gina"])
    FollowedUsernames.setFollowed("Jill", followed: true)
    FollowedUsernames.setFollowed("Hank", followed: false)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let once = NSLock()
        nonisolated(unsafe) var resumed = false
        nonisolated(unsafe) var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: FollowedUsernames.didChangeNotification, object: nil, queue: nil) { _ in
            let first = once.withLock { defer { resumed = true }; return !resumed }
            guard first else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            continuation.resume()
        }
        friends.release()
    }
    check("follows made during a friends fetch survive its older result", FollowedUsernames.current() == ["gina", "jill"])

    FavoriteSubredditsAccountContext.currentUsernameProvider = { nil }
    FollowedUsernames.setFollowed("erin", followed: true)
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smokehighlight" }
    check("signed out, a follow changes nothing", !FollowedUsernames.current().contains("erin"))
    friends.byAccount = [:]
    SubredditListCache.clear()
    check("clearing the list clears the followed set", FollowedUsernames.current().isEmpty)
    await FollowedUsernames.refreshFriends()
    FollowedUsernames.friendsFetcher = savedFetcher
    FavoriteSubredditsAccountContext.currentUsernameProvider = savedProvider
    FollowedUsernames.invalidate()

    // Settings backups carry the whole GeneralSettings blob.
    let source = UserDefaults(suiteName: "AuthorHighlightBackupSource")!
    source.removePersistentDomain(forName: "AuthorHighlightBackupSource")
    var backed = GeneralSettings.default
    backed.highlightOwnUsername = false
    backed.highlightFollowedUsers = true
    GeneralSettingsStore.storage.save(backed, to: source)
    let snapshot = try! JSONDecoder().decode([String: JSONValue].self,
                                             from: try! JSONEncoder().encode(SettingsDomainSnapshot.capture(from: source)))
    let target = UserDefaults(suiteName: "AuthorHighlightBackupTarget")!
    target.removePersistentDomain(forName: "AuthorHighlightBackupTarget")
    SettingsDomainSnapshot.restore(snapshot, into: target)
    let restored = GeneralSettingsStore.storage.load(from: target)
    check("highlight settings survive a settings backup round trip",
          !restored.highlightOwnUsername && restored.highlightFollowedUsers)
}

// --- Auto-collapse pinned comments (Apollo-Reborn feature) ---
@MainActor func checkAutoCollapsePinnedCommentsApolloReborn() async throws {
    let pinnedCommentJSON = """
    [{"kind": "t1", "data": {"id": "p1", "name": "t1_p1", "author": "mod", "body": "pinned announcement", "score": 1,
      "created_utc": 0, "parent_id": "t3_x", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": true,
      "replies": {"kind": "Listing", "data": {"children": [
        {"kind": "t1", "data": {"id": "p2", "name": "t1_p2", "author": "b", "body": "reply", "score": 1,
          "created_utc": 0, "parent_id": "t1_p1", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false,
          "replies": {"kind": "Listing", "data": {"children": [
            {"kind": "t1", "data": {"id": "p3", "name": "t1_p3", "author": "c", "body": "nested pinned reply", "score": 1,
              "created_utc": 0, "parent_id": "t1_p2", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": true,
              "replies": {"kind": "Listing", "data": {"children": [
                {"kind": "t1", "data": {"id": "p4", "name": "t1_p4", "author": "d", "body": "grandchild reply", "score": 1,
                  "created_utc": 0, "parent_id": "t1_p3", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false}}
              ]}}}}
          ]}}}}
      ]}}}}]
    """.data(using: .utf8)!
    let pinnedValues = try! JSONDecoder().decode([JSONValue].self, from: pinnedCommentJSON)
    let pinnedCollapsedTree = CommentTreeBuilder.build(from: pinnedValues, autoCollapse: false, autoCollapsePinned: true)
    check("autoCollapsePinned collapses a top-level stickied comment with replies", pinnedCollapsedTree.first?.isCollapsed == true)
    check("autoCollapsePinned leaves a non-stickied comment with replies expanded", pinnedCollapsedTree.first?.children.first?.isCollapsed == false)
    check("autoCollapsePinned collapses a nested stickied comment with replies too (depth-independent)", pinnedCollapsedTree.first?.children.first?.children.first?.isCollapsed == true)
    let pinnedUncollapsedTree = CommentTreeBuilder.build(from: pinnedValues, autoCollapse: false, autoCollapsePinned: false)
    check("autoCollapsePinned: false leaves a stickied comment expanded", pinnedUncollapsedTree.first?.isCollapsed == false)
    // Reborn collapses every stickied comment, a lone AutoModerator notice
    // with no replies included.
    let lonePinnedJSON = Data(#"[{"kind": "t1", "data": {"id": "s1", "name": "t1_s1", "author": "AutoModerator", "body": "Rules", "score": 1, "created_utc": 0, "parent_id": "t3_x", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": true, "replies": ""}}]"#.utf8)
    let lonePinned = CommentTreeBuilder.build(from: try! JSONDecoder().decode([JSONValue].self, from: lonePinnedJSON), autoCollapsePinned: true)
    check("autoCollapsePinned collapses a stickied comment with no replies", lonePinned.first?.isCollapsed == true)
    // The collapsed badge counts the comment, its loaded replies and the
    // replies still behind "more" stubs.
    check("threadCount counts self, loaded replies and unloaded more-stub replies",
          CommentTreeNode(comment: lonePinned[0].comment, depth: 0,
                          children: [CommentTreeNode(comment: lonePinned[0].comment, depth: 1)],
                          moreStub: MoreStub(id: "m", count: 5, children: ["a"], parentID: "t1_s1", depth: 1)).threadCount == 7)
}

// --- Auto-collapse AutoModerator comments (Apollo-Reborn feature) ---
@MainActor func checkAutoCollapseAutoModeratorCommentsApolloReborn() async throws {
    let autoModeratorCommentJSON = """
    [{"kind": "t1", "data": {"id": "am1", "name": "t1_am1", "author": "AutoModerator", "body": "Please read the rules", "score": 1,
      "created_utc": 0, "parent_id": "t3_x", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false}},
     {"kind": "t1", "data": {"id": "am2", "name": "t1_am2", "author": "AutoModerator", "body": "Removal notice", "score": 1,
      "created_utc": 0, "parent_id": "t3_x", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false,
      "replies": {"kind": "Listing", "data": {"children": [
        {"kind": "t1", "data": {"id": "am3", "name": "t1_am3", "author": "human", "body": "reply to bot", "score": 1,
          "created_utc": 0, "parent_id": "t1_am2", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false}}
      ]}}}},
     {"kind": "t1", "data": {"id": "am4", "name": "t1_am4", "author": "human", "body": "a normal comment", "score": 1,
      "created_utc": 0, "parent_id": "t3_x", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false}}]
    """.data(using: .utf8)!
    let autoModeratorValues = try! JSONDecoder().decode([JSONValue].self, from: autoModeratorCommentJSON)
    let autoModeratorCollapsedTree = CommentTreeBuilder.build(from: autoModeratorValues, autoCollapseAutoModerator: true)
    check("autoCollapseAutoModerator collapses a leaf AutoModerator comment with no replies", autoModeratorCollapsedTree[0].isCollapsed == true)
    check("autoCollapseAutoModerator collapses an AutoModerator comment even though it has replies", autoModeratorCollapsedTree[1].isCollapsed == true)
    check("autoCollapseAutoModerator leaves that AutoModerator comment's own human reply expanded", autoModeratorCollapsedTree[1].children.first?.isCollapsed == false)
    check("autoCollapseAutoModerator leaves an unrelated human top-level comment expanded", autoModeratorCollapsedTree[2].isCollapsed == false)
    let autoModeratorUncollapsedTree = CommentTreeBuilder.build(from: autoModeratorValues, autoCollapseAutoModerator: false)
    check("autoCollapseAutoModerator: false leaves an AutoModerator comment expanded", autoModeratorUncollapsedTree[0].isCollapsed == false)
    let autoModeratorBuildRoots = CommentTreeBuilder.buildRoots(from: autoModeratorValues, postFullname: "t3_x", autoCollapseAutoModerator: true)
    check("buildRoots also honors autoCollapseAutoModerator", autoModeratorBuildRoots.roots[0].isCollapsed == true)
}

// --- New Account Highlight decision function (Apollo-Reborn feature) ---
// Pure function, no network access - exercises the exact boundary
// condition (`isNewAccount` uses `<`, so exactly-at-threshold is
// "not new").
@MainActor func checkNewAccountHighlightDecisionFunctionApollo() async throws {
    let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)
    let oneDayOldAccount = referenceNow.addingTimeInterval(-1 * 24 * 60 * 60)
    let sixtyDayOldAccount = referenceNow.addingTimeInterval(-60 * 24 * 60 * 60)
    let exactlyThirtyDayOldAccount = referenceNow.addingTimeInterval(-AccountAgeCache.newAccountThreshold)
    check("isNewAccount: true for a 1-day-old account", AccountAgeCache.isNewAccount(createdAt: oneDayOldAccount, referenceDate: referenceNow) == true)
    check("isNewAccount: false for a 60-day-old account", AccountAgeCache.isNewAccount(createdAt: sixtyDayOldAccount, referenceDate: referenceNow) == false)
    check("isNewAccount: false exactly at the threshold boundary", AccountAgeCache.isNewAccount(createdAt: exactlyThirtyDayOldAccount, referenceDate: referenceNow) == false)
}

// --- Recently Read Posts (Apollo-Reborn feature) ---
@MainActor func checkRecentlyReadPostsApolloRebornFeature() async throws {
    RecentlyReadStore.clearAll()
    check("RecentlyReadStore starts empty after clearAll", RecentlyReadStore.load().isEmpty)
    RecentlyReadStore.recordView(fullname: "t3_r1", title: "First", subreddit: "test", author: "a", permalink: "/r/test/comments/r1")
    RecentlyReadStore.recordView(fullname: "t3_r2", title: "Second", subreddit: "test", author: "b", permalink: "/r/test/comments/r2")
    check("RecentlyReadStore tracks recorded views", RecentlyReadStore.load().count == 2)
    check("RecentlyReadStore orders newest-first", RecentlyReadStore.load().first?.fullname == "t3_r2")
    RecentlyReadStore.recordView(fullname: "t3_r1", title: "First (revisited)", subreddit: "test", author: "a", permalink: "/r/test/comments/r1")
    check("RecentlyReadStore re-viewing a post moves it to the front without duplicating", RecentlyReadStore.load().count == 2 && RecentlyReadStore.load().first?.fullname == "t3_r1")
    RecentlyReadStore.clearAll()
    check("RecentlyReadStore clearAll empties the list", RecentlyReadStore.load().isEmpty)
}

// --- Author flair / award count (Apollo's ShowUserFlair/ShowAwards) ---
@MainActor func checkAuthorFlairAwardCountApolloS() async throws {
    let flairPostJSON = """
    {
        "id": "flair1", "name": "t3_flair1", "title": "Flair Post",
        "author": "someuser", "subreddit": "test", "selftext": "",
        "url": "https://example.com", "permalink": "/r/test/comments/flair1/x/",
        "score": 1, "upvote_ratio": 1.0, "num_comments": 0,
        "created_utc": 0, "is_self": false, "over_18": false,
        "spoiler": false, "stickied": false, "saved": false, "likes": null,
        "author_flair_text": "Verified Expert",
        "total_awards_received": 3
    }
    """.data(using: .utf8)!
    let flairPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: flairPostJSON)
    check("decodes author_flair_text", flairPost.authorFlairText == "Verified Expert")
    check("decodes total_awards_received", flairPost.totalAwardsReceived == 3)
    check("posts without author flair decode nil", post.authorFlairText == nil)
}

// --- Edited marker (Apollo's edited pencil) ---
@MainActor func checkEditedMarker() async throws {
    func commentEdited(_ raw: String) -> RedditEditedTime? {
        let json = """
        {"id":"e1","name":"t1_e1","author":"u","body":"b","score":0,"created_utc":1700000000,
         "parent_id":"t3_x","link_id":"t3_x","saved":false,"score_hidden":false,"stickied":false,
         "edited":\(raw)}
        """.data(using: .utf8)!
        return (try? JSONDecoder.reddit.decode(RedditComment.self, from: json))?.edited
    }
    check("edited false decodes as unedited", commentEdited("false") == RedditEditedTime(isEdited: false))
    check("an edited Unix time decodes to its date",
          commentEdited("1700003600")?.date == Date(timeIntervalSince1970: 1700003600))
    check("a fractional edited time decodes", commentEdited("1700003600.5")?.date == Date(timeIntervalSince1970: 1700003600.5))
    check("a bare edited true is edited with no time",
          commentEdited("true") == RedditEditedTime(isEdited: true) && commentEdited("true")?.date == nil)
    check("an unexpected edited shape still decodes the comment", commentEdited("{\"x\":1}")?.isEdited == false)
    check("edited null decodes as absent", commentEdited("null") == nil)
    check("a comment without edited decodes it nil", makeComment(id: "plain").edited == nil)
    check("a post without edited decodes it nil", post.edited == nil)

    let editedPostJSON = """
    {"id":"ep","name":"t3_ep","title":"t","author":"u","subreddit":"test","permalink":"/r/test/comments/ep/",
     "score":1,"num_comments":0,"created_utc":1700000000,"is_self":true,"over_18":false,"spoiler":false,
     "stickied":false,"saved":false,"edited":1700007200.0}
    """.data(using: .utf8)!
    let editedPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: editedPostJSON)
    check("a post decodes its edited time", editedPost.edited?.date == Date(timeIntervalSince1970: 1700007200))
    let cachedPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: try! JSONEncoder.reddit.encode(editedPost))
    check("a post's edited time survives the cache round-trip", cachedPost.edited == editedPost.edited)
    let cachedUnedited = try! JSONDecoder.reddit.decode(
        RedditEditedTime.self, from: try! JSONEncoder().encode(RedditEditedTime(isEdited: false)))
    check("an unedited value round-trips as false", cachedUnedited == RedditEditedTime(isEdited: false))

    let utc = TimeZone(identifier: "UTC")!
    let enUS = Locale(identifier: "en_US")
    let editedAt = RedditEditedTime(isEdited: true, date: Date(timeIntervalSince1970: 1700007200))
    check("the marker shows for an edited thing", EditedMarker.isShown(editedAt, enabled: true))
    check("the marker hides when Show Edited Marker is off", !EditedMarker.isShown(editedAt, enabled: false))
    check("the marker hides for an unedited thing", !EditedMarker.isShown(RedditEditedTime(isEdited: false), enabled: true))
    check("the marker hides when edited is absent", !EditedMarker.isShown(nil, enabled: true))
    let lines = EditedMarker.lines(editedAt, now: Date(timeIntervalSince1970: 1700007200 + 2 * 3600), timeZone: utc, locale: enUS)
    check("the edited detail title gives the compact age", lines.title == "Edited 2h Ago")
    check("the edited detail names the exact time", lines.message?.hasPrefix("Edited on November 15, 2023") == true)
    check("a just-made edit reads Just now",
          EditedMarker.lines(editedAt, now: Date(timeIntervalSince1970: 1700007230)).title == "Edited Just now")
    check("an edit with no time reads plain Edited", EditedMarker.lines(RedditEditedTime(isEdited: true)).title == "Edited")
    check("the age's tap adds the edit time under the creation time",
          EditedMarker.appendingTimestamp(editedAt, to: "Created line", timeZone: utc, locale: enUS)?
            .hasPrefix("Created line\nEdited Nov 15, 2023") == true)
    check("the age's tap is unchanged for an unedited thing",
          EditedMarker.appendingTimestamp(RedditEditedTime(isEdited: false), to: "Created line") == "Created line")
    check("Show Edited Marker defaults on", GeneralSettings.default.showEditedMarker)
    let saved = GeneralSettingsStore.load()
    var off = saved
    off.showEditedMarker = false
    GeneralSettingsStore.save(off)
    let backup = try! BackupBundle.decode(from: try! BackupBundle.captureCurrent().encoded())
    check("Show Edited Marker round-trips through a settings backup", backup.generalSettings.showEditedMarker == false)
    GeneralSettingsStore.save(saved)
}

// --- Subreddit traffic decoding ---
@MainActor func checkSubredditTrafficDecodingApolloSSubredditTrafficViewController() async throws {
    let trafficJSON = """
    {
        "day": [[1700000000, 100, 500], [1700086400, 120, 600]],
        "hour": [[1700000000, 10, 50]],
        "month": [[1698796800, 3000, 15000, 25]]
    }
    """.data(using: .utf8)!
    let traffic = try! JSONDecoder().decode(SubredditTraffic.self, from: trafficJSON)
    check("decodes day traffic points", traffic.day.count == 2)
    check("day traffic point has correct uniques/pageviews", traffic.day[0].uniques == 100 && traffic.day[0].pageviews == 500)
    check("month traffic includes subscriptions", traffic.month.first?.subscriptions == 25)
    check("day traffic has no subscriptions field", traffic.day.first?.subscriptions == nil)
}

// --- Unify Modmail in Inbox (unifyModmailInInbox) ---
// `InboxDisplayItem` lives in PhoebusUI (SwiftUI-dependent, not importable
// here); this exercises the underlying `lastUpdatedDate` parsing that its
// merge-sort key relies on.
@MainActor func checkUnifyModmailInInboxDeadToggle() async throws {
    check("ModmailConversation.lastUpdatedDate parses a real ISO-8601 timestamp", modmailConvo.lastUpdatedDate != nil)
    check("ModmailConversation.lastUpdatedDate is nil when lastUpdated is absent", modmailNoOwner.lastUpdatedDate == nil)
    let messageForMerge = try! JSONDecoder.reddit.decode(RedditMessage.self, from: """
    {"id":"msg1","name":"t4_msg1","author":"someone","subject":"hi","body":"hi","created_utc":1900000000,"new":true,"was_comment":false}
    """.data(using: .utf8)!)
    check("A message newer than a modmail conversation's lastUpdated sorts first", messageForMerge.created > (modmailConvo.lastUpdatedDate ?? .distantPast))
}

// --- Translator URL construction ---
// Apollo embeds translate.google.com/?text=<encoded> in an in-app browser
// rather than using a translation API; this checks that URL is built correctly.
@MainActor func checkTranslatorURLConstructionApolloSTranslatorViewController() async throws {
    check("builds the correct translate.google.com URL", TranslatorURLBuilder.translateURL(for: "hello world")?.absoluteString == "https://translate.google.com/?text=hello%20world")
    check("percent-encodes special characters in the query", TranslatorURLBuilder.translateURL(for: "café & résumé")?.query?.contains("caf") == true)
    check("returns nil for empty text", TranslatorURLBuilder.translateURL(for: "") == nil)
}

// --- New comments tracker ---
@MainActor func checkNewCommentsTrackerApolloSNewCommentsTracker() async throws {
    let trackerPostID = "smoketest_post_\(UUID().uuidString)"
    check("first visit to a post has no new comments", NewCommentsTracker.newCommentIDs(postID: trackerPostID, currentIDs: ["c1", "c2"]).isEmpty)
    NewCommentsTracker.markSeen(postID: trackerPostID, commentIDs: ["c1", "c2"])
    let secondVisitNew = NewCommentsTracker.newCommentIDs(postID: trackerPostID, currentIDs: ["c1", "c2", "c3"])
    check("second visit identifies only the genuinely new comment", secondVisitNew == ["c3"])
    NewCommentsTracker.markSeen(postID: trackerPostID, commentIDs: ["c1", "c2", "c3"])
    check("after marking seen, no comments are new anymore", NewCommentsTracker.newCommentIDs(postID: trackerPostID, currentIDs: ["c1", "c2", "c3"]).isEmpty)
}

// --- Comment tree allIDs (used by NewCommentsTracker) ---
@MainActor func checkCommentTreeAllIDsUsedByNewCommentsTracker() async throws {
    let allIDsTree = collapsedTree
    check("allIDs includes every comment regardless of collapse state", Set(allIDsTree.flatMap { $0.allIDs() }) == ["c1", "c2"])
}

// --- YouTube URL parsing ---
@MainActor func checkYouTubeURLParsingApolloSYouTubePlayerController() async throws {
    check("extracts video ID from standard watch URL", YouTubeURLParser.extractVideoID(from: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!) == "dQw4w9WgXcQ")
    check("extracts video ID from youtu.be short URL", YouTubeURLParser.extractVideoID(from: URL(string: "https://youtu.be/dQw4w9WgXcQ")!) == "dQw4w9WgXcQ")
    check("extracts video ID from shorts URL", YouTubeURLParser.extractVideoID(from: URL(string: "https://www.youtube.com/shorts/abc123XYZ00")!) == "abc123XYZ00")
    check("extracts video ID with extra query params", YouTubeURLParser.extractVideoID(from: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s")!) == "dQw4w9WgXcQ")
    check("returns nil for non-YouTube URL", YouTubeURLParser.extractVideoID(from: URL(string: "https://example.com/watch?v=abc")!) == nil)

    // The embed page: loaded under an app-identifying https origin, never youtube.com itself.
    let embedOrigin = YouTubeEmbed.origin(bundleIdentifier: "com.Pendo324.Phoebus")
    check("YouTubeEmbed origin is the lowercased bundle id over https", embedOrigin.absoluteString == "https://com.pendo324.phoebus")
    check("YouTubeEmbed origin falls back when there is no bundle id", YouTubeEmbed.origin(bundleIdentifier: nil).host == "phoebus")
    check("YouTubeEmbed origin is not a YouTube host", !(embedOrigin.host ?? "").contains("youtube"))
    check("YouTubeEmbed accepts an 11-character video ID", YouTubeEmbed.isValidVideoID("dQw4w9WgXcQ") && YouTubeEmbed.isValidVideoID("a-b_c1D2e3F"))
    check("YouTubeEmbed rejects video IDs that would not be safe in the page",
          !YouTubeEmbed.isValidVideoID("") && !YouTubeEmbed.isValidVideoID("short")
            && !YouTubeEmbed.isValidVideoID("dQw4w9WgXc'") && !YouTubeEmbed.isValidVideoID("dQw4w9WgXcQ1"))
    let embedHTML = YouTubeEmbed.html(videoID: "dQw4w9WgXcQ", startSeconds: 42, origin: embedOrigin, captionsWanted: false) ?? ""
    check("YouTubeEmbed page uses the IFrame API for the video at the start time",
          embedHTML.contains("https://www.youtube.com/iframe_api") && embedHTML.contains("videoId: 'dQw4w9WgXcQ'") && embedHTML.contains("start: 42"))
    check("YouTubeEmbed page passes the app origin as origin and widget_referrer",
          embedHTML.contains("origin: 'https://com.pendo324.phoebus'") && embedHTML.contains("widget_referrer: 'https://com.pendo324.phoebus'"))
    check("YouTubeEmbed page loads with captions off when they aren't wanted", embedHTML.contains("cc_load_policy: 0"))
    check("YouTubeEmbed page loads with captions on when they are wanted",
          (YouTubeEmbed.html(videoID: "dQw4w9WgXcQ", startSeconds: 0, origin: embedOrigin, captionsWanted: true) ?? "").contains("cc_load_policy: 1"))
    check("YouTubeEmbed page reports errors to the message handler",
          embedHTML.contains("messageHandlers.phoebusYouTube.postMessage") && embedHTML.contains("onError"))
    check("YouTubeEmbed page clamps a negative start time", (YouTubeEmbed.html(videoID: "dQw4w9WgXcQ", startSeconds: -5, origin: embedOrigin, captionsWanted: false) ?? "").contains("start: 0"))
    check("YouTubeEmbed builds no page for an invalid video ID", YouTubeEmbed.html(videoID: "x'};alert(1);//", startSeconds: 0, origin: embedOrigin, captionsWanted: false) == nil)
    check("YouTubeEmbed treats removed, private and embedding-disabled videos as unplayable inline",
          [100, 101, 150, 152, 153].allSatisfy { YouTubeEmbed.isUnplayableInline(errorCode: $0) })
    check("YouTubeEmbed keeps playing through parameter and transient player errors",
          !YouTubeEmbed.isUnplayableInline(errorCode: 2) && !YouTubeEmbed.isUnplayableInline(errorCode: 5))
}

// --- Mod queue report reason parsing ---
// Shape matches Reddit's real /about/modqueue listing response for a
// reported comment (t1): user_reports is [[reasonText, count], ...],
// mod_reports is [[reasonText, moderatorName], ...].
@MainActor func checkModQueueReportReasonParsingApollo() async throws {
    let modQueueJSON: [String: JSONValue] = [
        "id": .string("mq1"),
        "name": .string("t1_mq1"),
        "author": .string("someuser"),
        "body": .string("reported comment text"),
        "num_reports": .number(3),
        "user_reports": .array([
            .array([.string("Spam"), .number(2)]),
            .array([.string("Harassment"), .number(1)]),
        ]),
        "mod_reports": .array([
            .array([.string("Breaks rule 3"), .string("modusername")]),
        ]),
    ]
    let modQueueItem = ModQueueItem(kind: "t1", raw: modQueueJSON)
    check("ModQueueItem parses successfully from a comment shape", modQueueItem != nil)
    check("ModQueueItem falls back to 'Comment' title for t1 kind", modQueueItem?.title == "Comment")
    check("ModQueueItem parses num_reports", modQueueItem?.numReports == 3)
    check("ModQueueItem parses user_reports reasons and counts", modQueueItem?.userReportReasons.map(\.reason) == ["Spam", "Harassment"])
    check("ModQueueItem parses user_reports counts correctly", modQueueItem?.userReportReasons.map(\.count) == [2, 1])
    check("ModQueueItem parses mod_reports reason and moderator", modQueueItem?.modReportReasons.first?.reason == "Breaks rule 3" && modQueueItem?.modReportReasons.first?.moderator == "modusername")

    let modQueuePostJSON: [String: JSONValue] = [
        "id": .string("mq2"),
        "name": .string("t3_mq2"),
        "author": .string("someuser"),
        "title": .string("Reported Post Title"),
        "selftext": .string("post body"),
        "num_reports": .number(0),
    ]
    let modQueuePost = ModQueueItem(kind: "t3", raw: modQueuePostJSON)
    check("ModQueueItem parses a t3 post's real title, not 'Comment'", modQueuePost?.title == "Reported Post Title")
    check("ModQueueItem with no reports has empty reason arrays", modQueuePost?.userReportReasons.isEmpty == true && modQueuePost?.modReportReasons.isEmpty == true)

    let malformedModQueueJSON: [String: JSONValue] = ["author": .string("x")]
    check("ModQueueItem init fails gracefully on missing required fields", ModQueueItem(kind: "t1", raw: malformedModQueueJSON) == nil)
}

// --- Quote-as-blockquote transform ---
@MainActor func checkQuoteAsBlockquoteTransformApolloS() async throws {
    let singleLineQuote = RedditMarkdown.asBlockquote("Just one line")
    check("single-line quote gets a single > prefix", singleLineQuote == "> Just one line\n\n")

    let multiLineQuote = RedditMarkdown.asBlockquote("Line one\nLine two\nLine three")
    check("multi-line quote prefixes every line with >", multiLineQuote == "> Line one\n> Line two\n> Line three\n\n")

    let blankLineQuote = RedditMarkdown.asBlockquote("First\n\nThird")
    check("blockquote preserves blank lines with their own > prefix", blankLineQuote == "> First\n> \n> Third\n\n")
}

// --- Custom Subreddit Sources (Apollo-Reborn feature) ---
@MainActor func checkCustomSubredditSourcesApolloRebornFeature() async throws {
    check("default custom subreddit source settings use Reddit's own endpoints", CustomSubredditSourceSettings.default.randomSourceURL == nil && CustomSubredditSourceSettings.default.trendingSourceURL == nil && CustomSubredditSourceSettings.default.randomNSFWSourceURL == nil)
    let bareArrayJSON = "[\"aww\", \"r/cats\", \"pics\"]".data(using: .utf8)!
    check("CustomSubredditSourceClient.parseNames handles a bare array and strips r/ prefixes", try! CustomSubredditSourceClient.parseNames(from: bareArrayJSON) == ["aww", "cats", "pics"])
    let wrappedJSON = "{\"subreddits\": [\"funny\", \"todayilearned\"]}".data(using: .utf8)!
    check("CustomSubredditSourceClient.parseNames handles a {subreddits:[...]} wrapper", try! CustomSubredditSourceClient.parseNames(from: wrappedJSON) == ["funny", "todayilearned"])
    let malformedJSON = "not json".data(using: .utf8)!
    var parseNamesThrew = false
    do { _ = try CustomSubredditSourceClient.parseNames(from: malformedJSON) } catch { parseNamesThrew = true }
    check("CustomSubredditSourceClient.parseNames throws on malformed input", parseNamesThrew)
    // Reborn #1272's test data; we also keep an `r/`-prefixed line, as the JSON
    // forms always have.
    let rebornTextSource = "18_19\n  valid_name  \nSubreddits working as of Dec/2024\ntwo words\nr/prefixed\nemoji_\u{1F6AB}\na\nab\nde\nit\nabcdefghijklmnopqrstu\nabcdefghijklmnopqrstuv\n\n".data(using: .utf8)!
    check("subreddit sources: Reborn's plain-text lists parse, invalid lines dropped",
          (try? CustomSubredditSourceClient.parseNames(from: rebornTextSource))
            == ["18_19", "valid_name", "prefixed", "ab", "de", "it", "abcdefghijklmnopqrstu"])
    check("subreddit sources: invalid names are dropped from JSON too",
          (try? CustomSubredditSourceClient.parseNames(from: Data(#"["pics","Dec/2024","two words"]"#.utf8))) == ["pics"])
    let pool = (1...30).map { "sub\($0)" }
    let sampled = CustomSubredditSourceClient.sample(pool + ["SUB1"], limit: 5)
    check("trending samples N distinct names from the whole list, as Reborn's",
          sampled.count == 5 && Set(sampled.map { $0.lowercased() }).count == 5 && sampled.allSatisfy(pool.contains))
    check("trending keeps the whole list in order when the limit covers it or is 0",
          CustomSubredditSourceClient.sample(["a", "b", "c"], limit: 0) == ["a", "b", "c"]
              && CustomSubredditSourceClient.sample(["a", "b", "c"], limit: 3) == ["a", "b", "c"])
    let emptySources = CustomSubredditSourceSettings.default
    check("empty Random/Trending sources mean Reborn's hosted lists; RandNSFW has none",
          emptySources.effectiveRandomSourceURL == "https://jeffreyca.github.io/subreddits/popular.txt"
              && emptySources.effectiveTrendingSourceURL == "https://jeffreyca.github.io/subreddits/trending-subriff-blended.txt"
              && emptySources.effectiveRandomNSFWSourceURL == nil)
}

// --- Trending subreddit title parsing (Apollo-Reborn feature) ---
@MainActor func checkTrendingSubredditTitleParsingApolloReborn() async throws {
    check("TrendingSubredditTitleParser parses a comma-separated title", TrendingSubredditTitleParser.parseSubredditNames(fromTitle: "Your daily trending subreddits | r/aww, r/cats, r/pics") == ["aww", "cats", "pics"])
    check("TrendingSubredditTitleParser dedupes repeated mentions case-insensitively", TrendingSubredditTitleParser.parseSubredditNames(fromTitle: "r/AWW and r/aww again") == ["AWW"])
    check("TrendingSubredditTitleParser excludes a self-reference to r/trendingsubreddits", TrendingSubredditTitleParser.parseSubredditNames(fromTitle: "r/trendingsubreddits presents: r/funny") == ["funny"])
    check("TrendingSubredditTitleParser returns empty for a title with no r/ mentions", TrendingSubredditTitleParser.parseSubredditNames(fromTitle: "No subreddits here").isEmpty)
}

// --- Search history and saved searches (Phoebus addition) ---
@MainActor func checkSearchHistoryAndSavedSearches() async throws {
    let savedCurrent = FavoriteSubredditsAccountContext.currentUsernameProvider
    let savedHistory = SearchHistoryStore.storage.load()
    let savedSettings = SearchHistorySettingsStore.load()
    defer {
        FavoriteSubredditsAccountContext.currentUsernameProvider = savedCurrent
        SearchHistoryStore.storage.save(savedHistory)
        SearchHistorySettingsStore.storage.save(savedSettings)
    }
    SearchHistoryStore.storage.save([:])
    SearchHistorySettingsStore.storage.save(.default)
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "SmokeOne" }

    check("Save Search History defaults on", SearchHistorySettings.default.saveHistory)
    let legacy = try? JSONDecoder().decode(SearchHistorySettings.self, from: Data("{}".utf8))
    check("search history settings without fields decode to the defaults", legacy == .default)
    let older = try? JSONDecoder().decode(SearchHistorySettings.self,
                                          from: Data(#"{"saveHistory":false,"showTrendingSearches":true}"#.utf8))
    check("an older blob with the removed trending field still decodes", older?.saveHistory == false)

    let t0 = Date(timeIntervalSince1970: 1_000)
    SearchHistoryStore.record(query: "swift", at: t0)
    SearchHistoryStore.record(query: "  rust  ", at: t0.addingTimeInterval(1))
    SearchHistoryStore.record(query: "SWIFT", at: t0.addingTimeInterval(2))
    SearchHistoryStore.record(query: "   ")
    let siteWide = SearchHistoryStore.lists().recent(subreddit: "")
    check("recent searches are newest first and de-duplicated case-insensitively",
          siteWide.map(\.query) == ["SWIFT", "rust"])
    SearchHistoryStore.record(query: "swift", subreddit: "iOSProgramming")
    SearchHistoryStore.record(query: "swift", engine: .google)
    let lists = SearchHistoryStore.lists()
    check("a subreddit's recent searches are kept apart from all of Reddit",
          lists.recent(subreddit: "iosprogramming").map(\.query) == ["swift"]
              && lists.recent(subreddit: "").count == 3)
    check("the same query on Google is its own entry",
          lists.recent(subreddit: "").first?.searchEngine == .google)
    SearchHistoryStore.record(query: "swift", subreddit: "iOSProgramming", engine: .kagi)
    check("a Kagi search is recorded site-wide, as its own entry",
          SearchHistoryStore.lists().recent(subreddit: "").first?.searchEngine == .kagi
              && SearchHistoryStore.lists().recent(subreddit: "iosprogramming").count == 1)
    if let kagi = SearchHistoryStore.lists().recent(subreddit: "").first { SearchHistoryStore.remove(kagi) }

    let many = (0..<40).reduce([RecentSearch]()) { list, i in
        SearchHistoryStore.inserting(RecentSearch(query: "q\(i)"), into: list)
    }
    check("recent searches are capped at 30, dropping the oldest",
          many.count == SearchHistoryStore.recentLimit && many.first?.query == "q39" && many.last?.query == "q10")

    SearchHistoryStore.remove(lists.recent(subreddit: "")[1])
    check("removing a recent search removes only that one",
          SearchHistoryStore.lists().recent(subreddit: "").map(\.query) == ["swift", "rust"])

    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smoketwo" }
    check("another account starts with no search history",
          SearchHistoryStore.lists().recent.isEmpty)
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smokeone" }
    check("the account key is case-insensitive",
          SearchHistoryStore.lists().recent.count == 3)

    let top = SavedSearch(query: "eclipse", subreddit: "pics", sort: "top", time: "week")
    SearchHistoryStore.save(top)
    SearchHistoryStore.save(SavedSearch(query: "Eclipse", subreddit: "PICS", sort: "top", time: "week"))
    check("saving the same query, scope, sort and time twice keeps one",
          SearchHistoryStore.lists().saved.count == 1 && SearchHistoryStore.isSaved(top))
    check("a different time range is a different saved search",
          !SearchHistoryStore.isSaved(SavedSearch(query: "eclipse", subreddit: "pics", sort: "top", time: "day")))
    check("a sort without a time range drops the time",
          SavedSearch(query: "x", sort: "new", time: "week").time == nil)

    SearchHistorySettingsStore.storage.update { $0.saveHistory = false }
    SearchHistoryStore.record(query: "private")
    check("nothing is recorded with Save Search History off",
          !SearchHistoryStore.lists().recent.contains { $0.query == "private" })
    SearchHistorySettingsStore.storage.update { $0.saveHistory = true }

    // Backups: both keys are in the snapshot and survive the JSON round trip.
    check("search history and its settings are backed up",
          SettingsDomainSnapshot.isBackedUp(SearchHistoryStore.storage.key)
              && SettingsDomainSnapshot.isBackedUp(SearchHistorySettingsStore.storage.key))
    let before = SearchHistoryStore.storage.load()
    let snapshot = SettingsDomainSnapshot.capture()
    let encoded = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: encoded)
    let target = UserDefaults(suiteName: "SearchHistoryRestore")!
    target.removePersistentDomain(forName: "SearchHistoryRestore")
    SettingsDomainSnapshot.restore(decoded, into: target)
    check("search history round-trips through a backup",
          SearchHistoryStore.storage.load(from: target) == before
              && SearchHistoryStore.storage.load(from: target)["smokeone"]?.saved.first?.time == "week")
    target.removePersistentDomain(forName: "SearchHistoryRestore")

    SearchHistoryStore.clearRecent(subreddit: "iOSProgramming")
    check("Clear in a feed's search clears only that subreddit",
          SearchHistoryStore.lists().recent.map(\.subreddit) == ["", ""])
    SearchHistoryStore.clearAllRecent()
    check("Clear Search History removes recents but keeps saved searches",
          SearchHistoryStore.lists().recent.isEmpty && SearchHistoryStore.lists().saved.count == 1)
    SearchHistoryStore.unsave(top)
    check("removing a saved search", SearchHistoryStore.lists().saved.isEmpty)
}

// --- User search (Phoebus addition) ---
@MainActor func checkUserSearch() async throws {
    let listing = Data("""
    {"kind": "Listing", "data": {"after": null, "children": [
      {"kind": "t2", "data": {"name": "spez", "icon_img": "https://styles.redditmedia.com/a.png?w=256&amp;s=1",
        "link_karma": 150000, "comment_karma": 750000, "created_utc": 1118030400.0,
        "subreddit": {"public_description": "Reddit CEO"}}},
      {"kind": "t2", "data": {"name": "spez_fan", "icon_img": "", "snoovatar_img": "https://i.redd.it/snoo.png",
        "link_karma": 12, "comment_karma": 30, "created_utc": 1700000000}},
      {"kind": "t2", "data": {"name": "gone_account", "is_suspended": true}},
      {"kind": "t5", "data": {"display_name": "spez"}}
    ]}}
    """.utf8)
    let users = try UserSearch.parse(listing)
    check("user search keeps only t2 accounts, in order", users.map(\.name) == ["spez", "spez_fan", "gone_account"])
    check("a user's karma adds link and comment karma", users.first?.karma == 900_000)
    check("an escaped avatar URL is unescaped",
          users.first?.iconURL?.absoluteString == "https://styles.redditmedia.com/a.png?w=256&s=1")
    check("an empty icon falls back to the snoovatar", users[1].iconURL?.absoluteString == "https://i.redd.it/snoo.png")
    check("a suspended account parses with only its name", users[2].isSuspended && users[2].created == nil)
    check("an empty user search ({}) parses as no accounts", (try? UserSearch.parse(Data("{}".utf8)))?.isEmpty == true)

    let now = Date(timeIntervalSince1970: 1_118_030_400 + 86400 * 365 * 21 + 86400 * 10)
    check("a user row reads karma and account age", UserSearch.subtitle(for: users[0], now: now) == "900k karma \u{00B7} 21y")
    check("a suspended user row says so", UserSearch.subtitle(for: users[2]) == "Suspended")

    check("u/ and /u/ prefixes are dropped from the query",
          UserSearch.normalizedQuery(" u/spez ") == "spez" && UserSearch.normalizedQuery("/u/Spez") == "Spez")
    check("usernames are 3-20 letters, digits, _ or -",
          UserSearch.isPossibleUsername("spez") && UserSearch.isPossibleUsername("a-b_c")
              && !UserSearch.isPossibleUsername("ab") && !UserSearch.isPossibleUsername("two words"))

    let about = Data(#"{"kind": "t2", "data": {"name": "Spez", "link_karma": 1, "comment_karma": 2}}"#.utf8)
    let exact = UserSearch.parseAccount(about)
    check("an exact lookup parses /user/name/about", exact?.name == "Spez")
    check("the exact account goes first without a duplicate",
          UserSearch.merging(exact: exact, into: users).map(\.name) == ["Spez", "spez_fan", "gone_account"])
    check("blocked users are left out of user search",
          UserSearch.visible(users, blocked: ["spez_fan"]).map(\.name) == ["spez", "gone_account"])

    let savedCurrent = FavoriteSubredditsAccountContext.currentUsernameProvider
    let savedHistory = SearchHistoryStore.storage.load()
    defer {
        FavoriteSubredditsAccountContext.currentUsernameProvider = savedCurrent
        SearchHistoryStore.storage.save(savedHistory)
    }
    SearchHistoryStore.storage.save([:])
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "smokeone" }
    SearchHistoryStore.record(query: "spez")
    SearchHistoryStore.record(user: "spez")
    let recent = SearchHistoryStore.lists().recent(subreddit: "")
    check("an opened user is its own recent entry beside the same post query",
          recent.map(\.kind) == [.user, .posts])
    let legacy = try? JSONDecoder().decode(RecentSearch.self,
                                           from: Data(#"{"query":"x","subreddit":"","engine":0,"searchedAt":0}"#.utf8))
    check("a recent search saved before user search reads as a post search", legacy?.kind == .posts)
}

// --- Tag Filters (Apollo-Reborn feature) ---
// Shape: enabled/nsfw/spoiler flags and `{nsfw, spoiler}` per-subreddit
// overrides (no three-way mode per tag, blur-titles switch or single-bool
// override).
@MainActor func checkTagFiltersApolloRebornFeature() async throws {
    check("default tag filters: disabled, NSFW on, Spoiler on, no overrides", !TagFilterSettings.default.enabled && TagFilterSettings.default.nsfw && TagFilterSettings.default.spoiler && TagFilterSettings.default.subredditOverrides.isEmpty)
    let tfOn = TagFilterSettings(enabled: true, nsfw: true, spoiler: false, subredditOverrides: [:])
    check("shouldBlur returns false for a non-flagged post", !tfOn.shouldBlur(subreddit: "test", isNSFW: false, isSpoiler: false))
    check("shouldBlur returns true for NSFW when the NSFW tag is on", tfOn.shouldBlur(subreddit: "test", isNSFW: true, isSpoiler: false))
    check("shouldBlur returns false for spoiler when the Spoiler tag is off", !tfOn.shouldBlur(subreddit: "test", isNSFW: false, isSpoiler: true))
    check("shouldBlur is off entirely while Enable Tag Filters is off", !TagFilterSettings(enabled: false, nsfw: true, spoiler: true, subredditOverrides: [:]).shouldBlur(subreddit: "t", isNSFW: true, isSpoiler: true))
    let tfOverride = TagFilterSettings(enabled: true, nsfw: false, spoiler: false, subredditOverrides: ["gore": .init(nsfw: true)])
    check("per-subreddit override turns one tag on when global is off", tfOverride.shouldBlur(subreddit: "gore", isNSFW: true, isSpoiler: false))
    check("per-subreddit override is case-insensitive", tfOverride.shouldBlur(subreddit: "GORE", isNSFW: true, isSpoiler: false))
    check("an absent tag in an override falls back to global", !tfOverride.shouldBlur(subreddit: "gore", isNSFW: false, isSpoiler: true))
    check("override summary reads like overrideSummaryForSubreddit:", TagFilterSettings.Override(nsfw: true, spoiler: false).summary == "NSFW: on · Spoiler: off" && TagFilterSettings.Override().summary == "(uses global)")
    check("a legacy single-bool override decodes into both tags", (try? JSONDecoder().decode(TagFilterSettings.self, from: Data(#"{"nsfwMode":"always","subredditOverrides":{"x":true}}"#.utf8)))?.subredditOverrides["x"] == TagFilterSettings.Override(nsfw: true, spoiler: true))
    TagFilterStore.setOverride(subreddit: "smoketestsub", .init(nsfw: true))
    check("TagFilterStore.setOverride persists an override", TagFilterStore.load().subredditOverrides["smoketestsub"]?.nsfw == true)
    TagFilterStore.setOverride(subreddit: "smoketestsub", nil)
    check("TagFilterStore.setOverride(nil) removes an override", TagFilterStore.load().subredditOverrides["smoketestsub"] == nil)
}

// --- Avatar cache (Apollo-Reborn "Show User Profile Pictures") ---
@MainActor func checkAvatarCacheApolloRebornShowUser() async throws {
    check("default general settings disables user profile pictures (extra network cost, off by default)", !GeneralSettings.default.showUserProfilePictures)
    let avatarTask = Task { () -> (String?, Bool, String?, Bool) in
        await AvatarCache.shared.clear()
        let beforeStore = await AvatarCache.shared.cachedURL(for: "smoketestuser")
        let hadFreshBefore = await AvatarCache.shared.hasFreshEntry(for: "smoketestuser")
        await AvatarCache.shared.store(url: "https://example.com/avatar.png", for: "SmokeTestUser")
        let afterStore = await AvatarCache.shared.cachedURL(for: "smoketestuser")
        let hadFreshAfter = await AvatarCache.shared.hasFreshEntry(for: "smoketestuser")
        return (beforeStore, hadFreshBefore, afterStore, hadFreshAfter)
    }
    let avatarResult = await avatarTask.value
    check("AvatarCache has no entry before storing", avatarResult.0 == nil && avatarResult.1 == false)
    check("AvatarCache lookup is case-insensitive on username", avatarResult.2 == "https://example.com/avatar.png")
    check("AvatarCache reports a fresh entry after storing", avatarResult.3 == true)
    let avatarNilTask = Task { () -> String? in
        await AvatarCache.shared.store(url: nil, for: "novatar")
        return await AvatarCache.shared.cachedURL(for: "novatar")
    }
    let avatarNilResult = await avatarNilTask.value
    check("AvatarCache can cache a 'no avatar' result as nil", avatarNilResult == nil)
    let avatarNilFreshTask = Task { () -> Bool in
        await AvatarCache.shared.hasFreshEntry(for: "novatar")
    }
    let avatarNilFreshResult = await avatarNilFreshTask.value
    check("AvatarCache distinguishes 'no avatar cached' from 'unknown user' via hasFreshEntry", avatarNilFreshResult == true)
}

// --- Steam deep linking (Apollo-Reborn feature) ---
@MainActor func checkSteamDeepLinkingApolloRebornFeature() async throws {
    let steamAppURL = URL(string: "https://store.steampowered.com/app/730/CounterStrike_2/")!
    let steamAppItem = SteamURLParser.extractItem(from: steamAppURL)
    check("SteamURLParser extracts an app ID from a store.steampowered.com/app URL", steamAppItem?.kind == .app && steamAppItem?.id == "730")
    let steamSubURL = URL(string: "https://store.steampowered.com/sub/12345/")!
    let steamSubItem = SteamURLParser.extractItem(from: steamSubURL)
    check("SteamURLParser extracts a sub ID from a store.steampowered.com/sub URL", steamSubItem?.kind == .sub && steamSubItem?.id == "12345")
    check("SteamURLParser returns nil for a non-Steam URL", SteamURLParser.extractItem(from: URL(string: "https://example.com/app/730")!) == nil)
    check("SteamURLParser returns nil for a Steam URL with a non-numeric ID", SteamURLParser.extractItem(from: URL(string: "https://store.steampowered.com/app/notanumber")!) == nil)
    check("SteamURLParser.nativeAppURL builds the correct steam:// URL for an app", SteamURLParser.nativeAppURL(kind: .app, id: "730")?.absoluteString == "steam://store/730")
    check("SteamURLParser.nativeAppURL builds the correct steam:// URL for a sub", SteamURLParser.nativeAppURL(kind: .sub, id: "12345")?.absoluteString == "steam://store/sub/12345")
}

// --- Backup & Restore (Apollo-Reborn feature) ---
// Establish a known, non-default state, then verify a captured bundle
// round-trips through encode/decode and restore() faithfully.
@MainActor func checkBackupRestoreApolloRebornFeature() async throws {
    ContentFilterStore.save([ContentFilter(kind: .subreddit, value: "smoketestbackupsub")])
    TagFilterStore.save(TagFilterSettings(enabled: true, nsfw: true, spoiler: false, subredditOverrides: ["backuptest": .init(nsfw: true)]))
    GeneralSettingsStore.save(GeneralSettings(autoCollapseChildComments: true, autoCollapsePinnedComments: true, defaultCommentSort: "new", thumbnailsOnLeft: false, thumbnailSize: .large, openVideosInYouTubeApp: true, showUserProfilePictures: true, showRichLinkPreviews: true, linkPreviewStyle: .compact, hideFeedDescriptions: true))
    SavedCategoryStore.saveCategories([SavedCategory(name: "SmokeBackupCategory")])
    SavedCategoryStore.assign(fullname: "t3_backuptest", category: "SmokeBackupCategory")

    let capturedBundle = BackupBundle.captureCurrent()
    let bundleData = try! capturedBundle.encoded()
    let decodedBundle = try! BackupBundle.decode(from: bundleData)
    check("BackupBundle round-trips GeneralSettings through encode/decode", decodedBundle.generalSettings == capturedBundle.generalSettings)
    check("BackupBundle round-trips TagFilterSettings through encode/decode", decodedBundle.tagFilterSettings == capturedBundle.tagFilterSettings)
    check("BackupBundle round-trips ContentFilters through encode/decode", decodedBundle.contentFilters == capturedBundle.contentFilters)
    check("BackupBundle round-trips SavedCategories through encode/decode", decodedBundle.savedCategories == capturedBundle.savedCategories)
    check("BackupBundle round-trips saved category assignments through encode/decode", decodedBundle.savedCategoryAssignments == capturedBundle.savedCategoryAssignments)
    check("BackupBundle stamps the current format version", capturedBundle.version == BackupBundle.currentVersion)

    // Now mutate state, restore the captured bundle, and confirm it wins.
    GeneralSettingsStore.save(.default)
    TagFilterStore.save(.default)
    ContentFilterStore.save([])
    decodedBundle.restore()
    check("BackupBundle.restore() writes GeneralSettings back", GeneralSettingsStore.load() == capturedBundle.generalSettings)
    check("BackupBundle.restore() writes TagFilterSettings back", TagFilterStore.load() == capturedBundle.tagFilterSettings)
    check("BackupBundle.restore() writes ContentFilters back", ContentFilterStore.load() == capturedBundle.contentFilters)
    check("BackupBundle.restore() writes saved category assignments back", SavedCategoryStore.category(for: "t3_backuptest") == "SmokeBackupCategory")

    // Clean up smoke-test state so repeated runs stay idempotent.
    GeneralSettingsStore.save(.default)
    TagFilterStore.save(.default)
    ContentFilterStore.save([])
    SavedCategoryStore.clearCategory(for: "t3_backuptest")
    SavedCategoryStore.saveCategories(SavedCategoryStore.loadCategories().filter { $0.name != "SmokeBackupCategory" })
}

// --- Rich Link Previews / OpenGraph parsing (Apollo-Reborn feature) ---
@MainActor func checkRichLinkPreviewsOpenGraphParsingApollo() async throws {
    check("default general settings disable rich link previews (extra network cost, off by default)", !GeneralSettings.default.showRichLinkPreviews)
    check("default link preview style is full", GeneralSettings.default.linkPreviewStyle == .full)
    let ogHTML = """
    <html><head>
    <meta property="og:title" content="Example Title">
    <meta property="og:description" content="An example description">
    <meta property="og:image" content="https://example.com/image.png">
    <meta property="og:site_name" content="Example Site">
    </head></html>
    """
    let ogMeta = OpenGraphParser.parse(html: ogHTML)
    check("OpenGraphParser extracts og:title", ogMeta.title == "Example Title")
    check("OpenGraphParser extracts og:description", ogMeta.description == "An example description")
    check("OpenGraphParser extracts og:image", ogMeta.imageURLString == "https://example.com/image.png")
    check("OpenGraphParser extracts og:site_name", ogMeta.siteName == "Example Site")

    let reorderedHTML = """
    <meta content="Reordered Title" property="og:title">
    """
    check("OpenGraphParser handles content-before-property attribute order", OpenGraphParser.parse(html: reorderedHTML).title == "Reordered Title")

    let twitterFallbackHTML = """
    <meta name="twitter:title" content="Twitter Card Title">
    <meta name="twitter:description" content="Twitter Card Description">
    """
    let twitterMeta = OpenGraphParser.parse(html: twitterFallbackHTML)
    check("OpenGraphParser falls back to twitter:title when og:title is absent", twitterMeta.title == "Twitter Card Title")
    check("OpenGraphParser falls back to twitter:description when og:description is absent", twitterMeta.description == "Twitter Card Description")

    let entityHTML = """
    <meta property="og:title" content="Fish &amp; Chips &quot;Special&quot;">
    """
    check("OpenGraphParser decodes HTML entities in extracted values", OpenGraphParser.parse(html: entityHTML).title == "Fish & Chips \"Special\"")

    let wikiArticle = WikipediaClient.article(from: URL(string: "https://en.m.wikipedia.org/wiki/Bernard_Montgomery")!)
    check("WikipediaClient reads the language and title of a mobile article link",
          wikiArticle?.language == "en" && wikiArticle?.title == "Bernard_Montgomery")
    check("WikipediaClient ignores links that aren't articles",
          WikipediaClient.article(from: URL(string: "https://en.wikipedia.org/w/index.php?title=X")!) == nil
            && WikipediaClient.article(from: URL(string: "https://example.com/wiki/X")!) == nil)
    check("WikipediaClient asks the summary endpoint, escaping slashes in the title",
          WikipediaClient.summaryURL(for: URL(string: "https://de.wikipedia.org/wiki/AC/DC")!)?.absoluteString
            == "https://de.wikipedia.org/api/rest_v1/page/summary/AC%2FDC")
    let wikiSummary = WikipediaClient.parse(Data("""
    {"title":"Bernard Montgomery","displaytitle":"<span>Bernard Montgomery</span>","extract":"Field Marshal Bernard Law Montgomery was a senior British Army officer.","thumbnail":{"source":"https://upload.wikimedia.org/m.jpg","width":320,"height":400}}
    """.utf8))
    check("WikipediaClient parses the plain title, extract and thumbnail",
          wikiSummary == WikipediaSummary(title: "Bernard Montgomery",
                                          extract: "Field Marshal Bernard Law Montgomery was a senior British Army officer.",
                                          thumbnailURL: URL(string: "https://upload.wikimedia.org/m.jpg")))

    check("OpenGraphParser.parse returns an empty result for HTML with no meta tags", OpenGraphParser.parse(html: "<html><body>No metadata here</body></html>").isEmpty)

    let charsetHTML = "<html><head><meta charset=\"EUC-KR\"></head></html>"
    check("OpenGraphClient.metaCharset extracts a declared charset", OpenGraphClient.metaCharset(fromHTML: charsetHTML) == "EUC-KR")
    check("OpenGraphClient.metaCharset returns nil when no charset is declared", OpenGraphClient.metaCharset(fromHTML: "<html><head></head></html>") == nil)
    check("OpenGraphClient.encoding recognizes utf-8", OpenGraphClient.encoding(fromIANACharset: "UTF-8") == .utf8)
    check("OpenGraphClient.encoding recognizes shift_jis", OpenGraphClient.encoding(fromIANACharset: "Shift_JIS") == .shiftJIS)
    let utf8Data = "Héllo".data(using: .utf8)!
    check("OpenGraphClient.decodeHTML decodes UTF-8 correctly given a matching header", OpenGraphClient.decodeHTML(data: utf8Data, headerEncoding: "utf-8") == "Héllo")
    check("OpenGraphClient.decodeHTML falls back to UTF-8 when no encoding is declared", OpenGraphClient.decodeHTML(data: utf8Data, headerEncoding: nil) == "Héllo")
}

// --- Inline Media Previews (Apollo-Reborn feature) ---
@MainActor func checkInlineMediaPreviewsApolloRebornFeature() async throws {
    check("inline media previews default ON, as Reborn registers (EnableInlineImages: YES)", InlineMediaSettings.default.enabled)
    check("default inline media size is large (100%)", InlineMediaSettings.default.size == .large)
    check("InlineMediaSize fractions map correctly", InlineMediaSize.small.fraction == 0.5 && InlineMediaSize.medium.fraction == 0.75 && InlineMediaSize.large.fraction == 1.0)
    // Hosts must be on Apollo's inline-media allowlist.
    let inlineBody = "Check out this image https://i.redd.it/photo.jpg and this gif https://i.imgur.com/funny.gif plus a video https://i.redd.it/clip.mp4"
    let inlineKinds = InlineMediaDetector.detect(in: inlineBody)
    check("InlineMediaDetector finds all 3 embedded media URLs in order", inlineKinds.count == 3)
    if inlineKinds.count == 3 {
        check("InlineMediaDetector classifies a .jpg URL as an image", inlineKinds[0] == .image(URL(string: "https://i.redd.it/photo.jpg")!))
        check("InlineMediaDetector classifies a .gif URL as a gif", inlineKinds[1] == .gif(URL(string: "https://i.imgur.com/funny.gif")!))
        check("InlineMediaDetector classifies a .mp4 URL as a video", inlineKinds[2] == .video(URL(string: "https://i.redd.it/clip.mp4")!))
    }
    let inlineYouTubeBody = "Watch this: https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    // YouTube links in bodies get a link card, not an inline player (neither
    // Apollo nor Reborn embeds them).
    check("InlineMediaDetector leaves an embedded YouTube link to its link card",
          InlineMediaDetector.detect(in: inlineYouTubeBody).isEmpty
            && LinkCardDetector.links(in: inlineYouTubeBody).map(\.absoluteString) == ["https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
    check("InlineMediaDetector finds nothing in plain text with no URLs", InlineMediaDetector.detect(in: "Just some regular comment text.").isEmpty)
    // Reborn's multi-link-comments rule collapses to a compact card only in
    // the Comments area at 2+ links; a plain link in a post body/selftext
    // is not treated as inline media.
    check("a non-media link in a body is not inline media",
          InlineMediaDetector.detect(in: "See https://www.nhc.noaa.gov/article for more").isEmpty)
    let encodedInline = try! JSONEncoder().encode(InlineMediaSettings.default)
    check("InlineMediaSettings round-trips through Codable", try! JSONDecoder().decode(InlineMediaSettings.self, from: encodedInline) == InlineMediaSettings.default)
}

// --- Custom API settings (Apollo-Reborn feature) ---
@MainActor func checkCustomAPISettingsApolloRebornFeature() async throws {
    check("default custom API settings use build-time defaults (nil overrides)", CustomAPISettings.default.redditClientID == nil && CustomAPISettings.default.redditRedirectURI == nil && CustomAPISettings.default.userAgent == nil)
    CustomAPISettingsStore.save(CustomAPISettings(redditClientID: "smoketest_client_id", redditRedirectURI: "smoketest://oauth", userAgent: "smoketest-agent/1.0", imgurClientID: "smoketest_imgur_id"))
    check("CustomAPISettingsStore.save applies the Imgur client ID immediately", ImgurClient.clientID == "smoketest_imgur_id")
    check("CustomAPISettingsStore.save applies the client ID to RedditOAuthConfig immediately", RedditOAuthConfig.clientID == "smoketest_client_id")
    check("CustomAPISettingsStore.save applies the redirect URI to RedditOAuthConfig immediately", RedditOAuthConfig.redirectURI == "smoketest://oauth")
    check("CustomAPISettingsStore.save applies the User-Agent override immediately", RedditAPIClient.userAgentOverride == "smoketest-agent/1.0")
    check("CustomAPISettingsStore.load reflects the saved settings", CustomAPISettingsStore.load().redditClientID == "smoketest_client_id")
    CustomAPISettingsStore.save(.default)
    check("CustomAPISettingsStore.save(.default) resets RedditOAuthConfig.clientID to the build-time default", RedditOAuthConfig.clientID == RedditOAuthConfig.defaultClientID)
    check("CustomAPISettingsStore.save(.default) resets RedditOAuthConfig.redirectURI to the build-time default", RedditOAuthConfig.redirectURI == RedditOAuthConfig.defaultRedirectURI)
    check("CustomAPISettingsStore.save(.default) clears the User-Agent override", RedditAPIClient.userAgentOverride == nil)
    check("CustomAPISettingsStore.save(.default) clears the Imgur client ID", ImgurClient.clientID == nil)
}

// --- Native Reddit media upload (Apollo-Reborn feature) ---
@MainActor func checkNativeRedditMediaUploadApolloReborn() async throws {
    let leaseJSON = """
    {
        "args": {
            "action": "//reddit-uploaded-media.s3-accelerate.amazonaws.com",
            "fields": [
                {"name": "acl", "value": "private"},
                {"name": "key", "value": "abc123/upload.jpg"},
                {"name": "policy", "value": "somepolicy"},
                {"name": "x-amz-signature", "value": "somesig"}
            ]
        },
        "asset": {
            "asset_id": "abc123",
            "websocket_url": "wss://ws-04c1c9d9.reddit.com/abc123"
        }
    }
    """.data(using: .utf8)!
    let lease = try! RedditMediaUploadClient.parseLeaseResponse(leaseJSON)
    check("RedditMediaUploadClient parses a protocol-relative action URL into https://", lease.uploadURL == "https://reddit-uploaded-media.s3-accelerate.amazonaws.com")
    check("RedditMediaUploadClient parses all lease fields in order", lease.fields.map(\.name) == ["acl", "key", "policy", "x-amz-signature"])
    check("RedditMediaUploadClient builds the final asset URL from the upload URL + key field", lease.assetURL == "https://reddit-uploaded-media.s3-accelerate.amazonaws.com/abc123/upload.jpg")
    check("RedditMediaUploadClient extracts the websocket URL for video/gif processing", lease.websocketURL == "wss://ws-04c1c9d9.reddit.com/abc123")
    // asset_id (the gallery-post media_id, distinct from the S3 key/asset URL).
    check("RedditMediaUploadClient extracts the real asset_id for gallery media_id use", lease.assetID == "abc123")
    var leaseParseThrew = false
    do { _ = try RedditMediaUploadClient.parseLeaseResponse("not json".data(using: .utf8)!) } catch { leaseParseThrew = true }
    check("RedditMediaUploadClient throws on a malformed lease response", leaseParseThrew)
}

// --- Imgur integration (Apollo-Reborn feature) ---
@MainActor func checkImgurIntegrationApolloRebornFeature() async throws {
    check("ImgurClient.extractAlbumID extracts an album ID from an imgur.com/a/ URL", ImgurClient.extractAlbumID(from: URL(string: "https://imgur.com/a/AbCdEfG")!) == "AbCdEfG")
    check("ImgurClient.extractAlbumID extracts a gallery ID from an imgur.com/gallery/ URL", ImgurClient.extractAlbumID(from: URL(string: "https://imgur.com/gallery/xyz123")!) == "xyz123")
    check("ImgurClient.extractAlbumID returns nil for a direct i.imgur.com image link", ImgurClient.extractAlbumID(from: URL(string: "https://i.imgur.com/abc123.jpg")!) == nil)
    check("ImgurClient.extractAlbumID returns nil for a non-Imgur URL", ImgurClient.extractAlbumID(from: URL(string: "https://example.com/a/abc123")!) == nil)
}

// --- RES filteReddit import (base-Apollo feature) ---
@MainActor func checkRESFilteRedditImportRealBaseApollo() async throws {
    let resExportJSON = """
    {
      "subreddits": { "value": [{ "subreddit": "politics" }, { "subreddit": "news" }] },
      "keywords": { "value": [{ "keyword": "spoiler", "applyTo": "everywhere", "subreddits": [], "unlessKeyword": "" }] },
      "domains": { "value": [{ "keyword": "clickbait.com", "applyTo": "everywhere", "subreddits": [] }] }
    }
    """
    switch RESFilterImporter.parse(resExportJSON) {
    case .success(let imported):
        check("RESFilterImporter parses subreddits from a real RES export shape", imported.contains { $0.kind == .subreddit && $0.value == "politics" })
        check("RESFilterImporter parses keywords from a real RES export shape", imported.contains { $0.kind == .keyword && $0.value == "spoiler" })
        check("RESFilterImporter parses domains from a real RES export shape", imported.contains { $0.kind == .domain && $0.value == "clickbait.com" })
    case .failure:
        check("RESFilterImporter parses a well-formed RES export", false)
    }
    switch RESFilterImporter.parse("") {
    case .success:
        check("RESFilterImporter fails on empty clipboard text", false)
    case .failure(let error):
        check("RESFilterImporter reports emptyClipboard for blank input", error == .emptyClipboard)
    }
    switch RESFilterImporter.parse("not json at all") {
    case .success:
        check("RESFilterImporter fails on garbage input", false)
    case .failure(let error):
        check("RESFilterImporter reports invalidOrEmpty for unparseable input", error == .invalidOrEmpty)
    }
}

// --- Share old.reddit Links (base-Apollo feature) ---
@MainActor func checkShareOldRedditLinksRealBase() async throws {
    check("ShareLinkBuilder defaults to reddit.com", ShareLinkBuilder.url(forPermalinkPath: "/r/test/comments/abc", useOldReddit: false).absoluteString == "https://reddit.com/r/test/comments/abc")
    check("ShareLinkBuilder substitutes old.reddit.com when enabled", ShareLinkBuilder.url(forPermalinkPath: "/r/test/comments/abc", useOldReddit: true).absoluteString == "https://old.reddit.com/r/test/comments/abc")
}

// --- Share Includes Title (sharePostIncludesTitle) ---
@MainActor func checkShareIncludesTitleDeadToggleFix() async throws {
    check("ShareLinkBuilder.shareText includes the title when enabled", ShareLinkBuilder.shareText(title: "My Post", url: URL(string: "https://reddit.com/r/test/comments/abc")!, includeTitle: true) == "My Post https://reddit.com/r/test/comments/abc")
    check("ShareLinkBuilder.shareText omits the title when disabled", ShareLinkBuilder.shareText(title: "My Post", url: URL(string: "https://reddit.com/r/test/comments/abc")!, includeTitle: false) == "https://reddit.com/r/test/comments/abc")

    check("GeneralSettings.default has shareOldRedditLinks off", GeneralSettings.default.shareOldRedditLinks == false)
    check("GeneralSettings.default post display style is Large, stock Apollo's (UseCompactThumbnails: NO)", GeneralSettings.default.postDisplayStyle == .large)
    check("PostDisplayStyle.large has the real 'Large Thumbnails' label", PostDisplayStyle.large.displayName == "Large Thumbnails")
    var displayStyleSettings = GeneralSettings.default
    displayStyleSettings.postDisplayStyle = .large
    GeneralSettingsStore.save(displayStyleSettings)
    check("GeneralSettingsStore round-trips postDisplayStyle", GeneralSettingsStore.load().postDisplayStyle == .large)
    GeneralSettingsStore.save(.default)

    check("Int.apolloAbbreviated leaves small numbers unabbreviated", 998.apolloAbbreviated == "998")
    check("Int.apolloAbbreviated abbreviates thousands with one decimal", 62800.apolloAbbreviated == "62.8K")
    check("Int.apolloAbbreviated abbreviates millions with one decimal", 2_400_000.apolloAbbreviated == "2.4M")
    check("Int.apolloAbbreviated handles exactly 1000", 1000.apolloAbbreviated == "1.0K")

    check("Date.apolloRelativeTime shows 'now' for just-elapsed times", Date().addingTimeInterval(-5).apolloRelativeTime == "now")
    check("Date.apolloRelativeTime shows compact minutes", Date().addingTimeInterval(-90).apolloRelativeTime == "1m")
    check("Date.apolloRelativeTime shows compact hours, not a multi-unit string", Date().addingTimeInterval(-3600 * 5).apolloRelativeTime == "5h")
    check("Date.apolloRelativeTime shows compact days", Date().addingTimeInterval(-86400 * 3).apolloRelativeTime == "3d")

    let imgurImageJSON = """
    {"data": {"id": "abc123", "link": "https://i.imgur.com/abc123.jpg", "deletehash": "somehash"}, "success": true}
    """.data(using: .utf8)!
    let imgurImage = try! ImgurClient.parseImageResponse(imgurImageJSON)
    check("ImgurClient.parseImageResponse extracts id/link/deletehash", imgurImage.id == "abc123" && imgurImage.link == "https://i.imgur.com/abc123.jpg" && imgurImage.deleteHash == "somehash")
    let imgurAlbumJSON = """
    {"data": {"id": "album1", "title": "My Album", "images": [
        {"id": "img1", "link": "https://i.imgur.com/img1.jpg"},
        {"id": "img2", "link": "https://i.imgur.com/img2.jpg"}
    ]}}
    """.data(using: .utf8)!
    let imgurAlbum = try! ImgurClient.parseAlbumResponse(imgurAlbumJSON)
    check("ImgurClient.parseAlbumResponse extracts id/title", imgurAlbum.id == "album1" && imgurAlbum.title == "My Album")
    check("ImgurClient.parseAlbumResponse extracts all images in order", imgurAlbum.images.map(\.id) == ["img1", "img2"])
    var imgurUploadThrewNotConfigured = false
    do { _ = try await ImgurClient.uploadImage(data: Data(), clientID: nil) } catch ImgurClient.ClientError.notConfigured { imgurUploadThrewNotConfigured = true } catch {}
    check("ImgurClient.uploadImage throws .notConfigured with no client ID", imgurUploadThrewNotConfigured)
}

// --- Vote breakdown calculator (Apollo-Reborn feature) ---
@MainActor func checkVoteBreakdownCalculatorApolloRebornFeature() async throws {
    let breakdown80 = VoteBreakdownCalculator.breakdown(score: 60, upvoteRatio: 0.8)
    check("VoteBreakdownCalculator computes upvotes/downvotes matching score and ratio", breakdown80 != nil && breakdown80!.upvotes - breakdown80!.downvotes == 60)
    if let breakdown80 {
        let computedRatio = Double(breakdown80.upvotes) / Double(breakdown80.upvotes + breakdown80.downvotes)
        check("VoteBreakdownCalculator's computed ratio matches the input ratio", abs(computedRatio - 0.8) < 0.01)
    }
    check("VoteBreakdownCalculator returns nil for a 50% ratio (unsolvable)", VoteBreakdownCalculator.breakdown(score: 10, upvoteRatio: 0.5) == nil)
    check("VoteBreakdownCalculator returns nil when upvoteRatio is nil", VoteBreakdownCalculator.breakdown(score: 10, upvoteRatio: nil) == nil)
    check("VoteBreakdownCalculator returns nil for an out-of-range ratio", VoteBreakdownCalculator.breakdown(score: 10, upvoteRatio: 1.5) == nil)
    // Matches Reborn's Comment Insights cutoff: "Totals are not estimated below
    // 60% because rounded ratios become unreliable near 50%".
    check("VoteBreakdownCalculator returns nil below the 60% reliability cutoff", VoteBreakdownCalculator.breakdown(score: 10, upvoteRatio: 0.55) == nil)
    check("VoteBreakdownCalculator estimates at exactly the 60% cutoff", VoteBreakdownCalculator.breakdown(score: 10, upvoteRatio: 0.6) != nil)
    // The cutoff is not symmetric around 50%: a mostly-downvoted
    // post/comment never gets an estimate, only ratios >= 60% do.
    check("VoteBreakdownCalculator does NOT estimate for a low ratio (real source confirms no symmetric cutoff)", VoteBreakdownCalculator.breakdown(score: 10, upvoteRatio: 0.4) == nil)
    // Also requires score > 0; score <= 0 is rejected with its own
    // distinct user-facing reason string.
    check("VoteBreakdownCalculator requires a strictly positive score, matching real source", VoteBreakdownCalculator.breakdown(score: 0, upvoteRatio: 0.8) == nil)
    check("VoteBreakdownCalculator rejects a negative score even with a high ratio", VoteBreakdownCalculator.breakdown(score: -10, upvoteRatio: 0.9) == nil)
}

// --- Hide Post Scores / Hide Comment Scores (Phoebus-only, inspired by Continuum) ---
@MainActor func checkHideVoteCounts() async throws {
    let shown = VoteCountSettings.default
    check("scores are shown by default", !shown.hidePostScores && !shown.hideCommentScores)
    check("a shown post score is abbreviated as rows draw it", shown.postScoreText(10_900) == "10.9K")
    check("a shown comment score is abbreviated", shown.commentScoreText(1_234, scoreHidden: false) == 1_234.apolloAbbreviated)
    check("Reddit's own hidden comment score stays an em dash", shown.commentScoreText(5, scoreHidden: true) == "\u{2014}")
    check("the vote estimate shows while post scores do", shown.showsPostVoteEstimate)

    let posts = VoteCountSettings(hidePostScores: true)
    check("Hide Post Scores drops the post number", posts.postScoreText(10_900) == nil)
    check("Hide Post Scores leaves comment scores", posts.commentScoreText(3, scoreHidden: false) == "3")
    check("Hide Post Scores also drops the upvote/downvote estimate", !posts.showsPostVoteEstimate)

    let comments = VoteCountSettings(hideCommentScores: true)
    check("Hide Comment Scores drops the comment number", comments.commentScoreText(3, scoreHidden: false) == nil)
    check("Hide Comment Scores drops the em dash too", comments.commentScoreText(3, scoreHidden: true) == nil)
    check("Hide Comment Scores leaves post scores", comments.postScoreText(42) == "42" && comments.showsPostVoteEstimate)

    let decodedEmpty = try JSONDecoder().decode(VoteCountSettings.self, from: Data("{}".utf8))
    check("an empty blob decodes to the defaults", decodedEmpty == .default)
    let both = VoteCountSettings(hidePostScores: true, hideCommentScores: true)
    let roundTripped = try JSONDecoder().decode(VoteCountSettings.self, from: JSONEncoder().encode(both))
    check("vote count settings survive a JSON round trip", roundTripped == both)

    let suite = "VoteCountSettingsBackupTest"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    VoteCountStore.storage.save(both, to: defaults)
    check("vote count settings are in settings backups",
          SettingsDomainSnapshot.isBackedUp("com.pendo324.Phoebus.voteCountSettings"))
    let snapshot = try JSONDecoder().decode([String: JSONValue].self,
                                            from: JSONEncoder().encode(SettingsDomainSnapshot.capture(from: defaults)))
    let restoreSuite = "VoteCountSettingsRestoreTest"
    let restored = UserDefaults(suiteName: restoreSuite)!
    restored.removePersistentDomain(forName: restoreSuite)
    SettingsDomainSnapshot.restore(snapshot, into: restored)
    check("vote count settings round-trip through a backup", VoteCountStore.storage.load(from: restored) == both)

    let now = Date(timeIntervalSince1970: 1_000_000)
    let spoken = AccessibilitySummary.post(title: "t", subreddit: "s", author: "a", score: 77, comments: 2,
                                           created: now, scoreHidden: true, now: now)
    check("a hidden post score is not spoken", !spoken.contains("point") && spoken.contains("2 comments"))
}

// --- Random NSFW subreddit + Hide Feed Descriptions (Apollo-Reborn features) ---
@MainActor func checkRandomNSFWSubredditHideFeedDescriptions() async throws {
    check("default general settings show feed descriptions (hideFeedDescriptions is false)", !GeneralSettings.default.hideFeedDescriptions)
    let encodedGeneral2 = try! JSONEncoder().encode(GeneralSettings.default)
    check("GeneralSettings still round-trips through Codable after adding hideFeedDescriptions", try! JSONDecoder().decode(GeneralSettings.self, from: encodedGeneral2) == GeneralSettings.default)
}

// --- Theme (Apollo-Reborn "unlocked Ultra" feature) ---
@MainActor func checkThemeUnlockedFeature() async throws {
    check("ThemeStore defaults to the real Default theme", ThemeStore.load() == Theme.defaultLight)
    check("Theme.allThemes has all 18 real named accent themes (36 entries: light/dark pairs)", Theme.allThemes.count == 36)
    check("Theme.allThemes includes every real Apollo theme name", Set(Theme.allThemes.map(\.name)) == Set([
        "Default", "Nefertiti", "Fiery Stare", "Spooky Pumpkin", "Solarized", "Outrun", "Sunset",
        "Sepia", "Monochromatic", "Navy", "Skies on Skies", "Majestic Purple", "Magentasplosion",
        "Sniffing Walnut", "Fisher King", "Chumbus", "Dracula", "Mint",
    ]))
    // Accent hex values match Apollo-Reborn's stock theme table.
    check("Default theme's real accent color matches Apollo's", Theme.defaultLight.accentColorHex == "007AFF")
    check("Solarized's accent matches Reborn's", Theme.solarizedLight.accentColorHex == "268BD2" && Theme.solarizedDark.accentColorHex == "268BD2")
    check("Outrun's light/dark accents match Reborn's", Theme.outrunLight.accentColorHex == "C400A6" && Theme.outrunDark.accentColorHex == "FF00D8")
    check("Dracula's accent matches Reborn's", Theme.draculaLight.accentColorHex == "9760FF")
    check("Monochromatic's light/dark accents match Reborn's", Theme.monochromaticLight.accentColorHex == "000000" && Theme.monochromaticDark.accentColorHex == "FFFFFF")
    let solarizedDarkTokens = StockThemeSurfaces.compiled(for: Theme.solarizedDark)
    check("tinted built-ins paint Reborn's own card, page and separator",
          solarizedDarkTokens?.hex(.secondaryBackground, mode: .dark) == "002B36"
              && solarizedDarkTokens?.hex(.background, mode: .dark) == "003745"
              && solarizedDarkTokens?.hex(.separator, mode: .light) == "E0DCCD"
              && solarizedDarkTokens?.hex(.accent, mode: .dark) == "268BD2")
    check("only the five tinted built-ins get their own surfaces",
          Theme.allThemes.filter { StockThemeSurfaces.compiled(for: $0) != nil }.map(\.name).reduce(into: Set<String>()) { $0.insert($1) }
              == ["Solarized", "Outrun", "Sunset", "Sepia", "Dracula"])
    check("Every theme has a non-empty comment-depth palette", Theme.allThemes.allSatisfy { !$0.commentDepthColorHexes.isEmpty })
    check("Every built-in theme name has both a light and dark variant", Set(Theme.allThemes.map(\.name)).allSatisfy { name in
        Theme.allThemes.filter { $0.name == name }.count == 2
    })
    check("defaultDark is marked dark", Theme.defaultDark.isDark)
    check("defaultLight is marked light", !Theme.defaultLight.isDark)
    ThemeStore.save(.navyLight)
    check("ThemeStore persists a selection", ThemeStore.load() == Theme.navyLight)
    ThemeStore.save(.defaultLight)
    check("ThemeStore round-trips back to the default theme", ThemeStore.load() == Theme.defaultLight)
    let encodedTheme = try! JSONEncoder().encode(Theme.chumbusLight)
    check("Theme round-trips through Codable", try! JSONDecoder().decode(Theme.self, from: encodedTheme) == Theme.chumbusLight)
}

// --- Other Discussions: `/duplicates/<id>` parsing, the row's count from
// the comments response, and its setting in backups ---
@MainActor func checkOtherDiscussions() async throws {
    // Reddit's `[postListing, duplicatesListing]` shape, filled with
    // archived copies of real posts of one link (authors anonymised).
    let duplicates = fixture("reddit-duplicates.json")
    check("the duplicates fixture is present", !duplicates.isEmpty)
    let page = try? OtherDiscussions.page(from: duplicates, excluding: "1wko4v6")
    check("a duplicates response yields the second listing's posts",
          page?.posts.map(\.id) == ["1wmp1pl", "1wmp0wj", "1wm5500", "1wvtfnf"])
    check("...with each post's subreddit and score",
          page?.posts.first?.subreddit == "Anthropic" && page?.posts.first?.score == 178)
    check("...and the cursor for the next page", page?.after == "t3_1wvtfnf")
    check("a crosspost among them keeps its original",
          page?.posts.last?.crosspostParent?.id == "1wko4v6")
    let single = try OtherDiscussions.page(from: Data(#"[{"kind":"Listing","data":{"children":[]}}]"#.utf8), excluding: "x")
    check("a single listing is not a duplicates response", single == nil)

    let selfFirst = Data(#"""
    [{"kind":"Listing","data":{"children":[]}},
     {"kind":"Listing","data":{"children":[
      {"kind":"t3","data":{"id":"p","name":"t3_p","title":"t","author":"a","subreddit":"s","permalink":"/p","score":1,"num_comments":0,"created_utc":0,"is_self":false,"over_18":false,"spoiler":false,"stickied":false,"saved":false}},
      {"kind":"t3","data":{"id":"q","name":"t3_q","title":"t","author":"a","subreddit":"s","permalink":"/q","score":1,"num_comments":0,"created_utc":0,"is_self":false,"over_18":false,"spoiler":false,"stickied":false,"saved":false}},
      {"kind":"t3","data":{"id":"q","name":"t3_q","title":"t","author":"a","subreddit":"s","permalink":"/q","score":1,"num_comments":0,"created_utc":0,"is_self":false,"over_18":false,"spoiler":false,"stickied":false,"saved":false}}]}}]
    """#.utf8)
    check("the post itself and repeats are dropped",
          (try? OtherDiscussions.page(from: selfFirst, excluding: "p"))?.posts.map(\.id) == ["q"])
    if let posts = page?.posts {
        check("a next page skips posts already shown",
              OtherDiscussions.appending(Array(posts.suffix(2)), to: Array(posts.prefix(3))).map(\.id)
                == ["1wmp1pl", "1wmp0wj", "1wm5500", "1wvtfnf"])
    }

    let original = page?.posts.first
    if let link = original {
        check("a link post has other discussions", OtherDiscussions.isAvailable(for: link))
        check("the row shows when Reddit reports some",
              OtherDiscussions.showsCountRow(count: 3, post: link, settings: .default))
        check("...not with none, or with the setting off",
              !OtherDiscussions.showsCountRow(count: 0, post: link, settings: .default)
                && !OtherDiscussions.showsCountRow(count: nil, post: link, settings: .default)
                && !OtherDiscussions.showsCountRow(count: 3, post: link, settings: OtherDiscussionsSettings(showCountRow: false)))
    }
    let selfPost = try JSONDecoder.reddit.decode(RedditPost.self, from: Data(#"""
    {"id":"s1","name":"t3_s1","title":"t","author":"a","subreddit":"s","permalink":"/s1","score":1,"num_comments":0,"created_utc":0,"is_self":true,"over_18":false,"spoiler":false,"stickied":false,"saved":false}
    """#.utf8))
    check("a text post has no other discussions", !OtherDiscussions.isAvailable(for: selfPost))
    if let crosspost = page?.posts.last {
        check("a crosspost has other discussions", OtherDiscussions.isAvailable(for: crosspost))
    }
    check("the row's label agrees with its count",
          OtherDiscussions.countLabel(1) == "1 Other Discussion" && OtherDiscussions.countLabel(12) == "12 Other Discussions")

    let comments = Data(#"""
    [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{"num_comments":7,"num_duplicates":29}}]}},
     {"kind":"Listing","data":{"children":[]}}]
    """#.utf8)
    check("a comments response carries the post's duplicate count",
          (try? CommentTreeBuilder.parseCommentsResponse(comments, postID: "p"))?.postDuplicateCount == 29)

    check("the row's setting defaults on", OtherDiscussionsSettings.default.showCountRow)
    check("an empty settings blob decodes to the default",
          (try? JSONDecoder().decode(OtherDiscussionsSettings.self, from: Data("{}".utf8))) == .default)
    OtherDiscussionsSettingsStore.storage.update { $0.showCountRow = false }
    let snapshot = SettingsDomainSnapshot.capture()
    OtherDiscussionsSettingsStore.save(.default)
    SettingsDomainSnapshot.restore(snapshot)
    check("the row's setting survives a settings backup", OtherDiscussionsSettingsStore.load().showCountRow == false)
    OtherDiscussionsSettingsStore.save(.default)
}

// --- Remember Thread Position (threadPositionSettings / threadPositions) ---
@MainActor func checkThreadPositionMemory() async throws {
    // a > (b > c, d), e
    let c = CommentTreeNode(comment: makeComment(id: "c"), depth: 2)
    let b = CommentTreeNode(comment: makeComment(id: "b"), depth: 1, children: [c])
    let d = CommentTreeNode(comment: makeComment(id: "d"), depth: 1)
    let a = CommentTreeNode(comment: makeComment(id: "a"), depth: 0, children: [b, d])
    let e = CommentTreeNode(comment: makeComment(id: "e"), depth: 0)
    let roots = [a, e]

    check("topmost visible row follows reading order, not set order",
          TopVisibleRowPolicy.topmost(order: ["a", "b", "c", "d"], onScreen: ["d", "c"]) == "c")
    check("no rows on screen means no top row",
          TopVisibleRowPolicy.topmost(order: ["a"], onScreen: []) == nil)

    // Under a 100pt navigation bar, an 800pt-tall screen.
    let viewport = ListViewport(top: 100, bottom: 800)
    check("a row kept alive above the viewport is not visible",
          !TopVisibleRowPolicy.isVisible(minY: -300, maxY: 40, in: viewport))
    check("a row under the navigation bar is not visible",
          !TopVisibleRowPolicy.isVisible(minY: 20, maxY: 100, in: viewport))
    check("a sliver below the navigation bar does not count",
          !TopVisibleRowPolicy.isVisible(minY: 20, maxY: 105, in: viewport))
    check("a row straddling the top edge is visible",
          TopVisibleRowPolicy.isVisible(minY: 60, maxY: 180, in: viewport))
    check("a 65pt row with 13pt showing below the bar does not count as the top row",
          !TopVisibleRowPolicy.isVisible(minY: 48, maxY: 113, in: viewport))
    check("a short 30pt row counts once half of it shows",
          TopVisibleRowPolicy.isVisible(minY: 85, maxY: 115, in: viewport))
    check("a row realized below the viewport is not visible",
          !TopVisibleRowPolicy.isVisible(minY: 820, maxY: 900, in: viewport))
    check("nothing is visible before the list is measured",
          !TopVisibleRowPolicy.isVisible(minY: 0, maxY: 50, in: ListViewport(top: 0, bottom: 0)))
    check("restore steps down toward a target below the realized rows",
          ScrollRestorePolicy.step(targetIndex: 40, realizedIndices: [10, 11, 12]) == .down)
    check("restore steps up toward a target above the realized rows",
          ScrollRestorePolicy.step(targetIndex: 2, realizedIndices: [10, 11, 12]) == .up)
    check("restore stops stepping when the target lies among the realized rows",
          ScrollRestorePolicy.step(targetIndex: 11, realizedIndices: [10, 12]) == nil)
    check("restore stops when no tracked row is on screen",
          ScrollRestorePolicy.step(targetIndex: 5, realizedIndices: []) == nil)
    // Scrolled to offset 1900 under a 100pt bar, 900pt tall, 50pt home indicator.
    let area = ListViewport.visibleArea(contentOffsetY: 1900, boundsHeight: 900, insetTop: 100, insetBottom: 50)
    check("the visible area starts below the bar at the content offset",
          area == ListViewport(top: 2000, bottom: 2750))
    check("a cell under the bar (content 1880-1990) is not on screen",
          !TopVisibleRowPolicy.isVisible(minY: 1880, maxY: 1990, in: area))
    check("a cell straddling the bar (content 1950-2050) is on screen",
          TopVisibleRowPolicy.isVisible(minY: 1950, maxY: 2050, in: area))
    check("a cell above the offset (content 400-600) is not on screen",
          !TopVisibleRowPolicy.isVisible(minY: 400, maxY: 600, in: area))
    let aligned = ScrollRestorePolicy.offset(aligningRowTop: 5000, insetTop: 100)
    check("aligning a row puts its top exactly at the top of the visible area",
          ListViewport.visibleArea(contentOffsetY: aligned, boundsHeight: 900, insetTop: 100, insetBottom: 50).top == 5000)
    check("restore offsets stay within the content",
          ScrollRestorePolicy.clamped(5000, min: -100, max: 3000) == 3000
            && ScrollRestorePolicy.clamped(-400, min: -100, max: 3000) == -100)

    check("ancestor path is top-level first", ThreadPositionPolicy.ancestorPath(to: "c", in: roots) == ["a", "b"])
    check("a top-level comment has no ancestors", ThreadPositionPolicy.ancestorPath(to: "e", in: roots) == [])
    check("an unloaded comment has no path", ThreadPositionPolicy.ancestorPath(to: "zz", in: roots) == nil)

    let saved = ThreadPositionPolicy.position(postID: "p1", roots: roots, onScreen: ["c", "d"], atTop: false)
    check("leaving mid-thread saves the topmost comment and its ancestors",
          saved == ThreadPosition(postID: "p1", commentID: "c", ancestorIDs: ["a", "b"]))
    check("leaving at the top saves nothing (forgets the thread)",
          ThreadPositionPolicy.position(postID: "p1", roots: roots, onScreen: ["a"], atTop: true) == nil)

    let target = ThreadPosition(postID: "p1", commentID: "c", ancestorIDs: ["a", "b"])
    check("reopening lands on the saved comment when it is shown",
          ThreadPositionPolicy.restoreTarget(for: target, roots: roots) == "c")
    check("a saved comment under a collapsed parent lands on that parent (left collapsed)",
          ThreadPositionPolicy.restoreTarget(for: target, roots: [a.togglingCollapse(id: "b"), e]) == "b")
    let underMore = ThreadPosition(postID: "p1", commentID: "gone", ancestorIDs: ["a", "missing"])
    check("a saved comment not loaded (under more replies) falls back to its nearest loaded ancestor",
          ThreadPositionPolicy.restoreTarget(for: underMore, roots: roots) == "a")
    check("a thread with none of the path loaded does not scroll",
          ThreadPositionPolicy.restoreTarget(for: ThreadPosition(postID: "p1", commentID: "x", ancestorIDs: ["y"]), roots: roots) == nil)

    check("restoring is off by default", !ThreadPositionSettings.default.rememberThreadPosition)
    check("20 threads are remembered by default", ThreadPositionSettings.default.capacity == 20)
    check("restores when enabled on a plain open",
          ThreadPositionPolicy.shouldRestore(enabled: true, focusedCommentID: nil, sort: "confidence"))
    check("a linked comment wins over the saved position",
          !ThreadPositionPolicy.shouldRestore(enabled: true, focusedCommentID: "c", sort: "confidence"))
    check("live sort never restores",
          !ThreadPositionPolicy.shouldRestore(enabled: true, focusedCommentID: nil, sort: "live"))
    check("disabled never restores",
          !ThreadPositionPolicy.shouldRestore(enabled: false, focusedCommentID: nil, sort: "confidence"))

    let list = RememberedPositions<ThreadPosition>()
        .recording(ThreadPosition(postID: "p1", commentID: "c1", ancestorIDs: []), capacity: 2)
        .recording(ThreadPosition(postID: "p2", commentID: "c2", ancestorIDs: []), capacity: 2)
        .recording(ThreadPosition(postID: "p1", commentID: "c1b", ancestorIDs: []), capacity: 2)
        .recording(ThreadPosition(postID: "p3", commentID: "c3", ancestorIDs: []), capacity: 2)
    check("positions are capped, evicting the least recently saved",
          list.entries.map(\.postID) == ["p3", "p1"])
    check("re-saving a thread replaces its position and refreshes it",
          list.entry(for: "p1")?.commentID == "c1b")
    check("removing forgets one thread", list.removing(key: "p3").entries.map(\.postID) == ["p1"])

    let suite = "phoebus.smoke.threadPosition"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    ThreadPositionStore.record(target, postID: "p1", defaults: defaults)
    check("nothing is saved while the setting is off", ThreadPositionStore.load(from: defaults).entries.isEmpty)
    ThreadPositionSettingsStore.storage.save(ThreadPositionSettings(rememberThreadPosition: true, capacity: 2), to: defaults)
    ThreadPositionStore.record(target, postID: "p1", defaults: defaults)
    ThreadPositionStore.record(ThreadPosition(postID: "p2", commentID: "x", ancestorIDs: []), postID: "p2", defaults: defaults)
    ThreadPositionStore.record(ThreadPosition(postID: "p3", commentID: "y", ancestorIDs: []), postID: "p3", defaults: defaults)
    check("the stored list honours the capacity setting",
          ThreadPositionStore.load(from: defaults).entries.map(\.postID) == ["p3", "p2"])
    ThreadPositionStore.record(nil, postID: "p3", defaults: defaults)
    check("returning to the top forgets the thread", ThreadPositionStore.position(postID: "p3", defaults: defaults) == nil)
    check("a saved position reads back", ThreadPositionStore.position(postID: "p2", defaults: defaults)?.commentID == "x")

    // Settings backup round trip, through JSON as an export is.
    let snapshot = SettingsDomainSnapshot.capture(from: defaults)
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: try JSONEncoder().encode(snapshot))
    let restoreSuite = "phoebus.smoke.threadPositionRestore"
    let restored = UserDefaults(suiteName: restoreSuite)!
    restored.removePersistentDomain(forName: restoreSuite)
    SettingsDomainSnapshot.restore(decoded, into: restored)
    check("the setting and capacity survive a backup round trip",
          ThreadPositionSettingsStore.storage.load(from: restored) == ThreadPositionSettings(rememberThreadPosition: true, capacity: 2))
    check("saved thread positions survive a backup round trip",
          ThreadPositionStore.load(from: restored) == ThreadPositionStore.load(from: defaults))
}

// --- Resume Where I Left Off (resumeSettings / resumeState) ---
@MainActor func checkResumeWhereLeftOff() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let saved = ResumeSnapshot(savedAt: now.addingTimeInterval(-60), account: "Reader", tab: 0,
                               feed: .subreddit("pics"), sort: "hot", topPostID: "p3",
                               openPost: .init(id: "p9", subreddit: "pics"))
    check("resuming is off by default", !ResumeSettings.default.resumeWhereLeftOff)
    check("a recent snapshot for the same account is restored",
          ResumePolicy.snapshotToRestore(saved, enabled: true, account: "reader", now: now, openedFromLink: false) == saved)
    check("nothing is restored while the setting is off",
          ResumePolicy.snapshotToRestore(saved, enabled: false, account: "Reader", now: now, openedFromLink: false) == nil)
    check("a link, widget, notification or quick action launch wins over resuming",
          ResumePolicy.snapshotToRestore(saved, enabled: true, account: "Reader", now: now, openedFromLink: true) == nil)
    check("another account's snapshot is not restored",
          ResumePolicy.snapshotToRestore(saved, enabled: true, account: "other", now: now, openedFromLink: false) == nil)
    check("a signed-out launch restores nothing",
          ResumePolicy.snapshotToRestore(saved, enabled: true, account: nil, now: now, openedFromLink: false) == nil)
    var stale = saved
    stale.savedAt = now.addingTimeInterval(-ResumePolicy.maxAge - 1)
    check("a snapshot older than a day is not restored",
          ResumePolicy.snapshotToRestore(stale, enabled: true, account: "Reader", now: now, openedFromLink: false) == nil)
    var future = saved
    future.savedAt = now.addingTimeInterval(3600)
    check("a snapshot from the future (clock change) is not restored",
          ResumePolicy.snapshotToRestore(future, enabled: true, account: "Reader", now: now, openedFromLink: false) == nil)

    check("a missing post is looked for on the next page",
          ResumePolicy.shouldLoadMore(toFind: "p3", loadedIDs: ["p1", "p2"], pagesLoaded: 1, reachedEnd: false))
    check("no more than three pages are fetched looking for it",
          !ResumePolicy.shouldLoadMore(toFind: "p3", loadedIDs: ["p1", "p2"], pagesLoaded: 3, reachedEnd: false))
    check("paging stops at the end of the feed",
          !ResumePolicy.shouldLoadMore(toFind: "p3", loadedIDs: ["p1"], pagesLoaded: 1, reachedEnd: true))
    check("paging stops once the post is loaded",
          !ResumePolicy.shouldLoadMore(toFind: "p3", loadedIDs: ["p1", "p3"], pagesLoaded: 1, reachedEnd: false))
    check("the saved post is scrolled to in the same sort",
          ResumePolicy.scrollTarget(for: saved, feedSort: "hot", loadedIDs: ["p1", "p2", "p3"]) == "p3")
    check("a feed reopening under another sort stays at its top",
          ResumePolicy.scrollTarget(for: saved, feedSort: "new", loadedIDs: ["p1", "p2", "p3"]) == nil)
    check("a post not loaded is given up on",
          ResumePolicy.scrollTarget(for: saved, feedSort: "hot", loadedIDs: ["p1", "p2"]) == nil)
    check("a feed left at its first post needs no scroll",
          ResumePolicy.scrollTarget(for: saved, feedSort: "hot", loadedIDs: ["p3", "p4"]) == nil)
    check("Home is the empty subreddit",
          ResumePolicy.feedDestination(subreddit: "", multiredditPath: nil, multiredditName: nil) == .home)
    check("r/all, r/popular and r/mod are their pseudo-feeds",
          ResumePolicy.feedDestination(subreddit: "All", multiredditPath: nil, multiredditName: nil) == .all
          && ResumePolicy.feedDestination(subreddit: "popular", multiredditPath: nil, multiredditName: nil) == .popular
          && ResumePolicy.feedDestination(subreddit: "mod", multiredditPath: nil, multiredditName: nil) == .moderator)
    check("a multireddit is kept by path and name",
          ResumePolicy.feedDestination(subreddit: "", multiredditPath: "/user/a/m/b", multiredditName: "b")
            == .multireddit(path: "/user/a/m/b", name: "b"))
    check("a subreddit keeps its name",
          ResumePolicy.feedDestination(subreddit: "pics", multiredditPath: nil, multiredditName: nil) == .subreddit("pics"))

    let suite = "phoebus.smoke.resume"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    ResumeStore.record(saved, defaults: defaults)
    check("nothing is saved while the setting is off", ResumeStore.load(from: defaults) == nil)
    ResumeSettingsStore.storage.save(ResumeSettings(resumeWhereLeftOff: true), to: defaults)
    ResumeStore.record(saved, defaults: defaults)
    check("a saved place reads back", ResumeStore.load(from: defaults) == saved)
    var later = saved
    later.savedAt = now
    ResumeStore.record(later, defaults: defaults)
    check("an unchanged place is not rewritten by the periodic save", ResumeStore.load(from: defaults)?.savedAt == saved.savedAt)
    ResumeStore.record(later, force: true, defaults: defaults)
    check("backgrounding refreshes an unchanged place's age", ResumeStore.load(from: defaults)?.savedAt == now)

    let snapshot = SettingsDomainSnapshot.capture(from: defaults)
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: try JSONEncoder().encode(snapshot))
    let restoreSuite = "phoebus.smoke.resumeRestore"
    let restored = UserDefaults(suiteName: restoreSuite)!
    restored.removePersistentDomain(forName: restoreSuite)
    SettingsDomainSnapshot.restore(decoded, into: restored)
    check("the setting survives a backup round trip", ResumeSettingsStore.storage.load(from: restored).resumeWhereLeftOff)
    check("the saved place is left out of backups", ResumeStore.load(from: restored) == nil)
    ResumeStore.clear(defaults: defaults)
    check("clearing forgets the saved place", ResumeStore.load(from: defaults) == nil)
}
