import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - LinkPreviewSettings
// Registered defaults are Full for both; there is no "Comments Compact".
@MainActor func checkLinkPreviewSettings() async throws {
    check("LinkPreviewSettings.default is Body Full / Comments Full / default color", LinkPreviewSettings.default.bodyDisplayMode == .full && LinkPreviewSettings.default.commentsDisplayMode == .full && LinkPreviewSettings.default.cardColorHex == nil)
    check("LinkPreviewSettings.default.displayColorText is \"Default color\"", LinkPreviewSettings.default.displayColorText == "Default color")
    var linkPreviewSettings = LinkPreviewSettings(bodyDisplayMode: .off, commentsDisplayMode: .full, cardColorHex: "ff8800")
    check("LinkPreviewSettings.displayColorText uppercases and prefixes a custom hex", linkPreviewSettings.displayColorText == "#FF8800")
    if let encoded = try? JSONEncoder().encode(linkPreviewSettings), let decoded = try? JSONDecoder().decode(LinkPreviewSettings.self, from: encoded) {
        check("LinkPreviewSettings round-trips through Codable unchanged", decoded == linkPreviewSettings)
    } else {
        check("LinkPreviewSettings round-trips through Codable unchanged", false)
    }
    LinkPreviewSettingsStore.save(linkPreviewSettings)
    check("LinkPreviewSettingsStore.load reflects the last saved settings", LinkPreviewSettingsStore.load() == linkPreviewSettings)
    LinkPreviewSettingsStore.save(.default)
}

// MARK: - DeletedCommentsClassifier / ArchivedComment
@MainActor func checkDeletedCommentsClassifierArchivedComment() async throws {
    check("DeletedCommentsClassifier recognizes [deleted]", DeletedCommentsClassifier.bodyLooksDeletedOrRemoved("[deleted]"))
    check("DeletedCommentsClassifier recognizes [removed]", DeletedCommentsClassifier.bodyLooksDeletedOrRemoved("[removed]"))
    check("DeletedCommentsClassifier recognizes bare 'removed'", DeletedCommentsClassifier.bodyLooksDeletedOrRemoved("Removed"))
    check("DeletedCommentsClassifier recognizes an empty body as deleted", DeletedCommentsClassifier.bodyLooksDeletedOrRemoved("   "))
    check("DeletedCommentsClassifier does not misclassify real comment text", !DeletedCommentsClassifier.bodyLooksDeletedOrRemoved("This is a perfectly normal comment."))
    check("DeletedCommentReason.userDeleted displays real verbatim chip text", DeletedCommentReason.userDeleted.displayLabel == "DELETED BY USER")
    check("DeletedCommentReason.moderatorRemoved displays real verbatim chip text", DeletedCommentReason.moderatorRemoved.displayLabel == "REMOVED BY MOD")
    let archivedComment = ArchivedComment(fullname: "t1_abc123", author: "someuser", body: "the real recovered text", score: 42, reason: .moderatorRemoved)
    check("ArchivedComment stores its fields unchanged", archivedComment.fullname == "t1_abc123" && archivedComment.body == "the real recovered text" && archivedComment.score == 42 && archivedComment.reason == .moderatorRemoved)
}

// MARK: - Apollo Reborn hub settings

