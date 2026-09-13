import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// Standalone Linux-runnable smoke test for PhoebusCore. The swift-testing
// test target pulls in the whole package graph (including SwiftUI-dependent
// PhoebusUI), which cannot build on Linux; this executable depends only on
// PhoebusCore and checks JSON decoding and comment-tree logic on the host.

// Every run starts from empty settings so values left behind by a previous
// run cannot change what the next run sees.
for key in UserDefaults.standard.dictionaryRepresentation().keys {
    UserDefaults.standard.removeObject(forKey: key)
}

nonisolated(unsafe) var failures = 0
func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

func makeComment(id: String) -> RedditComment {
    let json = """
    {"id":"\(id)","name":"t1_\(id)","author":"u","body":"b","score":0,
     "created_utc":0,"parent_id":"t3_x","link_id":"t3_x","saved":false,
     "score_hidden":false,"stickied":false}
    """.data(using: .utf8)!
    return try! JSONDecoder.reddit.decode(RedditComment.self, from: json)
}

func makeTestPost(id: String) -> RedditPost {
    let json = """
    {"id":"\(id)","name":"t3_\(id)","title":"t","author":"u",
     "subreddit":"test","permalink":"/r/test/comments/\(id)/",
     "score":1,"num_comments":0,"created_utc":0,"is_self":false,
     "over_18":false,"spoiler":false,"stickied":false,"saved":false}
    """.data(using: .utf8)!
    return try! JSONDecoder.reddit.decode(RedditPost.self, from: json)
}

// --- Post decoding ---
let postJSON = """
{
    "id": "abc123", "name": "t3_abc123", "title": "Test Post",
    "author": "someuser", "subreddit": "test", "selftext": "body text",
    "url": "https://example.com/img.png",
    "permalink": "/r/test/comments/abc123/test_post/",
    "score": 42, "upvote_ratio": 0.95, "num_comments": 3,
    "created_utc": 1700000000, "is_self": false, "over_18": false,
    "spoiler": false, "stickied": false, "saved": false, "likes": true,
    "thumbnail": "https://example.com/thumb.png",
    "link_flair_text": "Discussion"
}
""".data(using: .utf8)!
let post = try! JSONDecoder.reddit.decode(RedditPost.self, from: postJSON)
check("post.id decoded", post.id == "abc123")
check("post.name decoded", post.name == "t3_abc123")
check("post.score decoded", post.score == 42)
check("post.likes decoded", post.likes == true)
check("post.created decoded", post.created == Date(timeIntervalSince1970: 1700000000))

// --- Comment decoding ---
let commentJSON = """
{
    "id": "c1", "name": "t1_c1", "author": "commenter", "body": "hello world",
    "body_html": "<p>hello world</p>", "score": 5, "created_utc": 1700000100,
    "parent_id": "t3_abc123", "link_id": "t3_abc123", "saved": false,
    "score_hidden": false, "stickied": false
}
""".data(using: .utf8)!
let comment = try! JSONDecoder.reddit.decode(RedditComment.self, from: commentJSON)
check("comment.id decoded", comment.id == "c1")
check("comment.body decoded", comment.body == "hello world")

// OP badge, mod/admin distinguished flags and flair colors decode from
// comment JSON.
let richCommentJSON = """
{
    "id": "c2", "name": "t1_c2", "author": "opuser", "body": "I am the OP",
    "score": 5, "created_utc": 1700000000, "parent_id": "t3_x", "link_id": "t3_x",
    "saved": false, "score_hidden": false, "stickied": false,
    "is_submitter": true, "distinguished": "moderator",
    "author_flair_text": "Verified", "author_flair_background_color": "#FF4500",
    "author_flair_text_color": "dark"
}
""".data(using: .utf8)!
let richComment = try! JSONDecoder.reddit.decode(RedditComment.self, from: richCommentJSON)
check("comment.isSubmitter decoded true for OP", richComment.isSubmitter == true)
check("comment.distinguished decoded", richComment.distinguished == "moderator")
check("comment.authorFlairBackgroundColor decoded", richComment.authorFlairBackgroundColor == "#FF4500")
check("comment.authorFlairTextColorRaw decoded even when non-hex ('dark')", richComment.authorFlairTextColorRaw == "dark")
check("comment missing is_submitter/distinguished decode as nil, not false/empty", comment.isSubmitter == nil && comment.distinguished == nil)

check("RedditFlairColor.validHex accepts a real hex with #", RedditFlairColor.validHex(from: "#FF4500") == "FF4500")
check("RedditFlairColor.validHex accepts a real hex without #", RedditFlairColor.validHex(from: "1a2b3c") == "1a2b3c")
check("RedditFlairColor.validHex rejects nil", RedditFlairColor.validHex(from: nil) == nil)
check("RedditFlairColor.validHex rejects empty string", RedditFlairColor.validHex(from: "") == nil)
check("RedditFlairColor.validHex rejects a non-hex placeholder like 'dark'", RedditFlairColor.validHex(from: "dark") == nil)
check("RedditFlairColor.validHex rejects a wrong-length string", RedditFlairColor.validHex(from: "FFF") == nil)

let postWithFlairColorsJSON = """
{
    "id": "flairpost", "name": "t3_flairpost", "title": "t", "author": "a",
    "subreddit": "s", "permalink": "/r/s/comments/flairpost", "score": 1,
    "num_comments": 0, "created_utc": 0, "is_self": true, "over_18": false,
    "spoiler": false, "stickied": false, "saved": false,
    "link_flair_text": "Official", "link_flair_background_color": "#0079D3",
    "link_flair_text_color": "light"
}
""".data(using: .utf8)!
let postWithFlairColors = try! JSONDecoder.reddit.decode(RedditPost.self, from: postWithFlairColorsJSON)
check("post.linkFlairBackgroundColor decoded", postWithFlairColors.linkFlairBackgroundColor == "#0079D3")
check("post.linkFlairTextColorRaw decoded", postWithFlairColors.linkFlairTextColorRaw == "light")

