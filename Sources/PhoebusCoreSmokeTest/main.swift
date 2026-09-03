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