// "Live Interactive Posts" / "Show in Feed" Devvit switches
// (UDKeyDevvitInteractivePosts / UDKeyDevvitFeedWidgets). Both default ON and
// must survive a Codable round-trip and decode from blobs that lack them.
@MainActor func checkApolloRebornHubSettings() async throws {
    check("GeneralSettings.default leaves Live Interactive Posts off, as Reborn registers", !GeneralSettings.default.devvitInteractivePosts)
    check("GeneralSettings.default enables Devvit Show in Feed", GeneralSettings.default.devvitFeedWidgets)
    var devvitSettings = GeneralSettings.default
    devvitSettings.devvitInteractivePosts = false
    devvitSettings.devvitFeedWidgets = false
    let devvitEncoded = try! JSONEncoder().encode(devvitSettings)
    let devvitDecoded = try! JSONDecoder().decode(GeneralSettings.self, from: devvitEncoded)
    check("Devvit switches round-trip through Codable unchanged", !devvitDecoded.devvitInteractivePosts && !devvitDecoded.devvitFeedWidgets)
    // A settings blob without these keys still decodes, with defaults restored.
    let legacyBlob = Data("{\"autoCollapseChildComments\":false,\"autoCollapsePinnedComments\":false,\"defaultCommentSort\":\"top\"}".utf8)
    if let legacyDecoded = try? JSONDecoder().decode(GeneralSettings.self, from: legacyBlob) {
        check("Legacy GeneralSettings blob still decodes with Devvit defaults", !legacyDecoded.devvitInteractivePosts && legacyDecoded.devvitFeedWidgets)
        // Reborn's default is off: the key is read bare with no registered
        // default, so an absent key is NO.
        check("a legacy blob decodes with Polls OFF, the real default",
              !legacyDecoded.pollsEnabled)
        check("Legacy GeneralSettings blob still decodes with Color Flairs off, the Reborn default", !legacyDecoded.enableFlairColors)
    } else {
        check("Legacy GeneralSettings blob still decodes", false)
    }

    // `DevvitPostDetector.feedShouldShowWidget` is the decision
    // `FeedScreen.PostRow.devvitFeedWidgetURL` gates on:
    // `sDevvitInteractivePosts && sDevvitFeedWidgets`.
    check("Devvit feed widget shows when both switches are on", DevvitPostDetector.feedShouldShowWidget(post: devvitPost, devvitInteractivePosts: true, devvitFeedWidgets: true))
    check("Devvit feed widget hidden when master switch is off", !DevvitPostDetector.feedShouldShowWidget(post: devvitPost, devvitInteractivePosts: false, devvitFeedWidgets: true))
    check("Devvit feed widget hidden when Show in Feed sub-toggle is off", !DevvitPostDetector.feedShouldShowWidget(post: devvitPost, devvitInteractivePosts: true, devvitFeedWidgets: false))
    check("Devvit feed widget hidden for a non-Devvit post even with both switches on", !DevvitPostDetector.feedShouldShowWidget(post: textPost, devvitInteractivePosts: true, devvitFeedWidgets: true))

    // "Recently Read Posts Limit" (sReadPostMaxCount). nil means unlimited
    // ("(unlimited)"), and the field is absent-tolerant.
    check("RecentlyReadSettings.default leaves the posts limit unlimited", RecentlyReadSettings.default.maxCount == nil)
    var recentLimited = RecentlyReadSettings.default
    recentLimited.maxCount = 50
    let recentEncoded = try! JSONEncoder().encode(recentLimited)
    let recentDecoded = try! JSONDecoder().decode(RecentlyReadSettings.self, from: recentEncoded)
    check("Recently Read posts limit round-trips through Codable unchanged", recentDecoded.maxCount == 50)
    let legacyRecentBlob = Data("{\"filterNSFW\":true,\"showThumbnails\":false}".utf8)
    if let legacyRecent = try? JSONDecoder().decode(RecentlyReadSettings.self, from: legacyRecentBlob) {
        check("Legacy RecentlyReadSettings blob decodes with an unlimited limit", legacyRecent.maxCount == nil && legacyRecent.filterNSFW && !legacyRecent.showThumbnails)
    } else {
        check("Legacy RecentlyReadSettings blob decodes", false)
    }

    // AppearanceSettings: defaults, Codable round-trip and legacy-blob
    // tolerance. showGIFProgress/showSelfPostThumbnails/showThumbnails/
    // thumbnailPosition/thumbnailSize are GeneralSettings-backed.
    check("AppearanceSettings.default matches Apollo's real defaults", !AppearanceSettings.default.showPageEndings && AppearanceSettings.default.showVotingButtons && AppearanceSettings.default.votingButtonsPosition == .right && !AppearanceSettings.default.useSystemTextSize)
    check("AppearanceSettings.default.showSubredditIconsInSubredditList is on", AppearanceSettings.default.showSubredditIconsInSubredditList)
    check("AppearanceSettings.default.rememberPostSizePerSubreddit is off", !AppearanceSettings.default.rememberPostSizePerSubreddit)
    var appearanceCustom = AppearanceSettings.default
    appearanceCustom.showVotingButtons = false
    appearanceCustom.votingButtonsPosition = .left
    appearanceCustom.alwaysShowUsernames = true
    appearanceCustom.showSubredditAtTop = true
    appearanceCustom.textSizeScale = 1.2
    let appearanceEncoded = try! JSONEncoder().encode(appearanceCustom)
    let appearanceDecoded = try! JSONDecoder().decode(AppearanceSettings.self, from: appearanceEncoded)
    check("AppearanceSettings round-trips through Codable unchanged", appearanceDecoded == appearanceCustom)
    // A blob missing the GeneralSettings-backed fields (showGIFProgress,
    // showSelfPostThumbnails, showThumbnails, thumbnailPosition, thumbnailSize)
    // still decodes, with defaults restored for the remaining fields.
    let legacyAppearanceBlob = Data("{\"showSubredditIconsInSubredditList\":false,\"showGIFProgress\":true,\"showSelfPostThumbnails\":false,\"showThumbnails\":false,\"thumbnailPosition\":\"right\",\"thumbnailSize\":\"large\",\"showVotingButtons\":false}".utf8)
    if let legacyAppearance = try? JSONDecoder().decode(AppearanceSettings.self, from: legacyAppearanceBlob) {
        check("Legacy AppearanceSettings blob preserves a surviving field's real value", !legacyAppearance.showSubredditIconsInSubredditList && !legacyAppearance.showVotingButtons)
        check("Legacy AppearanceSettings blob defaults removed fields' dependents", legacyAppearance.votingButtonsPosition == .right && !legacyAppearance.useSystemTextSize && legacyAppearance.textSizeScale == 1.0)
    } else {
        check("Legacy AppearanceSettings blob decodes instead of losing the whole settings object", false)
    }
    // PostSizeMemoryStore (`rememberPostSizePerSubreddit`) mirrors
    // PostSortMemoryStore: setting-gated, per-subreddit only.
    func withRememberPostSizePerSubreddit(_ enabled: Bool, _ body: () -> Void) {
        var settings = AppearanceSettingsStore.load()
        let original = settings.rememberPostSizePerSubreddit
        settings.rememberPostSizePerSubreddit = enabled
        AppearanceSettingsStore.save(settings)
        body()
        settings.rememberPostSizePerSubreddit = original
        AppearanceSettingsStore.save(settings)
    }
    UserDefaults.standard.removeObject(forKey: "Phoebus.postSizeBySubreddit")
    withRememberPostSizePerSubreddit(false) {
        PostSizeMemoryStore.recordSizeChange(subreddit: "pics", style: .large)
        check("PostSizeMemoryStore records nothing while the setting is off", PostSizeMemoryStore.rememberedStyle(subreddit: "pics") == nil)
    }
    withRememberPostSizePerSubreddit(true) {
        PostSizeMemoryStore.recordSizeChange(subreddit: "pics", style: .large)
        check("PostSizeMemoryStore remembers a subreddit's display style", PostSizeMemoryStore.rememberedStyle(subreddit: "pics") == .large)
        check("PostSizeMemoryStore is case-insensitive", PostSizeMemoryStore.rememberedStyle(subreddit: "PICS") == .large)
        check("PostSizeMemoryStore never remembers aggregate feeds (empty subreddit)", PostSizeMemoryStore.rememberedStyle(subreddit: "") == nil)
    }
    withRememberPostSizePerSubreddit(false) {
        check("PostSizeMemoryStore stops surfacing a remembered style once turned off", PostSizeMemoryStore.rememberedStyle(subreddit: "pics") == nil)
    }
    // AppearanceTextSizeStep: the step-count math that PhoebusUI's
    // AppearanceTextSizeOverride applies to the DynamicTypeSize enum app-wide,
    // kept dependency-free so it is testable without SwiftUI.
    check("AppearanceTextSizeStep maps the real default scale (1.0) to zero steps", AppearanceTextSizeStep.steps(forScale: 1.0) == 0)
    check("AppearanceTextSizeStep maps a larger scale to positive steps", AppearanceTextSizeStep.steps(forScale: 1.4) > 0)
    check("AppearanceTextSizeStep maps a smaller scale to negative steps", AppearanceTextSizeStep.steps(forScale: 0.8) < 0)
    check("Show Self Post Thumbnails is its own setting, on by default (CompactModeShowSelfPostThumbnails)",
          AppearanceSettings.default.compactShowSelfPostThumbnails
              && (try? JSONDecoder().decode(AppearanceSettings.self, from: Data("{}".utf8)))?.compactShowSelfPostThumbnails == true)
    check("Apollo's seven text sizes span xSmall...xxxLarge with Large (4) at 1.0",
          AppearanceTextSizeStep.scale(forApolloTextSize: 4) == 1.0
              && AppearanceTextSizeStep.sizes.map(AppearanceTextSizeStep.steps(forScale:)) == [-3, -2, -1, 0, 1, 2, 3]
              && AppearanceTextSizeStep.scale(forApolloTextSize: 8) == nil)

    // Hub row subtitles are live summaries and must reproduce their format
    // exactly.
    // -profileLayoutSummaryText
    // The default avatar is Circle (Reborn #1136, shared Profile Picture
    // Shape), so the default summary reads "Immersive · Circle".
    check("ProfileLayoutSettings.default.summaryText is 'Immersive · Circle'", ProfileLayoutSettings.default.summaryText == "Immersive · Circle")
    var profileHidden = ProfileLayoutSettings.default
    profileHidden.headerImmersive = false
    profileHidden.avatarStyle = .square
    profileHidden.showBanner = false
    profileHidden.showStatCards = false
    check("ProfileLayoutSettings.summaryText counts hidden bands", profileHidden.summaryText == "Compact · Square · 2 hidden")

    // -subredditLayoutSummaryText: headers off short-circuits to "Native (Apollo)".
    var layoutNative = SubredditLayoutSettings.default
    layoutNative.showSubredditHeaders = false
    // `subredditLayoutSummaryText` returns plain "Native" and
    // "Immersive"/"Compact", with no parenthesised forms.
    check("SubredditLayoutSettings.summaryText is 'Native' when headers are off", layoutNative.summaryText == "Native")
    var layoutCustom = SubredditLayoutSettings.default
    layoutCustom.showSubredditHeaders = true
    layoutCustom.subredditHeaderImmersive = true
    layoutCustom.subredditShowBanner = false
    layoutCustom.subredditShowJoinButton = false
    layoutCustom.subredditShowDisplayName = true
    check("SubredditLayoutSettings.summaryText lists hidden header elements", layoutCustom.summaryText == "Immersive · Banner, Join Button, User Flair Button, Sidebar Button off")

    // -subredditSectionsSummaryText. The default order is constant, and the
    // Following section is filtered out unless Separate Followed Users is on.
    check("SubredditSectionsSettings.default.summaryText matches the g39 section order", SubredditSectionsSettings.default.summaryText == "Favorites · Multireddits · Moderator")
    var sectionsFollowing = SubredditSectionsSettings.default
    sectionsFollowing.separateFollowedUsers = true
    check("SubredditSectionsSettings.summaryText includes Following once separated", sectionsFollowing.summaryText.contains("Following"))
    check("SubredditSectionsSettings hides Following by default", !SubredditSectionsSettings.default.summaryText.contains("Following"))

    // `hideMultiredditDescriptions` gates this consumer.
    // `RedditMultireddit.subtitle` is the decision shared by both multireddit
    // list surfaces (SubredditsRootScreen, MultiredditListScreen), matching
    // Reborn's `sHideMultiredditDescriptions`.
    let multiWithDescription = RedditMultireddit(name: "m1", displayName: "My Multi", path: "/user/u1/m/m1", subreddits: [.init(name: "swift"), .init(name: "ios")], visibility: "private", descriptionMarkdown: "A curated multi about Swift and iOS.")
    let multiWithoutDescription = RedditMultireddit(name: "m2", displayName: "Empty Multi", path: "/user/u1/m/m2", subreddits: [], visibility: "private", descriptionMarkdown: nil)
    let multiWithBlankDescription = RedditMultireddit(name: "m3", displayName: "Blank Multi", path: "/user/u1/m/m3", subreddits: [], visibility: "private", descriptionMarkdown: "   ")
    check("Multireddit subtitle shows the real description when set and not hidden", multiWithDescription.subtitle(hideDescriptions: false, fallback: "fallback") == "A curated multi about Swift and iOS.")
    check("Multireddit subtitle falls back when there is no description", multiWithoutDescription.subtitle(hideDescriptions: false, fallback: "fallback") == "fallback")
    check("Multireddit subtitle falls back for a whitespace-only description", multiWithBlankDescription.subtitle(hideDescriptions: false, fallback: "fallback") == "fallback")
    check("Multireddit subtitle is nil when hideMultiredditDescriptions is on, even with a real description", multiWithDescription.subtitle(hideDescriptions: true, fallback: "fallback") == nil)
    check("Multireddit subtitle is nil when hidden, even with no description (blanks entirely, not the fallback)", multiWithoutDescription.subtitle(hideDescriptions: true, fallback: "fallback") == nil)
    // Reddit's `description_md` field decodes from the website's model shape
    // and is absent-tolerant.
    let multiWithDescJSON = Data("{\"name\":\"m1\",\"display_name\":\"My Multi\",\"path\":\"/user/u1/m/m1\",\"subreddits\":[],\"visibility\":\"private\",\"description_md\":\"Hello world\"}".utf8)
    let decodedMultiWithDesc = try! JSONDecoder().decode(RedditMultireddit.self, from: multiWithDescJSON)
    check("RedditMultireddit decodes description_md", decodedMultiWithDesc.descriptionMarkdown == "Hello world")
    let multiWithoutDescJSON = Data("{\"name\":\"m2\",\"display_name\":\"Empty\",\"path\":\"/user/u1/m/m2\",\"subreddits\":[],\"visibility\":\"private\"}".utf8)
    let decodedMultiWithoutDesc = try! JSONDecoder().decode(RedditMultireddit.self, from: multiWithoutDescJSON)
    check("RedditMultireddit decodes fine with no description_md key at all", decodedMultiWithoutDesc.descriptionMarkdown == nil)

    // Polls and Color Flairs both default OFF, as Reborn registers them.
    check("GeneralSettings.default leaves Polls OFF, matching Reborn", !GeneralSettings.default.pollsEnabled)
    check("GeneralSettings.default leaves Color Flairs off, as Reborn registers", !GeneralSettings.default.enableFlairColors)
}