// --- Nested comment tree building ---
let treeJSON = """
[
  {"kind":"t1","data":{"id":"c1","name":"t1_c1","author":"a1","body":"top1",
    "score":10,"created_utc":0,"parent_id":"t3_x","link_id":"t3_x","saved":false,
    "score_hidden":false,"stickied":false,
    "replies":{"kind":"Listing","data":{"children":[
      {"kind":"t1","data":{"id":"c2","name":"t1_c2","author":"a2","body":"nested",
        "score":3,"created_utc":0,"parent_id":"t1_c1","link_id":"t3_x","saved":false,
        "score_hidden":false,"stickied":false}}
    ]}}}},
  {"kind":"t1","data":{"id":"c3","name":"t1_c3","author":"a3","body":"top2",
    "score":1,"created_utc":0,"parent_id":"t3_x","link_id":"t3_x","saved":false,
    "score_hidden":false,"stickied":false}}
]
""".data(using: .utf8)!
let jsonValues = try! JSONDecoder().decode([JSONValue].self, from: treeJSON)
let tree = CommentTreeBuilder.build(from: jsonValues)
check("tree has 2 top-level nodes", tree.count == 2)
check("tree[0].id == c1", tree[0].comment.id == "c1")
check("tree[0].depth == 0", tree[0].depth == 0)
check("tree[0] has 1 child", tree[0].children.count == 1)
check("tree[0].children[0].id == c2", tree[0].children[0].comment.id == "c2")
check("tree[0].children[0].depth == 1", tree[0].children[0].depth == 1)
check("tree[1].id == c3", tree[1].comment.id == "c3")
check("tree[1] has no children", tree[1].children.isEmpty)
// --- "more" comment continuation stubs: threads show "N more replies" rows,
// so CommentTreeBuilder must not drop kind=="more" objects ---
let moreJSON = """
[
  {"kind":"t1","data":{"id":"m1","name":"t1_m1","author":"a1","body":"top",
    "score":1,"created_utc":0,"parent_id":"t3_x","link_id":"t3_x","saved":false,
    "score_hidden":false,"stickied":false,
    "replies":{"kind":"Listing","data":{"children":[
      {"kind":"more","data":{"id":"abc","count":5,"children":["c4","c5","c6","c7","c8"]}}
    ]}}}},
  {"kind":"more","data":{"id":"xyz","count":3,"children":["c9","c10","c11"]}}
]
""".data(using: .utf8)!
let moreJSONValues = try! JSONDecoder().decode([JSONValue].self, from: moreJSON)
let moreBuild = CommentTreeBuilder.buildRoots(from: moreJSONValues, postFullname: "t3_x")
check("buildRoots returns the one real t1 node (more-kind sibling excluded from roots)", moreBuild.roots.count == 1)
check("nested 'more' stub attached to its parent node", moreBuild.roots.first?.moreStub?.count == 5)
check("nested 'more' stub has the right parent fullname for /api/morechildren's link_id", moreBuild.roots.first?.moreStub?.parentID == "t1_m1")
check("nested 'more' stub carries the real child ids to resolve", moreBuild.roots.first?.moreStub?.children == ["c4", "c5", "c6", "c7", "c8"])
check("root-level trailing 'more' stub surfaced separately from nested ones", moreBuild.moreStub?.count == 3)
check("root-level 'more' stub uses the post fullname as its parent id", moreBuild.moreStub?.parentID == "t3_x")

let plainBuild = CommentTreeBuilder.build(from: moreJSONValues)
check("plain build(from:) still returns only real t1 nodes, more-kind siblings dropped from the array", plainBuild.count == 1)

check("visibleFlattenedWithMore yields the comment then its nested more-stub inline", moreBuild.roots.first?.visibleFlattenedWithMore().map(\.id) == ["m1", "t1_abc"])

let resolvedNode = moreBuild.roots.first!.resolvingMoreStub(stubID: "t1_abc", with: [CommentTreeNode(comment: makeComment(id: "c4"), depth: 1)])
check("resolvingMoreStub splices real children in and clears the stub", resolvedNode.moreStub == nil && resolvedNode.children.count == 1 && resolvedNode.children[0].comment.id == "c4")

// Reddit's /api/morechildren response is a flat array with no nested
// `replies`, so resolving a "more replies" stub rebuilds the tree from each
// comment's own parent_id, starting at the stub's depth.
let flatMoreJSON = """
[
  {"kind":"t1","data":{"id":"r1","name":"t1_r1","author":"a1","body":"first level",
    "score":1,"created_utc":0,"parent_id":"t1_parent","link_id":"t3_x","saved":false,
    "score_hidden":false,"stickied":false}},
  {"kind":"t1","data":{"id":"r2","name":"t1_r2","author":"a2","body":"second level",
    "score":1,"created_utc":0,"parent_id":"t1_r1","link_id":"t3_x","saved":false,
    "score_hidden":false,"stickied":false}},
  {"kind":"t1","data":{"id":"r3","name":"t1_r3","author":"a3","body":"third level",
    "score":1,"created_utc":0,"parent_id":"t1_r2","link_id":"t3_x","saved":false,
    "score_hidden":false,"stickied":false}}
]
""".data(using: .utf8)!
let flatMoreJSONValues = try! JSONDecoder().decode([JSONValue].self, from: flatMoreJSON)
let resolvingStub = MoreStub(id: "t1_stub", count: 3, children: ["r1", "r2", "r3"], parentID: "t1_parent", depth: 2)
let resolvedBuild = CommentTreeBuilder.buildResolved(from: flatMoreJSONValues, stub: resolvingStub)
check("buildResolved reconstructs exactly one real root from the flat batch (r2/r3 are nested under r1, not siblings)", resolvedBuild.roots.count == 1)
check("buildResolved's root is the actual shallowest comment (r1), not just array order", resolvedBuild.roots.first?.comment.id == "r1")
check("buildResolved starts depth at the stub's own depth, not always 0", resolvedBuild.roots.first?.depth == 2)
check("buildResolved nests r2 one level below the stub's depth", resolvedBuild.roots.first?.children.first?.comment.id == "r2" && resolvedBuild.roots.first?.children.first?.depth == 3)
check("buildResolved nests r3 two levels below the stub's depth (real multi-level reconstruction, not flat siblings)", resolvedBuild.roots.first?.children.first?.children.first?.comment.id == "r3" && resolvedBuild.roots.first?.children.first?.children.first?.depth == 4)
// --- RedGifs ID extraction (media pipeline) ---
let redgifsWatchURL = URL(string: "https://www.redgifs.com/watch/abcxyz")!
check("extracts redgifs ID from watch URL", RedGifsClient.extractID(from: redgifsWatchURL) == "abcxyz")

let redgifsDirectURL = URL(string: "https://i.redgifs.com/i/abcxyz.mp4")!
check("extracts redgifs ID from direct media URL", RedGifsClient.extractID(from: redgifsDirectURL) == "abcxyz")

let nonRedgifsURL = URL(string: "https://example.com/watch/abcxyz")!
check("returns nil for non-redgifs URL", RedGifsClient.extractID(from: nonRedgifsURL) == nil)

// --- Apollo regex edge cases (base app behaviour, not just Reborn) ---
let redgifsCDNURL = URL(string: "https://thumbs2.redgifs.com/SomeSlugName-mobile.mp4")!
check("extracts redgifs ID from a numbered CDN subdomain + trailing slug (real regex)", RedGifsClient.extractID(from: redgifsCDNURL) == "SomeSlugName")

