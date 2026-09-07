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