// --- Suggested sort ---

// RedditPost.suggestedSort (`ignoreSuggestedSort`'s backing data): decodes
// Reddit's `suggested_sort`, treats a missing key as nil, and treats the
// literal string "null" (which Reddit sometimes sends instead of omitting
// the key) as nil.
@MainActor func checkDeadToggleFixesGeneralSettingsScreenScope() async throws {
    check("RedditPost.suggestedSort is nil when the key is absent", makeTestPost(id: "nosort").suggestedSort == nil)
    let suggestedSortJSON = """
    {"id":"s1","name":"t3_s1","title":"t","author":"u",
     "subreddit":"test","permalink":"/r/test/comments/s1/",
     "score":1,"num_comments":0,"created_utc":0,"is_self":false,
     "over_18":false,"spoiler":false,"stickied":false,"saved":false,
     "suggested_sort":"qa"}
    """.data(using: .utf8)!
    let suggestedSortPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: suggestedSortJSON)
    check("RedditPost.suggestedSort decodes a real moderator-pinned sort", suggestedSortPost.suggestedSort == "qa")
    let nullSuggestedSortJSON = """
    {"id":"s2","name":"t3_s2","title":"t","author":"u",
     "subreddit":"test","permalink":"/r/test/comments/s2/",
     "score":1,"num_comments":0,"created_utc":0,"is_self":false,
     "over_18":false,"spoiler":false,"stickied":false,"saved":false,
     "suggested_sort":"null"}
    """.data(using: .utf8)!
    let nullSuggestedSortPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: nullSuggestedSortJSON)
    check("RedditPost.suggestedSort treats the literal string \"null\" as absent", nullSuggestedSortPost.suggestedSort == nil)

    // PostSortMemoryStore (`rememberPostsSortPerSubreddit`) is the posts-sort
    // analog of CommentSortMemoryStore, gated on a plain on/off flag.
    func withRememberPostsSortPerSubreddit(_ enabled: Bool, _ body: () -> Void) {
        var settings = GeneralSettingsStore.load()
        let original = settings.rememberPostsSortPerSubreddit
        settings.rememberPostsSortPerSubreddit = enabled
        GeneralSettingsStore.save(settings)
        body()
        settings.rememberPostsSortPerSubreddit = original
        GeneralSettingsStore.save(settings)
    }
    UserDefaults.standard.removeObject(forKey: "Phoebus.postSortBySubreddit")
    UserDefaults.standard.removeObject(forKey: "Phoebus.postSortTimeframeBySubreddit")
    withRememberPostsSortPerSubreddit(false) {
        PostSortMemoryStore.recordSortChange(subreddit: "pics", sort: "top", timeframe: "week")
        check("PostSortMemoryStore records nothing while the setting is off", PostSortMemoryStore.rememberedSort(subreddit: "pics") == nil)
    }
    withRememberPostsSortPerSubreddit(true) {
        PostSortMemoryStore.recordSortChange(subreddit: "pics", sort: "top", timeframe: "week")
        check("PostSortMemoryStore remembers a subreddit's sort", PostSortMemoryStore.rememberedSort(subreddit: "pics") == "top")
        check("PostSortMemoryStore remembers a subreddit's timeframe", PostSortMemoryStore.rememberedTimeframe(subreddit: "pics") == "week")
        check("PostSortMemoryStore is case-insensitive", PostSortMemoryStore.rememberedSort(subreddit: "PICS") == "top")
        check("PostSortMemoryStore never remembers Home/aggregate feeds (empty subreddit)", PostSortMemoryStore.rememberedSort(subreddit: "") == nil)
    }
    withRememberPostsSortPerSubreddit(false) {
        check("PostSortMemoryStore stops surfacing a remembered sort once turned off", PostSortMemoryStore.rememberedSort(subreddit: "pics") == nil)
    }

    // LastViewedSubredditStore (`rememberSubredditToLoad`/`defaultRedditToLoad`):
    // Codable round-trip for every destination the Posts tab can restore.
    UserDefaults.standard.removeObject(forKey: "com.pendo324.Phoebus.lastViewedFeedDestination")
    check("LastViewedSubredditStore has nothing recorded initially", LastViewedSubredditStore.load() == nil)
    LastViewedSubredditStore.record(.all)
    check("LastViewedSubredditStore round-trips .all", LastViewedSubredditStore.load() == .all)
    LastViewedSubredditStore.recordSubreddit("apolloapp")
    check("LastViewedSubredditStore round-trips a real subreddit", LastViewedSubredditStore.load() == .subreddit("apolloapp"))
    LastViewedSubredditStore.recordMultireddit(path: "/user/x/m/y", name: "y")
    check("LastViewedSubredditStore round-trips a multireddit", LastViewedSubredditStore.load() == .multireddit(path: "/user/x/m/y", name: "y"))
    LastViewedSubredditStore.record(.home)
    check("LastViewedSubredditStore round-trips .home", LastViewedSubredditStore.load() == .home)
}