let gfycatURL = URL(string: "https://gfycat.com/watch/somegfyid")!
check("GfycatURLParser extracts an ID from a legacy gfycat.com/watch/ URL", GfycatURLParser.extractID(from: gfycatURL) == "somegfyid")
check("GfycatURLParser returns nil for a non-gfycat URL", GfycatURLParser.extractID(from: nonRedgifsURL) == nil)
check("InlineMediaDetector classifies a gfycat URL as .gfycat", InlineMediaDetector.classify(gfycatURL) == .gfycat(id: "somegfyid"))

let streamableEditURL = URL(string: "https://streamable.com/edit/moo")!
check("StreamableClient.extractID handles the real /edit/<id> creator-link variant", StreamableClient.extractID(from: streamableEditURL) == "moo")

check("ImgurClient.extractAlbumID also recognizes the imgur.io TLD", ImgurClient.extractAlbumID(from: URL(string: "https://imgur.io/a/AbCdEfG")!) == "AbCdEfG")
check("ImgurClient.matchesImgurHost recognizes a t/<tag>/ prefixed link", ImgurClient.matchesImgurHost(URL(string: "https://imgur.com/t/aww/abc123")!))

/// The two third-party round-trips below run only with SMOKE_LIVE=1, so an
/// offline run does not count their failure.
let runsLiveChecks = ProcessInfo.processInfo.environment["SMOKE_LIVE"] == "1"
// --- v.redd.it native video media decoding ---
let redditVideoJSON = """
{"reddit_video": {"fallback_url": "https://v.redd.it/abc123/DASH_720.mp4", "hls_url": "https://v.redd.it/abc123/HLSPlaylist.m3u8", "is_gif": false}}
""".data(using: .utf8)!
let media = try! JSONDecoder().decode(RedditMedia.self, from: redditVideoJSON)
check("decodes reddit_video fallback_url", media.redditVideo?.fallbackURL == "https://v.redd.it/abc123/DASH_720.mp4")
check("decodes reddit_video hls_url", media.redditVideo?.hlsURL == "https://v.redd.it/abc123/HLSPlaylist.m3u8")
// --- Auto-collapse child comments (CommentTreeBuilder) ---
let nestedCommentJSON = """
[{"kind": "t1", "data": {"id": "c1", "name": "t1_c1", "author": "a", "body": "top", "score": 1,
  "created_utc": 0, "parent_id": "t3_x", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false,
  "replies": {"kind": "Listing", "data": {"children": [
    {"kind": "t1", "data": {"id": "c2", "name": "t1_c2", "author": "b", "body": "reply", "score": 1,
      "created_utc": 0, "parent_id": "t1_c1", "link_id": "t3_x", "saved": false, "score_hidden": false, "stickied": false}}
  ]}}}}]
""".data(using: .utf8)!
let nestedValues = try! JSONDecoder().decode([JSONValue].self, from: nestedCommentJSON)
let collapsedTree = CommentTreeBuilder.build(from: nestedValues, autoCollapse: true)
// Stock "Auto collapse replies to top-level comments": the top-level
// comment stays open and its replies fold.
check("autoCollapse keeps top-level comments open and folds their replies",
      collapsedTree.first?.isCollapsed == false && collapsedTree.first?.children.first?.isCollapsed == true)
let uncollapsedTree = CommentTreeBuilder.build(from: nestedValues, autoCollapse: false)
check("autoCollapse: false leaves top-level comments expanded", uncollapsedTree.first?.isCollapsed == false)
// --- Modmail conversation subreddit name ---
let modmailJSON = """
{
    "id": "abc123", "subject": "Test conversation", "state": 0,
    "lastUpdated": "2024-01-01T00:00:00Z", "isAuto": false, "numMessages": 2,
    "owner": {"displayName": "swift"}
}
""".data(using: .utf8)!
let modmailConvo = try! JSONDecoder().decode(ModmailConversation.self, from: modmailJSON)
check("decodes modmail owner.displayName as subredditName", modmailConvo.subredditName == "swift")

let modmailNoOwnerJSON = """
{
    "id": "abc456", "subject": "No owner", "state": 0,
    "lastUpdated": null, "isAuto": false, "numMessages": 1
}
""".data(using: .utf8)!
let modmailNoOwner = try! JSONDecoder().decode(ModmailConversation.self, from: modmailNoOwnerJSON)
check("modmail conversation without owner decodes nil subredditName", modmailNoOwner.subredditName == nil)
// --- Gallery View post filtering (Reborn feature) ---
let imagePostJSON = """
{
    "id": "img1", "name": "t3_img1", "title": "Image Post",
    "author": "u1", "subreddit": "test", "selftext": "",
    "url": "https://example.com/photo.jpg", "permalink": "/r/test/comments/img1/x/",
    "score": 1, "upvote_ratio": 1.0, "num_comments": 0,
    "created_utc": 0, "is_self": false, "over_18": false,
    "spoiler": false, "stickied": false, "saved": false, "likes": null
}
""".data(using: .utf8)!
let imagePost = try! JSONDecoder.reddit.decode(RedditPost.self, from: imagePostJSON)
check("GalleryPostMedia.thumbnailURL finds a direct image post's own URL", GalleryPostMedia.thumbnailURL(for: imagePost) == URL(string: "https://example.com/photo.jpg"))

let textPostJSON = """
{
    "id": "txt1", "name": "t3_txt1", "title": "Text Post",
    "author": "u1", "subreddit": "test", "selftext": "just text",
    "url": null, "permalink": "/r/test/comments/txt1/x/",
    "score": 1, "upvote_ratio": 1.0, "num_comments": 0,
    "created_utc": 0, "is_self": true, "over_18": false,
    "spoiler": false, "stickied": false, "saved": false, "likes": null
}
""".data(using: .utf8)!
let textPost = try! JSONDecoder.reddit.decode(RedditPost.self, from: textPostJSON)
check("GalleryPostMedia.thumbnailURL returns nil for a text post", GalleryPostMedia.thumbnailURL(for: textPost) == nil)
let filteredGalleryPosts = GalleryPostMedia.filterMediaPosts([imagePost, textPost])
check("GalleryPostMedia.filterMediaPosts keeps only posts with media", filteredGalleryPosts.count == 1 && filteredGalleryPosts.first?.id == imagePost.id)
// --- WebSessionCredential / Web JSON transport (Reborn's OAuth-free
// sign-in flow) ---
let webSession = WebSessionCredential(username: "TestUser", cookieHeader: "reddit_session=abc; token_v2=xyz", modhash: "modhash123")
check("WebSessionCredential lowercases the username", webSession.username == "testuser")
check("WebSessionCredential with a modhash is not read-only", webSession.isReadOnly == false)
let readOnlySession = WebSessionCredential(username: "testuser", cookieHeader: "reddit_session=abc", modhash: nil)
check("WebSessionCredential with no modhash matches the real read-only state", readOnlySession.isReadOnly == true)

