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
    check("default general settings uses small thumbnails (confirmed via Defaults.plist)", defaultGeneral.thumbnailSize == .small)
    check("ThumbnailSize has 4 cases (hidden/small/medium/large - hidden added after a real on-device screenshot showed a compact row with thumbnails off)", ThumbnailSize.allCases.count == 4)
    check("thumbnail sizes are strictly increasing", ThumbnailSize.small.pointSize < ThumbnailSize.medium.pointSize && ThumbnailSize.medium.pointSize < ThumbnailSize.large.pointSize)
    let encodedGeneral = try! JSONEncoder().encode(defaultGeneral)
    let decodedGeneral = try! JSONDecoder().decode(GeneralSettings.self, from: encodedGeneral)
    check("GeneralSettings round-trips through Codable", decodedGeneral == defaultGeneral)
    check("default general settings plays YouTube inline, not in native app (confirmed via Defaults.plist)", !defaultGeneral.openVideosInYouTubeApp)
    check("YouTubeURLParser builds native app URL from video ID", YouTubeURLParser.nativeAppURL(forVideoID: "dQw4w9WgXcQ")?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
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