// MARK: - LinkRouter ("Open Reddit Links in Apollo" / "Open Tweets in…")
// `LinkRouter.route` is a pure decision function so routing precedence can
// be asserted here.
@MainActor func checkLinkRouterOpenRedditLinksInApollo() async throws {
    var linkGeneral = GeneralSettings.default
    linkGeneral.openRedditLinksInApollo = true
    linkGeneral.openTwitterLinksIn = .twitterApp
    let inAppBrowser = ExternalBrowserSettings.default

    // A reddit.com post URL routes natively when the setting is on.
    if case .native(let t) = LinkRouter.route(URL(string: "https://www.reddit.com/r/swift/comments/abc123/title/")!, general: linkGeneral, browser: inAppBrowser),
       case .post(let sub, let id) = t {
        check("LinkRouter routes a reddit post URL natively", sub == "swift" && id == "abc123")
    } else {
        check("LinkRouter routes a reddit post URL natively", false)
    }

    // ...and not when it is off.
    var linkOff = linkGeneral
    linkOff.openRedditLinksInApollo = false
    if case .inApp = LinkRouter.route(URL(string: "https://www.reddit.com/r/swift/comments/abc123/title/")!, general: linkOff, browser: inAppBrowser) {
        check("LinkRouter respects Open Reddit Links in Apollo being off", true)
    } else {
        check("LinkRouter respects Open Reddit Links in Apollo being off", false)
    }

    // A reddit URL the parser cannot map to a screen opens in a browser.
    if case .inApp = LinkRouter.route(URL(string: "https://www.reddit.com/wiki/index")!, general: linkGeneral, browser: inAppBrowser) {
        check("LinkRouter sends unmappable reddit URLs to a browser, not nowhere", true)
    } else {
        check("LinkRouter sends unmappable reddit URLs to a browser, not nowhere", false)
    }

    // Tweets go to the X app only when that preference is set.
    if case .twitterApp = LinkRouter.route(URL(string: "https://x.com/user/status/123")!, general: linkGeneral, browser: inAppBrowser) {
        check("LinkRouter sends tweets to the X app when preferred", true)
    } else {
        check("LinkRouter sends tweets to the X app when preferred", false)
    }
    var tweetInApp = linkGeneral
    tweetInApp.openTwitterLinksIn = .inApp
    if case .inApp = LinkRouter.route(URL(string: "https://twitter.com/user/status/123")!, general: tweetInApp, browser: inAppBrowser) {
        check("LinkRouter keeps tweets in-app when that is the preference", true)
    } else {
        check("LinkRouter keeps tweets in-app when that is the preference", false)
    }

    // Host matching tolerates Reddit's host variants and does not capture
    // media hosts, which have their own handling.
    check("LinkRouter recognizes old.reddit.com", LinkRouter.isRedditURL(URL(string: "https://old.reddit.com/r/a")!))
    check("LinkRouter recognizes redd.it short links", LinkRouter.isRedditURL(URL(string: "https://redd.it/abc")!))
    check("LinkRouter does NOT treat i.redd.it media as a screen", !LinkRouter.isRedditURL(URL(string: "https://i.redd.it/x.jpg")!))
    check("LinkRouter does NOT treat v.redd.it media as a screen", !LinkRouter.isRedditURL(URL(string: "https://v.redd.it/x")!))
    check("LinkRouter recognizes x.com as Twitter", LinkRouter.isTwitterURL(URL(string: "https://x.com/u/status/1")!))
    check("LinkRouter ignores unrelated hosts", !LinkRouter.isRedditURL(URL(string: "https://example.com/r/swift")!))
}

// MARK: - FeedPaginationPolicy
// Pins the infinite-scroll trigger rule, which passes Reddit's `after`
// cursor back, and the cross-page dedupe.
@MainActor func checkFeedPaginationPolicyG42InfiniteScrollingWasEntirely() async throws {
    let thr = FeedPaginationPolicy.loadMoreThreshold
    // Near the end of 25 loaded posts -> load; early in the list -> don't.
    check("Pagination triggers within the threshold of the end", FeedPaginationPolicy.shouldLoadMore(index: 25 - thr, loadedCount: 25, infiniteScrollingEnabled: true, reachedEnd: false, isLoadingMore: false, isLoading: false))
    check("Pagination does not trigger early in the list", !FeedPaginationPolicy.shouldLoadMore(index: 0, loadedCount: 25, infiniteScrollingEnabled: true, reachedEnd: false, isLoadingMore: false, isLoading: false))
    check("Pagination triggers on the very last row", FeedPaginationPolicy.shouldLoadMore(index: 24, loadedCount: 25, infiniteScrollingEnabled: true, reachedEnd: false, isLoadingMore: false, isLoading: false))
    // The "Infinite Scrolling" setting stops it.
    check("Infinite Scrolling off stops auto-loading", !FeedPaginationPolicy.shouldLoadMore(index: 24, loadedCount: 25, infiniteScrollingEnabled: false, reachedEnd: false, isLoadingMore: false, isLoading: false))
    // Guards against redundant/invalid fetches.
    check("Pagination stops once Reddit reports end of listing", !FeedPaginationPolicy.shouldLoadMore(index: 24, loadedCount: 25, infiniteScrollingEnabled: true, reachedEnd: true, isLoadingMore: false, isLoading: false))
    check("Pagination does not stack concurrent page fetches", !FeedPaginationPolicy.shouldLoadMore(index: 24, loadedCount: 25, infiniteScrollingEnabled: true, reachedEnd: false, isLoadingMore: true, isLoading: false))
    check("Pagination waits for the first page to finish", !FeedPaginationPolicy.shouldLoadMore(index: 24, loadedCount: 25, infiniteScrollingEnabled: true, reachedEnd: false, isLoadingMore: false, isLoading: true))

    // Cross-page dedupe: Reddit repeats posts across pages as ranking churns,
    // and appending blindly would produce duplicate SwiftUI ids.
    check("Page merge drops posts already shown", FeedPaginationPolicy.mergePage(existing: ["a", "b", "c"], incoming: ["c", "d"]) == ["a", "b", "c", "d"])
    check("Page merge preserves order and appends new posts", FeedPaginationPolicy.mergePage(existing: ["a"], incoming: ["b", "c"]) == ["a", "b", "c"])
    check("Page merge of a fully duplicate page adds nothing", FeedPaginationPolicy.mergePage(existing: ["a", "b"], incoming: ["a", "b"]) == ["a", "b"])
}