let webSessionStore = InMemoryWebSessionStore()
try? webSessionStore.save(webSession)
check("WebSessionStore round-trips a saved session", webSessionStore.load() == webSession)
webSessionStore.clear()
check("WebSessionStore.clear() removes the session", webSessionStore.load() == nil)

do {
    let authClient = RedditAuthClient(credentialStore: InMemoryCredentialStore(), webSessionStore: InMemoryWebSessionStore())
    let isSignedInBefore = await authClient.isSignedIn
    check("RedditAuthClient starts signed out with no OAuth credential or web session", isSignedInBefore == false)
    await authClient.setWebSession(webSession)
    let isSignedInAfter = await authClient.isSignedIn
    check("RedditAuthClient.isSignedIn is true after setWebSession (real Reborn 'account synthesis' parity)", isSignedInAfter == true)
    let storedSession = await authClient.webSession
    check("RedditAuthClient exposes the stored web session", storedSession == webSession)
    await authClient.signOut()
    let isSignedInAfterSignOut = await authClient.isSignedIn
    check("RedditAuthClient.signOut() clears the web session too", isSignedInAfterSignOut == false)
}

check("PureBlackSettings.default has everything off", PureBlackSettings.default == PureBlackSettings(isEnabled: false, isPurerEnabled: false, reduceSmearing: false))
PureBlackSettingsStore.save(PureBlackSettings(isEnabled: true, isPurerEnabled: true, reduceSmearing: true))
check("PureBlackSettingsStore round-trips a saved selection", PureBlackSettingsStore.load() == PureBlackSettings(isEnabled: true, isPurerEnabled: true, reduceSmearing: true))
PureBlackSettingsStore.save(.default)
check("PureBlackSettingsStore round-trips back to default", PureBlackSettingsStore.load() == PureBlackSettings.default)

check("FavoriteSubredditsStore starts empty", FavoriteSubredditsStore.load().isEmpty)
// MARK: - Row-swipe / navigation mutual exclusivity
//
// `navigationClaimsTouch` is the single arbiter between navigation and row
// swipes, and it is directional: only touches navigation takes are withheld
// from the row.

let screen = 393.0

check("navigation claims a rightward drag from the leading edge",
      PushPopGesturePolicy.navigationClaimsTouch(startX: 20, velocityX: 400, velocityY: 30, viewWidth: screen))
check("navigation claims a leftward drag from the trailing edge",
      PushPopGesturePolicy.navigationClaimsTouch(startX: 380, velocityX: -400, velocityY: 30, viewWidth: screen))

// A leftward drag inside the wide 70pt back inset is not a back swipe, so
// the row keeps it.
check("a LEFTWARD drag in the leading inset is left to the row",
      !PushPopGesturePolicy.navigationClaimsTouch(startX: 20, velocityX: -400, velocityY: 30, viewWidth: screen))
check("a RIGHTWARD drag in the trailing inset is left to the row",
      !PushPopGesturePolicy.navigationClaimsTouch(startX: 380, velocityX: 400, velocityY: 30, viewWidth: screen))
check("a mid-row drag is always left to the row",
      !PushPopGesturePolicy.navigationClaimsTouch(startX: 200, velocityX: -400, velocityY: 30, viewWidth: screen))
check("a vertical drag at the edge is left to the row (and the scroll view)",
      !PushPopGesturePolicy.navigationClaimsTouch(startX: 20, velocityX: 40, velocityY: 800, viewWidth: screen))
check("a lazy diagonal at the edge is not claimed by navigation",
      !PushPopGesturePolicy.navigationClaimsTouch(startX: 20, velocityX: 120, velocityY: 100, viewWidth: screen))

// Navigation and the row never both claim one touch, in either edge zone
// or either direction.
for startX in [5.0, 20.0, 69.0, 200.0, 353.0, 380.0, 392.0] {
    for vx in [-600.0, -200.0, 200.0, 600.0] {
        let claimed = PushPopGesturePolicy.navigationClaimsTouch(
            startX: startX, velocityX: vx, velocityY: 20, viewWidth: screen)
        let back = PushPopGesturePolicy.shouldBeginBack(velocityX: vx, velocityY: 20, locationX: startX)
        let forward = PushPopGesturePolicy.shouldBeginForward(
            velocityX: vx, velocityY: 20, locationX: startX, viewWidth: screen)
        check("claim at x=\(Int(startX)) vx=\(Int(vx)) matches exactly one navigation gesture",
              claimed == (back || forward))
        check("back and forward never both claim x=\(Int(startX)) vx=\(Int(vx))",
              !(back && forward))
    }
}

check("the real insets stay asymmetric (back is the wider, common gesture)",
      PushPopGesturePolicy.leftInset == 70 && PushPopGesturePolicy.rightInset == 40)
// MARK: - Subreddit Sections live preview
//
// Mirrors Reborn's subreddit-sections preview state: sample names, colors,
// bands and heights are specified exactly.
let sectionsDefault = SubredditSectionsSettings.default
let sectionsBlocks = SubredditSectionsPreview.blocks(for: sectionsDefault)

check("the preview ends where the A-Z list picks up, at the U band",
      sectionsBlocks.contains { $0.key == "band.letter" && $0.title == "U" })
check("the real sample rows are present with their real names",
      sectionsBlocks.contains { $0.title == "apolloapp" }
        && sectionsBlocks.contains { $0.title == "My Multireddit" }
        && sectionsBlocks.contains { $0.title == "modclub" }
        && sectionsBlocks.contains { $0.title == "ukulele" })
check("only the favorites sample is starred",
      sectionsBlocks.filter(\.starred).map(\.key) == ["row.apolloapp"])

// The sample followed user keeps the same key in both placements, so it
// slides between the FOLLOWING band and the U letter band instead of
// vanishing and reappearing.
var sectionsSeparate = sectionsDefault
sectionsSeparate.separateFollowedUsers = true
let separateBlocks = SubredditSectionsPreview.blocks(for: sectionsSeparate)
check("with separation off there is no FOLLOWING band",
      !sectionsBlocks.contains { $0.key == "band.following" })
check("...and the followed user sits after the letter band",
      sectionsBlocks.firstIndex(where: { $0.key == "row.username" })
        ?? 0 > (sectionsBlocks.firstIndex(where: { $0.key == "band.letter" }) ?? 0))
check("with separation on the FOLLOWING band appears",
      separateBlocks.contains { $0.key == "band.following" })
check("...and the followed user moves ABOVE the letter band",
      (separateBlocks.firstIndex(where: { $0.key == "row.username" }) ?? 99)
        < (separateBlocks.firstIndex(where: { $0.key == "band.letter" }) ?? 0))