// MARK: - Notification sound
// "None" must be genuinely silent rather than falling back to `.default`.
@MainActor func checkFinalDeadToggleLeftovers() async throws {
    #if canImport(UserNotifications)
    check("NotificationSound.none maps to no sound", NotificationSound.none.unNotificationSound == nil)
    check("NotificationSound.defaultSound maps to a real sound", NotificationSound.defaultSound.unNotificationSound != nil)
    check("NotificationSound.chime maps to a real sound", NotificationSound.chime.unNotificationSound != nil)
    #endif

    // The Info Row translation marker is only offered once translation is
    // enabled.
    var translationOff = TranslationSettings.default
    translationOff.enableBulkTranslation = false
    TranslationSettingsStore.save(translationOff)
    check("Translation marker unavailable while translation is off", !InfoRowSettings.translationAvailable)
    var translationOn = TranslationSettings.default
    translationOn.enableBulkTranslation = true
    TranslationSettingsStore.save(translationOn)
    check("Translation marker available once translation is enabled", InfoRowSettings.translationAvailable
          == (translationOn.mode == .tapToTranslate || translationOn.showTitleDetails || translationOn.showDetails))
    var noMarker = translationOn
    noMarker.mode = .automatic; noMarker.showDetails = false; noMarker.showTitleDetails = false
    check("...and not when neither Tap to Translate nor Show Details is on",
          !InfoRowSettings.translationAvailable(noMarker))
    TranslationSettingsStore.save(translationOff)
}

// MARK: - Stock Apollo defaults
// Defaults match stock Apollo's settings screens.
@MainActor func checkStockApolloCoverageGapsClosed() async throws {
    check("Upvote on Save defaults off", !GeneralSettings.default.upvoteOnSave)
    check("Show Jump Button defaults on", GeneralSettings.default.showJumpButton)
    check("Jump Button defaults to the right", GeneralSettings.default.jumpButtonPosition == .bottomTrailing)
    check("Show Awards defaults on", GeneralSettings.default.showAwards)
    check("Post Flair defaults on", GeneralSettings.default.showPostFlair)
    check("User Flair defaults on", GeneralSettings.default.showUserFlair)
    check("New Comments Highlightifier defaults off", !GeneralSettings.default.newCommentsHighlightifier)
    check("Mark Read on Scroll defaults off", !MarkReadSettings.default.markReadOnScroll)
    check("Show Hide Read Button defaults off", !MarkReadSettings.default.showHideReadButton)
    check("Portrait Lock Buddy defaults off", !PortraitLockSettings().portraitLockBuddy)

    // Autoplay policy: "Wi-Fi Only" must differ by network, so assert all
    // three modes both ways.
    check("Autoplay Always plays on cellular", AutoplayPolicy.shouldAutoplay(mode: .always, isUnmetered: false))
    check("Autoplay Never stays off even on Wi-Fi", !AutoplayPolicy.shouldAutoplay(mode: .never, isUnmetered: true))
    check("Autoplay Wi-Fi Only plays on Wi-Fi", AutoplayPolicy.shouldAutoplay(mode: .wifiOnly, isUnmetered: true))
    check("Autoplay Wi-Fi Only stays off on cellular", !AutoplayPolicy.shouldAutoplay(mode: .wifiOnly, isUnmetered: false))
    check("Autoplay defaults to Always", GeneralSettings.default.autoplayMode == .always)

    // Legacy blobs decode with the new fields defaulted, since strict
    // decoding would lose the whole settings object.
    let legacyGeneral = Data("{\"autoCollapseChildComments\":false}".utf8)
    if let decoded = try? JSONDecoder().decode(GeneralSettings.self, from: legacyGeneral) {
        check("Legacy GeneralSettings blob decodes with new coverage fields defaulted",
              decoded.showJumpButton && decoded.showAwards && decoded.autoplayMode == .always && !decoded.upvoteOnSave)
    } else {
        check("Legacy GeneralSettings blob decodes with new coverage fields defaulted", false)
    }
    let legacyMarkRead = Data("{\"markReadOnOpen\":true,\"hideReadPosts\":false}".utf8)
    if let decoded = try? JSONDecoder().decode(MarkReadSettings.self, from: legacyMarkRead) {
        check("Legacy MarkReadSettings blob decodes with new fields defaulted",
              !decoded.markReadOnScroll && !decoded.showHideReadButton && decoded.markReadOnOpen)
    } else {
        check("Legacy MarkReadSettings blob decodes with new fields defaulted", false)
    }
    let legacyPortrait = Data("{\"isEnabled\":true}".utf8)
    if let decoded = try? JSONDecoder().decode(PortraitLockSettings.self, from: legacyPortrait) {
        check("Legacy PortraitLockSettings blob decodes, Buddy defaulted off",
              decoded.isEnabled && !decoded.portraitLockBuddy)
    } else {
        check("Legacy PortraitLockSettings blob decodes, Buddy defaulted off", false)
    }
}