check("the followed user's key is identical in both placements, so it slides",
      separateBlocks.filter { $0.key == "row.username" }.count == 1
        && sectionsBlocks.filter { $0.key == "row.username" }.count == 1)

// Subtitle rule and the height it implies.
var sectionsHidden = sectionsDefault
sectionsHidden.hideMultiredditDescriptions = true
let hiddenBlocks = SubredditSectionsPreview.blocks(for: sectionsHidden)
check("the multireddit sample lists its subreddits by default",
      sectionsBlocks.first { $0.key == "row.multireddit" }?.subtitle == "apolloapp, ios, swift")
check("...and drops them when descriptions are hidden",
      hiddenBlocks.first { $0.key == "row.multireddit" }?.subtitle == nil)
check("a row WITH a subtitle is the taller 40pt detail row",
      sectionsBlocks.first { $0.key == "row.multireddit" }?.height == 40)
check("...and without one it is the 30pt row",
      hiddenBlocks.first { $0.key == "row.multireddit" }?.height == 30)
check("a signature change is what marks the multireddit row for a cross-fade",
      sectionsBlocks.first { $0.key == "row.multireddit" }?.signature
        != hiddenBlocks.first { $0.key == "row.multireddit" }?.signature)

// Height math: two paddings, every block, and spacing between blocks only,
// not a trailing one.
let twoBlocks = Array(sectionsBlocks.prefix(2))
check("height is padding + blocks + inter-block spacing only",
      SubredditSectionsPreview.height(of: twoBlocks)
        == 2 * 8 + twoBlocks[0].height + twoBlocks[1].height + 3)
check("a single block gets no spacing at all",
      SubredditSectionsPreview.height(of: [sectionsBlocks[0]]) == 2 * 8 + sectionsBlocks[0].height)

// Reordering the sections must reorder the preview.
var sectionsReordered = sectionsDefault
sectionsReordered.order = [.moderator, .favorites, .multireddits, .following]
let reorderedBlocks = SubredditSectionsPreview.blocks(for: sectionsReordered)
check("reordering the sections reorders the preview's bands",
      reorderedBlocks.first?.key == "band.moderator")
// MARK: - Modmail conversation detail

// Response envelope: `conversation`, `messages`, `modActions`. Messages
// arrive as an unordered dictionary; the conversation's own objIds list is
// the only source of display order.
let modmailDetailJSON = """
{
  "conversation": {
    "id": "abc123",
    "subject": "Ban appeal",
    "numMessages": 3,
    "state": 1,
    "isHighlighted": true,
    "isArchived": false,
    "lastUnread": "2025-01-02T03:04:05.000+0000",
    "isRepliable": true,
    "owner": { "displayName": "apolloapp" },
    "participant": { "name": "someuser" },
    "objIds": [
      { "id": "m3", "key": "messages" },
      { "id": "m1", "key": "messages" },
      { "id": "mod1", "key": "modActions" },
      { "id": "m2", "key": "messages" }
    ]
  },
  "messages": {
    "m1": { "id": "m1", "bodyMarkdown": "second shown", "date": "2025-01-01T10:00:00.000+0000",
            "author": { "name": "someuser", "isMod": false, "isAuthorHidden": false } },
    "m2": { "id": "m2", "bodyMarkdown": "third shown", "isInternal": true,
            "author": { "name": "amod", "isMod": true, "isAuthorHidden": false } },
    "m3": { "id": "m3", "bodyMarkdown": "first shown",
            "author": { "name": "hidden", "isMod": false, "isAuthorHidden": true } }
  }
}
"""
let modmailDetail = try! ModmailConversationDetail.decode(from: Data(modmailDetailJSON.utf8))

// A dictionary has no order, so decoding `messages` alone and showing
// `.values` would render the thread differently on every launch.
check("messages are ordered by the conversation's own objIds, not dictionary order",
      modmailDetail.messages.map(\.id) == ["m3", "m1", "m2"])
check("...and objIds entries that are NOT messages are skipped",
      !modmailDetail.messages.contains { $0.id == "mod1" })

// The key is bodyMarkdown, not body.
check("the real bodyMarkdown key is read",
      modmailDetail.messages.first?.body == "first shown")
check("the internal-note flag is decoded",
      modmailDetail.messages.first { $0.id == "m2" }?.isInternal == true)
check("...and a normal reply is not marked internal",
      modmailDetail.messages.first { $0.id == "m1" }?.isInternal == false)
check("a hidden author is flagged rather than silently shown",
      modmailDetail.messages.first { $0.id == "m3" }?.author?.isHidden == true)
check("a moderator author is flagged",
      modmailDetail.messages.first { $0.id == "m2" }?.author?.isMod == true)

// Conversation-level state that drives the quick actions.
check("highlight state is decoded",
      modmailDetail.conversation.isHighlighted && !modmailDetail.conversation.isArchived)
check("unread is derived from lastUnread being PRESENT, not a boolean",
      modmailDetail.conversation.isUnread)
check("the participant and subreddit are decoded",
      modmailDetail.conversation.participantName == "someuser"
        && modmailDetail.conversation.subredditName == "apolloapp")

// Date format is pinned to en_US_POSIX so a non-Gregorian device calendar
// cannot break it.
check("the real yyyy-MM-dd'T'HH:mm:ss.SSSZ date format parses",
      modmailDetail.messages.first { $0.id == "m1" }?.parsedDate != nil)

// isRepliable defaults TRUE when absent: defaulting false would hide the
// reply box on every conversation whose response omits it.
let modmailMinimal = """
{"conversation":{"id":"x","subject":"s"},"messages":{}}
"""
let minimalDetail = try! ModmailConversationDetail.decode(from: Data(modmailMinimal.utf8))
check("an absent isRepliable means REPLIABLE, so the reply box is not wrongly hidden",
      minimalDetail.conversation.isRepliable)
check("an absent lastUnread means read",
      !minimalDetail.conversation.isUnread)
check("a conversation with no messages decodes rather than throwing",
      minimalDetail.messages.isEmpty)

// A message Reddit returned but did not list stays visible.
let modmailOrphan = """
{"conversation":{"id":"x","subject":"s","objIds":[]},
 "messages":{"z1":{"id":"z1","bodyMarkdown":"orphan"}}}
"""
let orphanDetail = try! ModmailConversationDetail.decode(from: Data(modmailOrphan.utf8))
check("a message missing from objIds is still shown, not silently dropped",
      orphanDetail.messages.map(\.id) == ["z1"])

// On a cookie/web-session account the modmail request 403s and returns
// www.reddit.com's HTML forbidden page, because the cookie transport
// rewrites oauth.reddit.com -> www.reddit.com where /api/mod/conversations
// does not exist. New modmail is OAuth-only. It surfaces as its own error so
// a web-session user is not told to retry something that cannot succeed.
check("the OAuth-only modmail error explains the sign-in method, not a transient failure",
      RedditRepository.ModmailRequiresOAuthError().errorDescription?.contains("API-key sign-in") == true)