// MARK: - Comments Theme (Theme Manager > Options row)
// Palettes match Apollo's; the settings row shows a palette name ("Forest").
@MainActor func checkCommentsThemeRealThemeManagerOptions() async throws {
    CommentsThemeStore.overridePaletteName = nil
    let rainbowTheme = Theme.defaultLight
    check("A built-in theme knows its own palette name", rainbowTheme.commentPaletteName == "Rainbow")
    check("With no override, comments follow the theme's palette",
          CommentsThemeStore.effectivePaletteName(theme: rainbowTheme) == "Rainbow")
    check("Follow-theme hexes match the theme's own palette",
          CommentsThemeStore.effectiveHexes(theme: rainbowTheme) == CommentColorPalette.hexes(named: "Rainbow", isDark: false))

    // An override wins over the theme's pairing, independent of the accent
    // theme.
    CommentsThemeStore.overridePaletteName = "Forest"
    check("An override replaces the theme's palette",
          CommentsThemeStore.effectivePaletteName(theme: rainbowTheme) == "Forest")
    check("Override hexes are the real Forest light values",
          CommentsThemeStore.effectiveHexes(theme: rainbowTheme) == CommentColorPalette.hexes(named: "Forest", isDark: false))
    // ...and tracks the theme's light/dark variant.
    check("Override honours the dark variant",
          CommentsThemeStore.effectiveHexes(theme: Theme.defaultDark) == CommentColorPalette.hexes(named: "Forest", isDark: true))

    // A garbage or stale palette name must not break comment rendering.
    CommentsThemeStore.overridePaletteName = "NotARealPalette"
    check("An unknown palette name is ignored rather than persisted",
          CommentsThemeStore.overridePaletteName == nil)

    // A generated or imported theme carries custom hexes and no named palette;
    // with no override it keeps its own colours rather than falling back to
    // Rainbow.
    CommentsThemeStore.overridePaletteName = nil
    let generated = Theme(id: "gen1", name: "Panda", accentColorHex: "112233",
                          commentDepthColorHexes: ["111111", "222222", "333333"],
                          isDark: false, isGenerated: true)
    check("A generated theme has no named palette", generated.commentPaletteName == nil)
    check("A generated theme keeps its own custom comment colours",
          CommentsThemeStore.effectiveHexes(theme: generated) == ["111111", "222222", "333333"])
    // An explicit override still wins over a generated theme's colours.
    CommentsThemeStore.overridePaletteName = "Ocean"
    check("An override still wins over a generated theme's colours",
          CommentsThemeStore.effectiveHexes(theme: generated) == CommentColorPalette.hexes(named: "Ocean", isDark: false))
    CommentsThemeStore.overridePaletteName = nil

    check("All six real palettes are offered", CommentColorPalette.names.count == 6)
    check("Forest is among them (the value the real app shows)", CommentColorPalette.names.contains("Forest"))

    print("---")
}

// MARK: - PushPopGesturePolicy
//
// Apollo's navigation gesture constants.
@MainActor func checkPushPopGesturePolicy() async throws {
    check("back inset is the real 70pt", PushPopGesturePolicy.leftInset == 70)
    check("forward inset is the real 40pt", PushPopGesturePolicy.rightInset == 40)
    check("dominance ratio is the real 1.65", PushPopGesturePolicy.horizontalDominance == 1.65)
    check("forward inset is narrower than back", PushPopGesturePolicy.rightInset < PushPopGesturePolicy.leftInset)

    // Ratio gate: 1.65 is the threshold, so 2:1 passes and 1.5:1 does not.
    check("2:1 horizontal drag is horizontal enough",
          PushPopGesturePolicy.isHorizontalEnough(velocityX: -200, velocityY: 100))
    check("1.5:1 drag is NOT horizontal enough (a 1.0 ratio would wrongly accept)",
          !PushPopGesturePolicy.isHorizontalEnough(velocityX: -150, velocityY: 100))
    check("exactly 1.65:1 qualifies (the test is >=)",
          PushPopGesturePolicy.isHorizontalEnough(velocityX: -165, velocityY: 100))
    check("pure horizontal drag qualifies without dividing by zero",
          PushPopGesturePolicy.isHorizontalEnough(velocityX: -200, velocityY: 0))
    check("pure vertical drag never qualifies",
          !PushPopGesturePolicy.isHorizontalEnough(velocityX: 0, velocityY: 200))
    check("sign of the drag does not affect the ratio test",
          PushPopGesturePolicy.isHorizontalEnough(velocityX: 200, velocityY: -100))

    // Forward gate on a 393pt-wide iPhone 17 screen: the zone is x >= 353.
    check("forward swipe begins at the trailing edge",
          PushPopGesturePolicy.shouldBeginForward(velocityX: -300, velocityY: 20, locationX: 390, viewWidth: 393))
    check("forward zone starts exactly at width - 40",
          PushPopGesturePolicy.shouldBeginForward(velocityX: -300, velocityY: 20, locationX: 353, viewWidth: 393))
    check("just inside width - 40 does not begin a forward swipe",
          !PushPopGesturePolicy.shouldBeginForward(velocityX: -300, velocityY: 20, locationX: 352, viewWidth: 393))
    check("rightward drag never begins a FORWARD swipe",
          !PushPopGesturePolicy.shouldBeginForward(velocityX: 300, velocityY: 20, locationX: 390, viewWidth: 393))
    check("vertical scroll at the trailing edge still scrolls",
          !PushPopGesturePolicy.shouldBeginForward(velocityX: -40, velocityY: 600, locationX: 390, viewWidth: 393))
    check("a lazy diagonal at the trailing edge does NOT navigate",
          !PushPopGesturePolicy.shouldBeginForward(velocityX: -120, velocityY: 100, locationX: 390, viewWidth: 393))
    check("56pt (my old guess) is outside the real forward zone",
          !PushPopGesturePolicy.shouldBeginForward(velocityX: -300, velocityY: 20, locationX: 393 - 56, viewWidth: 393))

    // Back gate: the zone is x <= 70, nearly twice as wide.
    check("back swipe begins near the leading edge",
          PushPopGesturePolicy.shouldBeginBack(velocityX: 300, velocityY: 20, locationX: 10))
    check("back zone ends exactly at 70",
          PushPopGesturePolicy.shouldBeginBack(velocityX: 300, velocityY: 20, locationX: 70))
    check("past 70 does not begin a back swipe",
          !PushPopGesturePolicy.shouldBeginBack(velocityX: 300, velocityY: 20, locationX: 71))
    check("leftward drag never begins a BACK swipe",
          !PushPopGesturePolicy.shouldBeginBack(velocityX: -300, velocityY: 20, locationX: 10))
    check("vertical scroll at the leading edge still scrolls",
          !PushPopGesturePolicy.shouldBeginBack(velocityX: 40, velocityY: 600, locationX: 10))
}