// MARK: - Native modmail over a web session
//
// These decode captured Reddit responses in Tests/Fixtures/ rather than
// hand-written JSON, so they prove the decoder matches Reddit.

func fixture(_ name: String) -> Data {
    let candidates = [
        "Tests/Fixtures/\(name)",
        FileManager.default.currentDirectoryPath + "/Tests/Fixtures/\(name)",
    ]
    for path in candidates {
        if let data = FileManager.default.contents(atPath: path) { return data }
    }
    return Data()
}

let convFixture = fixture("modmail-conversations-v2.json")
check("the live modmail conversations fixture is present", !convFixture.isEmpty)
if !convFixture.isEmpty,
   let convJSON = (try? JSONSerialization.jsonObject(with: convFixture)) as? [String: Any] {
    let conversations = (try? ModmailWebService.decodeConversations(from: convJSON)) ?? []
    check("the live modmail listing decodes", conversations.count == 1)
    if let first = conversations.first {
        // The prefix is required: every mutation needs it, and a bare id is
        // rejected.
        check("the conversation id keeps its GraphQL prefix",
              first.id == "ModmailConversation_3q3cd2")
        check("...and exposes the bare id for display", first.bareID == "3q3cd2")
        check("the real subject decodes", first.subject == "Modmail test")
        check("the owning subreddit decodes", first.subredditName == "examplesub")
        check("the inline last message decodes",
              first.lastMessageMarkdown?.hasPrefix("Test message to verify") == true)
        // Reddit's `2026-09-14T13:53:06.414000+0000` needs .withFractionalSeconds;
        // a default ISO8601DateFormatter returns nil and rows would sort as undated.
        check("microsecond timestamps with a +0000 offset parse",
              first.lastModUpdateAt != nil)
        check("a conversation with lastUnreadAt is unread", first.isUnread)
        // A mod messaging their own subreddit produces an internal conversation,
        // visible only in MOD_DISCUSSIONS.
        check("a mod-to-own-subreddit conversation is INTERNAL", first.type == "INTERNAL")
    }
}

let threadFixture = fixture("modmail-messages-and-actions.json")
check("the live modmail thread fixture is present", !threadFixture.isEmpty)
if !threadFixture.isEmpty,
   let threadJSON = (try? JSONSerialization.jsonObject(with: threadFixture)) as? [String: Any] {
    let entries = (try? ModmailWebService.decodeThread(from: threadJSON)) ?? []
    // The thread is 1 message + 2 mod actions; a message-only model would
    // render one third of it.
    check("messages AND mod actions both decode", entries.count == 3)
    check("...exactly one of them is a message", entries.filter(\.isMessage).count == 1)
    check("...and two are mod actions", entries.filter { !$0.isMessage }.count == 2)
    if let message = entries.first(where: \.isMessage) {
        check("the message body markdown decodes",
              message.markdown?.hasPrefix("Test message to verify") == true)
        check("the message author decodes", message.authorName == "example_mod")
        // A mod-discussion message is internal and shown differently, since
        // mistaking a private mod note for a user-visible reply is the costly
        // error.
        check("a mod discussion message is internal", message.isInternal)
    }
    if case .action(let type)? = entries.last?.kind {
        check("the newest action is the UNHIGHLIGHT we performed", type == "UNHIGHLIGHTED")
    } else {
        check("the newest action is the UNHIGHLIGHT we performed", false)
    }
    // Reddit returns newest-first; a thread must read oldest-first.
    let dates = entries.compactMap(\.createdAt)
    check("thread entries are sorted oldest-first", dates == dates.sorted())
}

// The archive trap: Reddit answers ok:true / errors:null and does nothing;
// the refusal is a BAD_REQUEST warning in `extensions`. Highlight/read
// return no warning and take effect.
let archiveFallback: [String: Any] = [
    "data": ["setModmailConversationsArchiveStatus": ["ok": true, "errors": NSNull()]],
    "extensions": ["warnings": [["message": "Fallback value returned",
                                 "extensions": ["code": "BAD_REQUEST"]]]],
]
check("a fallback 'ok: true' still surfaces its BAD_REQUEST warning",
      ModmailWebService.warningCode(in: archiveFallback) == "BAD_REQUEST")
let genuineSuccess: [String: Any] = [
    "data": ["setModmailConversationsHighlightStatus": ["ok": true, "errors": NSNull()]],
    "extensions": ["traceID": "abc"],
]
check("a genuine success carries no warning",
      ModmailWebService.warningCode(in: genuineSuccess) == nil)

// Ids are prefixed for every mutation, and prefixing twice does not
// corrupt an already-prefixed id.
check("a bare conversation id gets prefixed",
      ModmailWebService.prefixed("3q3cd2") == "ModmailConversation_3q3cd2")
check("an already-prefixed id is left alone",
      ModmailWebService.prefixed("ModmailConversation_3q3cd2") == "ModmailConversation_3q3cd2")

// Apollo's 5 tabs map onto Reddit's GraphQL enum, which is not the same as
// uppercasing the REST `state` string.
check("the Mod Discussions tab maps to MOD_DISCUSSIONS",
      ModmailWebService.MailboxCategory(tab: .modDiscussions) == .modDiscussions)
check("...whose GraphQL value differs from the REST state 'mod'",
      ModmailWebService.MailboxCategory(tab: .modDiscussions).rawValue == "MOD_DISCUSSIONS"
        && ModmailInboxTab.modDiscussions.apiState == "mod")
check("the In Progress tab maps to IN_PROGRESS",
      ModmailWebService.MailboxCategory(tab: .inProgress).rawValue == "IN_PROGRESS")

// Reddit throttles modmail by answering HTTP 200 with a "Prove your
// humanity" page and `Retry-After`, not a 429. This reads as a transient,
// retryable condition rather than a parse failure.
let rateLimited = ModmailWebService.ServiceError.rateLimited(retryAfterSeconds: 30)
check("a throttled modmail call names the wait, not a parse failure",
      rateLimited.errorDescription?.contains("30s") == true)
check("...and still reads as rate limiting when Reddit omits a duration",
      ModmailWebService.ServiceError.rateLimited(retryAfterSeconds: nil)
        .errorDescription?.contains("rate limiting") == true)
check("a throttle is distinct from an unreadable reply",
      rateLimited != ModmailWebService.ServiceError.malformedResponse)