// MARK: - Interactive transition
//
// A UIPercentDrivenInteractiveTransition: progress is translation/width,
// and release finishes if the drag passed half the width or was flicked
// faster than 100pt/s.
@MainActor func checkInteractiveTransition() async throws {
    check("completion velocity is the real 100pt/s", PushPopGesturePolicy.completionVelocity == 100)
    check("completion fraction is the real half-width", PushPopGesturePolicy.completionFraction == 0.5)

    check("progress is translation over width",
          PushPopGesturePolicy.transitionProgress(translationX: -196.5, viewWidth: 393) == 0.5)
    check("progress clamps to 1 past full width",
          PushPopGesturePolicy.transitionProgress(translationX: -800, viewWidth: 393) == 1)
    check("progress is 0 at rest",
          PushPopGesturePolicy.transitionProgress(translationX: 0, viewWidth: 393) == 0)
    check("progress never divides by a zero width",
          PushPopGesturePolicy.transitionProgress(translationX: -100, viewWidth: 0) == 0)

    // Forward (leftward) release.
    check("a slow drag past half the width completes",
          PushPopGesturePolicy.shouldComplete(translationX: -250, velocityX: -10, viewWidth: 393, isForward: true))
    check("a short but fast flick completes (the velocity escape hatch)",
          PushPopGesturePolicy.shouldComplete(translationX: -60, velocityX: -900, viewWidth: 393, isForward: true))
    check("a short slow drag springs back",
          !PushPopGesturePolicy.shouldComplete(translationX: -60, velocityX: -10, viewWidth: 393, isForward: true))
    check("exactly 100pt/s completes (the test is >=)",
          PushPopGesturePolicy.shouldComplete(translationX: -60, velocityX: -100, viewWidth: 393, isForward: true))
    check("just under 100pt/s and under half width springs back",
          !PushPopGesturePolicy.shouldComplete(translationX: -60, velocityX: -99, viewWidth: 393, isForward: true))

    // Back (rightward) release is the mirror image.
    check("a rightward drag past half the width completes back",
          PushPopGesturePolicy.shouldComplete(translationX: 250, velocityX: 10, viewWidth: 393, isForward: false))
    check("a fast rightward flick completes back",
          PushPopGesturePolicy.shouldComplete(translationX: 60, velocityX: 900, viewWidth: 393, isForward: false))
    check("a short slow rightward drag springs back",
          !PushPopGesturePolicy.shouldComplete(translationX: 60, velocityX: 10, viewWidth: 393, isForward: false))

    // A drag starting inside either navigation inset belongs to navigation,
    // not to the row swipe.
    check("a drag starting at x=10 is inside the back inset",
          10 <= PushPopGesturePolicy.leftInset)
    check("a drag starting at x=380 is inside the forward inset on a 393pt screen",
          380 >= 393 - PushPopGesturePolicy.rightInset)
    check("a drag starting mid-row is in neither inset",
          200 > PushPopGesturePolicy.leftInset && 200 < 393 - PushPopGesturePolicy.rightInset)
}

// MARK: - Settings cache
//
// `NavigationGestureSettingsStore.load()` runs from gesture paths dozens of
// times per second, so it caches; these assert the cache serves the
// current value.
@MainActor func checkSettingsCache() async throws {
    let originalGestureSettings = NavigationGestureSettingsStore.load()
    NavigationGestureSettingsStore.save(NavigationGestureSettings(pushPopSwipeGesturesEnabled: false))
    check("a saved value is visible immediately (cache is refreshed by save)",
          NavigationGestureSettingsStore.load().pushPopSwipeGesturesEnabled == false)
    NavigationGestureSettingsStore.save(NavigationGestureSettings(pushPopSwipeGesturesEnabled: true))
    check("saving again is visible immediately, not served stale",
          NavigationGestureSettingsStore.load().pushPopSwipeGesturesEnabled == true)
    NavigationGestureSettingsStore.invalidateCache()
    check("a value survives cache invalidation (it really was persisted)",
          NavigationGestureSettingsStore.load().pushPopSwipeGesturesEnabled == true)
    check("repeated loads are consistent",
          NavigationGestureSettingsStore.load() == NavigationGestureSettingsStore.load())
    NavigationGestureSettingsStore.save(originalGestureSettings)
}

// MARK: - RecentEntryPolicy
//
// Backs the short-lived comment cache that keeps a forward swipe from
// blanking a post's comments and refetching them; pins both staleness
// and eviction.
@MainActor func checkRecentEntryPolicy() async throws {
    check("cache lifetime is 10s", RecentEntryPolicy.lifetime == 10)
    check("cache holds 5 posts", RecentEntryPolicy.capacity == 5)

    check("a just-stored entry is fresh", RecentEntryPolicy.isFresh(age: 0))
    check("an entry mid-window is fresh", RecentEntryPolicy.isFresh(age: 5))
    check("an entry just inside the window is fresh", RecentEntryPolicy.isFresh(age: 9.99))
    check("an entry at exactly the lifetime is STALE", !RecentEntryPolicy.isFresh(age: 10))
    check("an old entry is stale", !RecentEntryPolicy.isFresh(age: 60))
    check("a negative age (clock moved) is not treated as fresh",
          !RecentEntryPolicy.isFresh(age: -1))

    // Eviction: oldest first, and only once over capacity.
    check("nothing is evicted below capacity",
          RecentEntryPolicy.keysToEvict(agesByKey: ["a": 1, "b": 2]).isEmpty)
    check("nothing is evicted exactly at capacity",
          RecentEntryPolicy.keysToEvict(agesByKey: ["a": 1, "b": 2, "c": 3, "d": 4, "e": 5]).isEmpty)
    check("the single oldest entry is evicted at capacity + 1",
          RecentEntryPolicy.keysToEvict(agesByKey: ["a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "old": 99])
            == ["old"])

    let overfull = ["a": 1.0, "b": 2.0, "c": 3.0, "d": 4.0, "e": 5.0, "f": 6.0, "g": 7.0]
    let evicted = Set(RecentEntryPolicy.keysToEvict(agesByKey: overfull))
    check("exactly the overflow is evicted", evicted.count == 2)
    check("the two OLDEST are the ones evicted", evicted == ["g", "f"])
    check("the newest entry is never evicted", !evicted.contains("a"))
}

// MARK: - VoteStateStore
//
// Vote state lives in one place written by both the swipe gesture and the
// arrow buttons, so a confirmed vote updates the row's arrow and score.
@MainActor func checkVoteStateStore() async throws {
    check("no vote + upvote scores +1", VoteStateStore.scoreDelta(from: nil, direction: 1) == 1)
    check("no vote + downvote scores -1", VoteStateStore.scoreDelta(from: nil, direction: -1) == -1)
    check("clearing an upvote scores -1", VoteStateStore.scoreDelta(from: true, direction: 0) == -1)
    check("clearing a downvote scores +1", VoteStateStore.scoreDelta(from: false, direction: 0) == 1)
    check("downvote -> upvote swings +2", VoteStateStore.scoreDelta(from: false, direction: 1) == 2)
    check("upvote -> downvote swings -2", VoteStateStore.scoreDelta(from: true, direction: -1) == -2)
    check("re-upvoting an upvote is a no-op", VoteStateStore.scoreDelta(from: true, direction: 1) == 0)
    check("clearing a vote never cast is a no-op", VoteStateStore.scoreDelta(from: nil, direction: 0) == 0)

    // Pressing the direction already held clears the vote rather than
    // re-sending it.
    check("swiping upvote when not voted upvotes",
          VoteStateStore.toggledDirection(current: nil, tapped: 1) == 1)
    check("swiping upvote when ALREADY upvoted un-votes",
          VoteStateStore.toggledDirection(current: true, tapped: 1) == 0)
    check("swiping upvote when downvoted switches to upvote",
          VoteStateStore.toggledDirection(current: false, tapped: 1) == 1)
    check("swiping downvote when ALREADY downvoted un-votes",
          VoteStateStore.toggledDirection(current: false, tapped: -1) == 0)
    check("swiping downvote when upvoted switches to downvote",
          VoteStateStore.toggledDirection(current: true, tapped: -1) == -1)

    // A full swipe -> revert round trip, which is what the row renders from.
    await MainActor.run {
        let store = VoteStateStore.shared
        store.reset()

        check("an unvoted post reads through to the server value",
              store.vote(for: "t3_x", serverValue: nil) == nil)
        check("a post the server says is upvoted reads as upvoted",
              store.vote(for: "t3_x", serverValue: true) == true)

        let delta = store.applyVote(fullname: "t3_x", direction: 1, serverValue: nil)
        check("swiping upvote records the vote locally",
              store.vote(for: "t3_x", serverValue: nil) == true)
        check("swiping upvote moves the displayed score by 1",
              store.scoreDelta(for: "t3_x") == 1 && delta == 1)
        check("the local vote WINS over the stale server value",
              store.vote(for: "t3_x", serverValue: false) == true)

        store.revertVote(fullname: "t3_x", to: nil, delta: delta)
        check("a failed vote reverts the arrow", store.vote(for: "t3_x", serverValue: nil) == nil)
        check("a failed vote reverts the score", store.scoreDelta(for: "t3_x") == 0)

        // Saving, same shape.
        check("save reads through to the server value", store.isSaved("t3_x", serverValue: true))
        store.setSaved(true, for: "t3_y")
        check("a local save wins over the server value", store.isSaved("t3_y", serverValue: false))

        // Other posts are untouched by one post's vote.
        store.applyVote(fullname: "t3_a", direction: -1, serverValue: nil)
        check("voting one post does not move another",
              store.scoreDelta(for: "t3_b") == 0 && store.vote(for: "t3_b", serverValue: nil) == nil)
        store.reset()
    }
}

// MARK: - SwipeCommitPolicy
//
// The long threshold stays above the commit threshold; otherwise every
// committing swipe counts as long and fires the long action (Downvote
// instead of the upvote indicator on the Posts defaults).
@MainActor func checkSwipeCommitPolicy() async throws {
    for point in LongSwipeTriggerPoint.allCases {
        check("long threshold is beyond the commit point (\(point.title))",
              SwipeCommitPolicy.longThreshold(fraction: point.fraction) > SwipeCommitPolicy.commitThreshold)
    }

    check("a drag short of the commit point does nothing",
          !SwipeCommitPolicy.commits(distance: SwipeCommitPolicy.commitThreshold - 1))
    check("a drag at the commit point commits",
          SwipeCommitPolicy.commits(distance: SwipeCommitPolicy.commitThreshold))

    // The commit point must be reachable one-handed.
    check("the short swipe commits within a quarter of the screen",
          SwipeCommitPolicy.commitThreshold < 393 * 0.25)
    // Apollo commits the short action at exactly 60pt; the row recognizer's
    // 10pt + direction test, not the commit distance, rejects incidental drags.
    check("the short swipe commits at real Apollo's measured 60pt",
          SwipeCommitPolicy.commitThreshold == 60)
    check("...and the long action engages at the measured 120pt by default",
          SwipeCommitPolicy.longThreshold(fraction: LongSwipeTriggerPoint.normal.fraction) == 120)

    // Thresholds are constant points tied to a 30pt icon inset, so they are the
    // same on every device.
    check("the commit distance is the same on every screen width",
          SwipeCommitPolicy.commitThreshold(width: 320) == SwipeCommitPolicy.commitThreshold(width: 430))
}

// MARK: - Markdown zero-width cleanup
//
// Reddit's editor writes an intentionally blank line as a paragraph holding
// only a zero-width space. The entity is stripped (so "&#x200B;" never
// renders literally, #405) and the empty paragraph left behind is
// collapsed (#482/#1050).
@MainActor func checkApolloReborn370Parity() async throws {
    check("a body with no zero-width content is returned untouched",
          MarkdownBodyCleanup.clean("hello\n\nworld") == "hello\n\nworld")
    check("the hex entity no longer renders literally",
          !MarkdownBodyCleanup.clean("a\n\n&#x200B;\n\nb").contains("&#x200"))
    check("the decimal entity is stripped too",
          !MarkdownBodyCleanup.clean("a\n\n&#8203;\n\nb").contains("&#8203"))
    check("a raw U+200B character is stripped too",
          !MarkdownBodyCleanup.clean("a\n\n\u{200B}\n\nb").contains("\u{200B}"))
    check("entity case does not matter",
          !MarkdownBodyCleanup.clean("a\n\n&#X200B;\n\nb").contains("&#X200"))

    // One paragraph gap, not three blank lines.
    check("a blank paragraph collapses to a single separator",
          MarkdownBodyCleanup.clean("a\n\n&#x200B;\n\nb") == "a\n\nb")
    check("a leading blank paragraph is dropped",
          MarkdownBodyCleanup.clean("&#x200B;\n\nb") == "b")
    check("a trailing blank paragraph is dropped",
          MarkdownBodyCleanup.clean("a\n\n&#x200B;") == "a")
    check("a body that was ONLY the entity becomes empty",
          MarkdownBodyCleanup.clean("&#x200B;").isEmpty)
    check("several blank paragraphs each collapse",
          MarkdownBodyCleanup.clean("a\n\n&#x200B;\n\nb\n\n&#x200B;\n\nc") == "a\n\nb\n\nc")

    // A zero-width space on a hard-line-break line loses only the character,
    // so a blank line the author forced that way survives.
    check("a hard-line-break blank line is preserved",
          MarkdownBodyCleanup.clean("A\n&#x200B;\nB") == "A\n\nB")
    // An inline zero-width space is just removed, not treated as a blank.
    check("an inline zero-width space only loses the character",
          MarkdownBodyCleanup.clean("he&#x200B;llo") == "hello")
}

// MARK: - Bold Post Titles + favorites sort
@MainActor func checkApolloReborn370Parity2() async throws {
    check("Bold Post Titles defaults OFF, matching the real key",
          !AppearanceSettings.default.boldPostTitles)
    let boldDecoded = try! JSONDecoder().decode(AppearanceSettings.self, from: Data("{}".utf8))
    check("an older saved appearance blob also defaults it off", !boldDecoded.boldPostTitles)

    // "Sort Favorites Alphabetically" defaults OFF (native order).
    let favs = ["zeta", "Alpha", "sub10", "sub9", "beta"]
    check("with sorting OFF the native favoriting order is preserved",
          FavoriteSubredditsStore.applySorting(favs, name: { $0 }, sortAlphabetically: false) == favs)
    let sortedFavs = FavoriteSubredditsStore.applySorting(favs, name: { $0 }, sortAlphabetically: true)
    check("with sorting ON the list is alphabetical",
          sortedFavs.first == "Alpha" && sortedFavs.last == "zeta")
    // The comparator is localizedStandardCompare (Finder-style), so numbers
    // order naturally; a plain case-insensitive compare gets this pair wrong.
    check("...using the real Finder-style numeric ordering (sub9 before sub10)",
          sortedFavs.firstIndex(of: "sub9")! < sortedFavs.firstIndex(of: "sub10")!)
    // The sort is stable (`NSSortStable`): equal entries keep their original
    // order. Identical names are used since localizedStandardCompare orders
    // even "A" vs "a" deterministically.
    let dupes = [("dup", 1), ("aaa", 2), ("dup", 3)]
    let stable = FavoriteSubredditsStore.applySorting(dupes, name: { $0.0 }, sortAlphabetically: true)
    check("the sort is stable for equal-comparing names",
          stable.map(\.1) == [2, 1, 3])

    // Sorting never drops or renames an entry.
    check("sorting preserves every entry exactly",
          Set(sortedFavs) == Set(favs) && sortedFavs.count == favs.count)
}