// Reddit sends `Retry-After: 0` for this throttle. Honouring it literally
// retries instantly and burns every attempt inside the window, so the
// header is a floor, not a promise.
func modmailBackoff(attempt: Int, retryAfter: Int?) -> Double {
    max(Double(retryAfter ?? 0), pow(2.0, Double(attempt)) * 1.5)
}
check("a Retry-After of 0 still waits", modmailBackoff(attempt: 0, retryAfter: 0) >= 1.5)
check("...and backs off further on later attempts",
      modmailBackoff(attempt: 2, retryAfter: 0) > modmailBackoff(attempt: 0, retryAfter: 0))
check("...while a longer Retry-After from Reddit still wins",
      modmailBackoff(attempt: 0, retryAfter: 30) == 30)

// Reddit pages the thread connection at 25 newest-first, counting mod
// actions alongside messages. A conversation with one message and 25+
// actions pushes the only message off page 1, so the thread must keep
// paging until messages are found.
let actionHeavy: [String: Any] = [
    "data": ["modmailFullConversation": ["messagesAndActions": [
        "edges": (0..<25).map { index in
            ["node": ["__typename": "ModmailAction", "id": "ModmailAction_\(index)",
                      "actionType": "HIGHLIGHTED",
                      "createdAt": "2026-09-14T13:5\(index % 10):00.000000+0000"]]
        }
    ]]]
]
let actionsOnly = (try? ModmailWebService.decodeThread(from: actionHeavy)) ?? []
check("a thread page of pure mod actions decodes without inventing messages",
      actionsOnly.count == 25 && actionsOnly.allSatisfy { !$0.isMessage })

// The modmail inbox has exactly three controls: a title-view mailbox
// switcher button, a sort button, and a more-options button (no segmented
// control).
check("modmail mailboxes are menu items, so full titles always fit",
      ModmailInboxTab.allCases.allSatisfy { !$0.title.isEmpty })
check("...and Mod Discussions keeps its full name, not 'Mod Dis...'",
      ModmailInboxTab.modDiscussions.title == "Mod Discussions")

// All five sort orders, not just recent/unread.
check("all five real modmail sort orders exist",
      ModmailSortOption.allCases.count == 5)
check("...including the three the reconstruction missed",
      Set(ModmailSortOption.allCases.map(\.rawValue))
        .isSuperset(of: ["mod", "user", "relevance"]))
check("sort maps onto the real GraphQL enum",
      ModmailSortOption.recent.graphQLValue == "RECENT"
        && ModmailSortOption.unread.graphQLValue == "UNREAD")
// RELEVANCE is search-only in Reddit's client; sending it for a plain
// mailbox listing 500s, so it falls back.
check("relevance falls back to RECENT for a plain listing",
      ModmailSortOption.relevance.graphQLValue == "RECENT")

// Apollo ships 189 distinct `option-*` menu icons, one per action, which
// gives menus their at-a-glance distinction between sorts and votes.
check("each modmail sort carries its own real Apollo icon name",
      Set(ModmailSortOption.allCases.map(\.apolloIconName)).count
        == ModmailSortOption.allCases.count)
check("the unread sort uses Apollo's real option-sort-unread",
      ModmailSortOption.unread.apolloIconName == "option-sort-unread")
check("relevance uses Apollo's real option-sort-relevance",
      ModmailSortOption.relevance.apolloIconName == "option-sort-relevance")

// The four autoplay modes. "WiFi Only" keeps GIFs off cellular data, so
// the setting cannot be a boolean.
check("all four real GIF autoplay modes exist",
      InlineGIFAutoplayMode.allCases.count == 4)
check("...in the real sheet's order, Always/WiFi Only/Tap to Play/Never",
      InlineGIFAutoplayMode.realOrder.map(\.displayName)
        == ["Always", "WiFi Only", "Tap to Play", "Never"])
check("only Tap to Play and Never hold a GIF behind a play button",
      InlineGIFAutoplayMode.allCases.filter(\.requiresTapToPlay) == [.tapToPlay, .never])

// A stored `tapToPlayGIFs: true` means "Tap to Play" and migrates rather
// than resetting the preference.
let legacyOn = Data(#"{"enabled":true,"alignment":"center","size":100,"tapToPlayGIFs":true}"#.utf8)
let migratedOn = try? JSONDecoder().decode(InlineMediaSettings.self, from: legacyOn)
check("a legacy tapToPlayGIFs=true migrates to .tapToPlay",
      migratedOn?.autoplayMode == .tapToPlay)
let legacyOff = Data(#"{"enabled":true,"alignment":"center","size":100,"tapToPlayGIFs":false}"#.utf8)
let migratedOff = try? JSONDecoder().decode(InlineMediaSettings.self, from: legacyOff)
check("a legacy tapToPlayGIFs=false migrates to .always", migratedOff?.autoplayMode == .always)
// Round-trip, and keep writing the legacy key so an older build can read
// the file instead of reverting to autoplay.
if let encoded = try? JSONEncoder().encode(migratedOn),
   let text = String(data: encoded, encoding: .utf8) {
    check("the legacy tapToPlayGIFs key is still written for back-compat",
          text.contains("tapToPlayGIFs"))
    let round = try? JSONDecoder().decode(InlineMediaSettings.self, from: encoded)
    check("...and the four-mode value round-trips", round?.autoplayMode == .tapToPlay)
}

// Size is a detent slider in Reborn (ApolloIMDetentSlider), snapping to
// 50/75/100.
check("a dragged slider value snaps to the nearest real detent",
      InlineMediaSize.snapped(to: 61) == .small
        && InlineMediaSize.snapped(to: 70) == .medium
        && InlineMediaSize.snapped(to: 99) == .large)

// Apollo has three separate moderator user-list controllers, reached as
// three separate menu rows.
check("the three moderator user lists are separate, titled destinations",
      Set(ModeratorUserList.allCases.map(\.title)).count == 3)
check("...each with its own real Apollo icon name",
      Set(ModeratorUserList.allCases.map(\.apolloIconName)).count == 3)
// Search sorts include "relevance" and "comments", which the feed's
// enumerated arm does not list; they resolve through the shared table of
// option-sort-* names. If that fallback stopped resolving they would render
// the generic arrow.
check("the real option-sort-relevance icon resolves",
      ApolloMenuIcon.symbol("option-sort-relevance") != nil)
check("the real option-sort-comments icon resolves",
      ApolloMenuIcon.symbol("option-sort-comments") != nil)
// Icons with known values keep them rather than name-derived guesses.
check("Best stays the trophy seen in reference-screenshots/sort.png",
      ApolloMenuIcon.symbol("option-sort-best") == "trophy")
check("Hot stays the droplet seen in the same screenshot",
      ApolloMenuIcon.symbol("option-sort-hot") == "drop")
check("Controversial stays the crossed arrows, not a bolt",
      ApolloMenuIcon.symbol("option-sort-controversial") == "scissors")
// An unmapped name returns nil so a caller falls back deliberately rather
// than rendering a wrong glyph.
check("an unmapped icon name returns nil rather than a wrong glyph",
      ApolloMenuIcon.symbol("option-sort-not-a-real-name") == nil)
// Subreddit header spacing: Reddit returns `banner_background_image: ""`
// for a subreddit with no banner, not null, so `URL(string: "")` is nil and
// the banner never draws. The -20pt overlap and zeroed top inset key off a
// usable URL rather than the setting, or a bannerless subreddit would be
// pulled up and clipped against the nav bar.
func headerBannerURL(showBanner: Bool, raw: String?) -> URL? {
    guard showBanner,
          let trimmed = raw?.trimmingCharacters(in: .whitespaces),
          !trimmed.isEmpty else { return nil }
    return URL(string: trimmed)
}
check("an empty banner string yields no banner (Reddit sends \"\", not null)",
      headerBannerURL(showBanner: true, raw: "") == nil)
check("...as does a whitespace-only one",
      headerBannerURL(showBanner: true, raw: "   ") == nil)
check("...and a missing key",
      headerBannerURL(showBanner: true, raw: nil) == nil)
check("a real banner URL still resolves",
      headerBannerURL(showBanner: true, raw: "https://styles.redditmedia.com/b.png") != nil)
check("the banner setting off wins over a valid URL",
      headerBannerURL(showBanner: false, raw: "https://styles.redditmedia.com/b.png") == nil)
// The overlap and the top inset both follow the resolved URL so they
// cannot disagree. Apollo's banner is a band with the identity row below
// it, with no negative overlap; top padding is the same both ways.
let headerTopPadding: CGFloat = 10
check("the header uses the same top padding with or without a banner",
      headerTopPadding == 10)

// The "Filter Subreddits" pill sits inset from the list content on both
// sides with fully rounded ends, so it cannot be a plain List row with
// `listRowBackground`.
let shotContentLeft = 25.0, shotContentRight = 338.0
let shotPillLeft = 37.0, shotPillRight = 325.0
check("the real filter pill is inset from BOTH edges, not full width",
      shotPillLeft > shotContentLeft && shotPillRight < shotContentRight)
check("...by about the same margin on each side",
      abs((shotPillLeft - shotContentLeft) - (shotContentRight - shotPillRight)) <= 2)
// A DEBUG seed for the SEARCHING state: the query is seeded via
// SIMCTL_CHILD_APOLLO_SETTINGS_SEARCH because synthetic keystrokes cannot
// reach it from a headless session.
check("the settings search seed is empty unless the env var is set",
      ProcessInfo.processInfo.environment["APOLLO_SETTINGS_SEARCH"] == nil)

// Liquid Glass detection, mirroring Reborn's IsLiquidGlass() and
// ApolloSDKEnablesLiquidGlass. Two conditions, both required: iOS 26+ and
// the UIGlassEffect class present at runtime (an @available check alone
// would claim glass where the effect is unavailable).
//
// On Linux (no UIKit) it is false, so the non-glass path is exercised.
#if canImport(UIKit)
check("glass detection requires the runtime class, not just the OS version",
      LiquidGlass.isAvailable == (NSClassFromString("UIGlassEffect") != nil))
#else
check("glass is unavailable without UIKit", !LiquidGlass.isAvailable)
#endif

// Splitting on blank lines matches how `RedditMarkdown` separates the
// blocks it emits.
let sampleBody = "First paragraph.\n\nSecond paragraph.\n\n\nThird."
check("paragraph splitting divides on blank lines",
      BodyParagraphs.split(sampleBody) == ["First paragraph.", "Second paragraph.", "Third."])
check("...and a body with no blank lines stays one paragraph",
      BodyParagraphs.split("No breaks here at all.") == ["No breaks here at all."])
// Never return an empty list: that would drop the body entirely.
check("...and an empty body never yields zero paragraphs",
      BodyParagraphs.split("").count == 1)
// --- Reddit-only inline syntax the Markdown parser does not know ---
//
// `render()` parses Markdown only under `#if canImport(Darwin)`. The parser
// handles bold, italic, bold-italic, partial-word emphasis, strikethrough,
// inline code, escapes, HTML entities, hard breaks, thematic breaks and
// ordered lists, but leaks raw syntax for:
//   `^(text)` / `^word`  -> literal carets
//   `>!text!<`           -> literal >! and !<
//   `| a | b |`          -> cells scrambled into separate paragraphs
check("a parenthesised superscript loses its caret",
      !RedditMarkdown.expandRedditInlineSyntax("reddit ^(and be)").contains("^"))
check("a bare word superscript loses its caret",
      !RedditMarkdown.expandRedditInlineSyntax("just ^reddit here").contains("^"))
check("...and keeps the word itself",
      RedditMarkdown.expandRedditInlineSyntax("just ^reddit here").contains("reddit"))
check("a spoiler loses its markers",
      RedditMarkdown.expandRedditInlineSyntax("to >!hidden!< now") == "to hidden now")
check("a caret with no superscript is untouched",
      RedditMarkdown.expandRedditInlineSyntax("2 ^ 3") == "2 ^ 3")

// Tables: pipe rows become plain markdown lines, since the parser has no
// table support. Fencing them as a code block would preserve column spacing
// but a fence means verbatim, so each cell's own markdown (`**bold**`,
// [`hash`](url)) would stop being parsed.
let table = "| a | bb |\n|---|---:|\n| 1 | 2 |"
let rewritten = RedditMarkdown.rewriteTables(table)
check("a table is NOT fenced, so its cells keep their markdown",
      !rewritten.contains("```"))
check("...and its cells are preserved",
      rewritten.contains("a") && rewritten.contains("bb") && rewritten.contains("1"))
// Markdown inside a cell survives the rewrite.
let richTable = "| Game | Change |\n|---|---|\n| **Lineage II** | Fixed. [`d442b416`](https://e/c) |"
let richRewritten = RedditMarkdown.rewriteTables(richTable)
check("bold inside a cell survives the rewrite",
      richRewritten.contains("**Lineage II**"))
check("a link inside a cell survives the rewrite",
      richRewritten.contains("[`d442b416`](https://e/c)"))
check("a rewritten table is not wrapped in a code fence",
      !richRewritten.contains("```"))
// Each row becomes its own paragraph, or the parser folds them into one
// run-on block.
check("rows are separated by blank lines",
      richRewritten.contains("\n\n"))
// A marker row is required: a lone pipe line is ordinary text.
check("a pipe line with no marker row is not a table",
      RedditMarkdown.rewriteTables("a | b") == "a | b")
check("the marker row is recognized",
      RedditMarkdown.isTableMarkerRow("|---|:---:|"))
check("...and a data row is not mistaken for one",
      !RedditMarkdown.isTableMarkerRow("| a | b |"))
