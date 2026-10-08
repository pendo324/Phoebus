import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Siri & Spotlight (Reborn #1299)
//
// What the Spotlight and Siri index may hold: eligibility, limits, pruning,
// tombstones, spoken names, the session context, the incremental publication
// plan and the publication gate.

private let siriNow = Date(timeIntervalSince1970: 1_800_000_000)
private let siriAccount = "test-account-fingerprint"

private func siriPost(_ name: String, title: String = "Café and iPhone Duo") -> [String: Any] {
    ["kind": "t3", "name": "t3_\(name)", "title": title, "subreddit": "apple", "author": "testuser",
     "selftext": "Searchable body", "subreddit_type": "public", "hidden": false, "over_18": false,
     "created_utc": siriNow.timeIntervalSince1970]
}

private func siriCommunity(_ name: String, description: String = "") -> [String: Any] {
    ["kind": "t5", "display_name": name, "public_description": description,
     "subreddit_type": "public", "over18": false, "user_is_subscriber": true]
}

private func siriData(_ rows: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: rows) }

private func siriComment(_ id: String, link: String = "t3_meta1", body: String = "A useful comment body", score: Int = 1,
                         depth: Int = 0, op: Bool = false, author: String = "someone") -> [String: Any] {
    ["name": id, "link_id": link, "subreddit": "apple", "author": author, "body": body,
     "score": score, "depth": depth, "is_submitter": op, "created_utc": 1_700_000_000]
}

@MainActor func checkSiriContentCatalogue() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phoebus-siri-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("catalog.json")
    let store = try SiriContentCatalog(file: file, postLimit: 2, subredditLimit: 1, retention: 100)

    check("Siri index: the limits are 1,000 posts and 500 communities for 30 days",
          SiriContentLimits.posts == 1000 && SiriContentLimits.communities == 500
            && SiriContentLimits.retention == 30 * 24 * 60 * 60)
    check("Siri index: indexing is off by default",
          !SiriContentSettings.isEnabled && SiriContentSettings.enabledKey == "ApolloSiriContentEnabled")

    try store.ingest(siriData([siriPost("a")]), account: siriAccount, now: siriNow)
    check("Siri index: a disabled catalogue collects nothing", store.state.records.isEmpty)
    try store.configure(enabled: true, account: siriAccount)
    try store.ingest(siriData([siriPost("a"), siriPost("a")]), account: siriAccount, now: siriNow)
    check("Siri index: a repeated record isn't duplicated", store.records(now: siriNow).count == 1)
    check("Siri index: search folds case and diacritics and matches every term",
          store.records(query: "CAFE duo", now: siriNow).count == 1)
    check("Siri index: a missing term matches nothing", store.records(query: "missing", now: siriNow).isEmpty)
    check("Siri index: records resolve by id in a batch",
          store.resolve(["reddit:post:t3_a", "missing"], now: siriNow).count == 1)
    check("Siri index: a zero limit returns nothing", store.records(limit: 0, now: siriNow).isEmpty)
    let reopened = try SiriContentCatalog(file: file, postLimit: 2, subredditLimit: 1, retention: 100)
    check("Siri index: the catalogue survives a relaunch", reopened.records(now: siriNow).count == 1)
    try store.ingest(siriData([siriPost("a", title: "Updated")]), account: siriAccount, now: siriNow)
    check("Siri index: a later listing updates the record", store.records(now: siriNow).first?.title == "Updated")

    for field in ["over_18", "hidden"] {
        var rejected = siriPost("a"); rejected[field] = true
        try store.ingest(siriData([rejected]), account: siriAccount, now: siriNow)
        check("Siri index: a post that becomes \(field) is removed", store.records(now: siriNow).isEmpty)
        try store.ingest(siriData([siriPost("a")]), account: siriAccount, now: siriNow)
    }
    for (field, value) in [("subreddit_type", "private"), ("removed_by_category", "deleted"),
                           ("selftext", "[removed]"), ("author", "[deleted]")] {
        var rejected = siriPost("a"); rejected[field] = value
        try store.ingest(siriData([rejected]), account: siriAccount, now: siriNow)
        check("Siri index: a post with \(field) \(value) isn't kept", store.records(now: siriNow).isEmpty)
        try store.ingest(siriData([siriPost("a")]), account: siriAccount, now: siriNow)
    }
    var missing = siriPost("a"); missing.removeValue(forKey: "over_18")
    try store.ingest(siriData([missing]), account: siriAccount, now: siriNow)
    check("Siri index: a missing NSFW flag is treated as unsafe", store.records(now: siriNow).isEmpty)

    try store.ingest(siriData([siriPost("a"), siriPost("b"), siriPost("c")]), account: siriAccount, now: siriNow)
    check("Siri index: posts beyond the limit are pruned", store.records(now: siriNow).count == 2)
    check("Siri index: expired records don't resolve", store.records(now: siriNow.addingTimeInterval(101)).isEmpty)
    try store.expire(now: siriNow.addingTimeInterval(101))
    check("Siri index: expiry is persisted", store.state.records.isEmpty)

    var subreddit = siriCommunity("Apple")
    subreddit["title"] = "Apple"
    try store.ingest(siriData([subreddit]), account: siriAccount, now: siriNow)
    check("Siri index: a community's id is its lowercased name", store.records(now: siriNow).first?.id == "reddit:subreddit:apple")
    check("Siri index: a community is searchable by name", store.records(kind: .subreddit, query: "apple", now: siriNow).count == 1)
    var nsfwCommunity = subreddit
    nsfwCommunity["over18"] = true
    nsfwCommunity["over_18"] = false
    try store.ingest(siriData([nsfwCommunity]), account: siriAccount, now: siriNow)
    check("Siri index: an NSFW community is removed, whatever the post flag says",
          store.records(kind: .subreddit, now: siriNow).isEmpty)
    var missingCommunityFlag = subreddit
    missingCommunityFlag.removeValue(forKey: "over18")
    missingCommunityFlag["over_18"] = false
    check("Siri index: the post flag doesn't vouch for a community",
          SiriContentRecord.parse(missingCommunityFlag, now: siriNow) == nil)
    var missingPostFlag = siriPost("a")
    missingPostFlag.removeValue(forKey: "over_18")
    missingPostFlag["over18"] = false
    check("Siri index: the community flag doesn't vouch for a post",
          SiriContentRecord.parse(missingPostFlag, now: siriNow) == nil)
    try store.ingest(siriData([subreddit]), account: siriAccount, now: siriNow)
    subreddit["user_is_subscriber"] = false
    try store.ingest(siriData([subreddit]), account: siriAccount, now: siriNow)
    check("Siri index: an unsubscribed community isn't kept", store.records(now: siriNow).isEmpty)

    var outbound = siriPost("a"); outbound["permalink"] = "https://evil.invalid/"
    try store.ingest(siriData([outbound]), account: siriAccount, now: siriNow)
    check("Siri index: a post's route comes from its validated names, never its link",
          store.records(now: siriNow).first?.route == "/r/apple/comments/a/")
    check("Siri index: a post opens its thread",
          store.records(now: siriNow).first?.navigationTarget == .post(subreddit: "apple", id: "a"))

    try store.configure(enabled: true, account: "other-account")
    check("Siri index: switching account clears the previous account's content", store.records(now: siriNow).isEmpty)
    try store.ingest(siriData([siriPost("a")]), account: siriAccount, now: siriNow)
    check("Siri index: a late response for the old account is ignored", store.records(now: siriNow).isEmpty)
    try store.configure(enabled: false, account: siriAccount)
    let afterOptOut = try SiriContentCatalog(file: file)
    check("Siri index: turning it off removes the catalogue from disk", afterOptOut.state.records.isEmpty)
    try store.configure(enabled: true, account: nil)
    try store.ingest(siriData([siriPost("a")]), account: siriAccount, now: siriNow)
    check("Siri index: nothing is collected without an account", store.records(now: siriNow).isEmpty)
    check("Siri index: an invalid identifier is rejected", SiriContentRecord.parse(siriPost("../escape"), now: siriNow) == nil)

    try store.configure(enabled: true, account: siriAccount)
    try store.ingest(siriData([siriPost("a")]), account: siriAccount, now: siriNow)
    try store.suppress(["reddit:post:t3_a"], account: siriAccount, now: siriNow)
    check("Siri index: hiding a post removes it", store.records(now: siriNow).isEmpty)
    try store.ingest(siriData([siriPost("a")]), account: siriAccount, now: siriNow)
    check("Siri index: a late listing can't resurrect a hidden post", store.records(now: siriNow).isEmpty)
    let afterHide = try SiriContentCatalog(file: file)
    check("Siri index: the tombstone survives a relaunch", afterHide.state.suppressed?["reddit:post:t3_a"] != nil)
    try store.allow(["reddit:post:t3_a"], account: "wrong-account")
    check("Siri index: another account can't undo a tombstone", store.isSuppressed("reddit:post:t3_a"))
    try store.allow(["reddit:post:t3_a"], account: siriAccount)
    check("Siri index: unhiding doesn't resurrect stale text", store.records(now: siriNow).isEmpty)
    try store.ingest(siriData([siriPost("a")]), account: siriAccount, now: siriNow)
    check("Siri index: a fresh listing after unhide is accepted", store.records(now: siriNow).count == 1)

    subreddit["user_is_subscriber"] = true
    subreddit["name"] = "t5_test"
    try store.ingest(siriData([subreddit]), account: siriAccount, now: siriNow)
    let communityIDs = store.canonicalIdentifiers(["t5_test"])
    check("Siri index: a community fullname resolves to its id", communityIDs == ["reddit:subreddit:apple"])
    check("Siri index: names resolve to ids",
          store.canonicalIdentifiers(["t3_ABC", "r/Apple", "other"]) == ["reddit:post:t3_abc", "reddit:subreddit:apple"])
    try store.suppress(communityIDs, account: siriAccount, now: siriNow)
    let afterUnsubscribe = try SiriContentCatalog(file: file)
    check("Siri index: the unsubscribe alias survives a relaunch",
          afterUnsubscribe.canonicalIdentifiers(["t5_test"]) == communityIDs)
    try store.ingest(siriData([subreddit]), account: siriAccount, now: siriNow)
    check("Siri index: a late listing can't resurrect an unsubscribe", store.records(kind: .subreddit, now: siriNow).isEmpty)
    try store.allow(store.canonicalIdentifiers(["t5_test"]), account: siriAccount)
    try store.ingest(siriData([subreddit]), account: siriAccount, now: siriNow)
    check("Siri index: subscribing again accepts fresh metadata", store.records(kind: .subreddit, now: siriNow).count == 1)
    try store.configure(enabled: true, account: "other-account")
    check("Siri index: an account change drops the tombstones",
          store.state.suppressed == nil && store.state.suppressedAliases == nil)
}

@MainActor func checkSiriSpokenCommunityNames() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phoebus-siri-names-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let names = try SiriContentCatalog(file: directory.appendingPathComponent("names.json"), retention: 100)
    try names.configure(enabled: true, account: siriAccount)
    try names.ingest(siriData([siriCommunity("boutiquebluray"), siriCommunity("boutique_bluray")]), account: siriAccount, now: siriNow)
    try names.ingest(siriData([siriCommunity("movies", description: "boutique blu-ray boutiqueBluray cinema")]),
                     account: siriAccount, now: siriNow.addingTimeInterval(1))
    for query in ["boutique blu-ray", "BOUTIQUE BLU–RAY", "r/boutiquebluray", " /r/BoutiqueBluray "] {
        check("Siri index: the spoken name \(query) outranks a description match",
              names.records(kind: .subreddit, query: query, limit: 1, now: siriNow).map(\.id) == ["reddit:subreddit:boutiquebluray"])
    }
    check("Siri index: an underscore in a community name stays meaningful",
          names.records(kind: .subreddit, query: "boutique_bluray", now: siriNow).map(\.id) == ["reddit:subreddit:boutique_bluray"])
    check("Siri index: description search still works",
          names.records(kind: .subreddit, query: "cinema", now: siriNow).map(\.id) == ["reddit:subreddit:movies"])
    check("Siri index: unmatched words aren't discarded",
          names.records(kind: .subreddit, query: "boutique bluray missing", now: siriNow).isEmpty)
    check("Siri index: spoken matching doesn't resurrect expired records",
          names.records(kind: .subreddit, query: "boutique blu-ray", now: siriNow.addingTimeInterval(102)).isEmpty)

    var titled = siriCommunity("criterion")
    titled["title"] = "The Criterion Collection"
    try names.ingest(siriData([titled]), account: siriAccount, now: siriNow)
    check("Siri index: a community's display title is a spoken alias",
          names.records(kind: .subreddit, query: "the criterion collection", limit: 1, now: siriNow).map(\.id) == ["reddit:subreddit:criterion"])
    check("Siri index: the display title is stored",
          names.resolve(["reddit:subreddit:criterion"], now: siriNow).first?.displayTitle == "The Criterion Collection")
    let legacy = try JSONDecoder().decode(SiriContentRecord.self, from: Data(#"{"id":"reddit:subreddit:x","kind":"subreddit","title":"r/x","subreddit":"x","author":"","text":"","createdAt":0,"observedAt":0,"route":"/r/x/"}"#.utf8))
    check("Siri index: a record saved without a display title still decodes", legacy.displayTitle == nil)
    check("Siri index: a post shares as its HTTPS permalink",
          SiriContentRecord.webURL(forRoute: "/r/apple/comments/abc123/").absoluteString == "https://www.reddit.com/r/apple/comments/abc123/")
    check("Siri index: a share link can't leave reddit.com",
          SiriContentRecord.webURL(forRoute: "https://evil.example/x").absoluteString == "https://www.reddit.com/")

    try names.suppress(["reddit:subreddit:boutiquebluray"], account: siriAccount, now: siriNow)
    check("Siri index: spoken matching doesn't resurrect a suppressed community",
          !names.records(kind: .subreddit, query: "boutique blu-ray", now: siriNow).contains { $0.id == "reddit:subreddit:boutiquebluray" })
    try names.configure(enabled: false, account: siriAccount)
    check("Siri index: spoken matching doesn't bypass opting out",
          names.records(kind: .subreddit, query: "boutique blu-ray", now: siriNow).isEmpty)

    let meta = try SiriContentCatalog(file: directory.appendingPathComponent("meta.json"))
    try meta.configure(enabled: true, account: siriAccount)
    try meta.ingest(siriData([["kind": "t3", "name": "t3_meta1", "title": "Link", "subreddit": "apple", "author": "a",
                               "selftext": "", "subreddit_type": "public", "over_18": false, "hidden": false,
                               "score": 1234, "num_comments": 56, "domain": "TheVerge.com"],
                              ["kind": "t3", "name": "t3_meta2", "title": "Self", "subreddit": "apple", "author": "a",
                               "selftext": "x", "subreddit_type": "public", "over_18": false, "hidden": false,
                               "domain": "self.apple"]]), account: siriAccount, now: siriNow)
    let link = meta.resolve(["reddit:post:t3_meta1"], now: siriNow).first
    check("Siri index: a link post keeps its score, comment count and site",
          link?.score == 1234 && link?.commentCount == 56 && link?.linkDomain == "theverge.com")
    let selfPost = meta.resolve(["reddit:post:t3_meta2"], now: siriNow).first
    check("Siri index: a self post has no site and an absent score stays absent",
          selfPost?.linkDomain == nil && selfPost?.score == nil)
}

@MainActor func checkSiriSessionContext() async throws {
    check("Siri context: a comment parses with its post",
          SiriCommentRecord.parse(siriComment("t1_ok"), order: 0)?.postID == "reddit:post:t3_meta1")
    check("Siri context: an unprefixed link id is normalized",
          SiriCommentRecord.parse(siriComment("t1_ok", link: "meta1"), order: 0)?.postID == "reddit:post:t3_meta1")
    check("Siri context: a removed comment is refused", SiriCommentRecord.parse(siriComment("t1_x", body: "[removed]"), order: 0) == nil)
    check("Siri context: a deleted author is refused", SiriCommentRecord.parse(siriComment("t1_x", author: "[deleted]"), order: 0) == nil)
    check("Siri context: a post fullname isn't a comment", SiriCommentRecord.parse(siriComment("t3_notacomment"), order: 0) == nil)
    check("Siri context: a comment's route is its thread",
          SiriCommentRecord.parse(siriComment("t1_abc"), order: 0)?.route == "/r/apple/comments/meta1/_/abc/")
    check("Siri context: a comment opens in its thread",
          SiriCommentRecord.parse(siriComment("t1_abc"), order: 0)?.navigationTarget
            == .comment(subreddit: "apple", postID: "meta1", commentID: "abc"))

    let session = SiriSessionContext(postLimit: 2, threadLimit: 2, commentsPerThread: 3)
    session.configure(account: siriAccount)
    let parsed = [siriComment("t1_low", score: 1), siriComment("t1_top", score: 900), siriComment("t1_op", score: 2, op: true),
                  siriComment("t1_deep", score: 950, depth: 12), siriComment("t1_over", score: 5000)]
        .enumerated().compactMap { SiriCommentRecord.parse($0.element, order: $0.offset) }
    session.observe(comments: parsed, account: siriAccount)
    check("Siri context: a thread keeps at most its cap of comments", session.comments(forPost: "reddit:post:t3_meta1", limit: 10).count == 3)
    check("Siri context: the best comments come first, OP and score favoured",
          session.comments(forPost: "reddit:post:t3_meta1", limit: 2).map(\.id) == ["reddit:comment:t1_op", "reddit:comment:t1_top"])
    check("Siri context: comments resolve by id", session.comments(["reddit:comment:t1_top"]).first?.score == 900)
    check("Siri context: comment search matches every term", session.search("useful", limit: 5).count == 3)
    session.observe(comments: parsed, account: "other-account")
    check("Siri context: another account's comments are refused", session.comments(forPost: "reddit:post:t3_meta1", limit: 10).count == 3)
    for id in ["t1_a2", "t1_a3"] {
        session.observe(comments: [SiriCommentRecord.parse(siriComment(id, link: "t3_\(id.dropFirst(3))"), order: 0)!], account: siriAccount)
    }
    check("Siri context: the oldest thread is evicted", session.comments(forPost: "reddit:post:t3_meta1", limit: 10).isEmpty)

    let viewed = ["t3_v1", "t3_v2", "t3_v3"].compactMap {
        SiriContentRecord.parse(["kind": "t3", "name": $0, "title": "T", "subreddit": "apple", "author": "a",
                                 "selftext": "", "subreddit_type": "public", "over_18": false, "hidden": false], now: siriNow)
    }
    viewed.forEach { session.observe(post: $0, account: siriAccount) }
    check("Siri context: viewed posts are kept least-recently-first out",
          session.post("reddit:post:t3_v1") == nil && session.post("reddit:post:t3_v3") != nil)
    check("Siri context: it can list what it holds",
          Set(session.postIDs) == ["reddit:post:t3_v2", "reddit:post:t3_v3"] && session.commentIDs.count == 2)
    session.suppress(["reddit:post:t3_v3", "reddit:post:t3_a3"])
    check("Siri context: hiding a post drops it and its comments",
          session.post("reddit:post:t3_v3") == nil && session.comments(forPost: "reddit:post:t3_a3", limit: 5).isEmpty)
    session.configure(account: nil)
    check("Siri context: a scope change drops everything",
          session.post("reddit:post:t3_v2") == nil && session.comments(forPost: "reddit:post:t3_a2", limit: 5).isEmpty)
}

@MainActor func checkSiriCaptureAndPublication() async throws {
    // What leaves a response: an allowlist, never the original.
    let listing = try JSONDecoder.reddit.decode(RedditListing.self, from: Data("""
    {"kind":"Listing","data":{"after":null,"children":[
      {"kind":"t3","data":{"name":"t3_abc","title":"Hello","subreddit":"apple","author":"u","selftext":"body",
        "subreddit_type":"public","over_18":false,"hidden":false,"score":0,"num_comments":4,"created_utc":1700000000,
        "domain":"self.apple","secret_token":"must not travel","upvote_ratio":0.9}},
      {"kind":"t5","data":{"display_name":"Apple","title":"Apple","public_description":"d","over18":false,
        "subreddit_type":"public","user_is_subscriber":true,"name":"t5_x","email":"must not travel"}},
      {"kind":"t1","data":{"name":"t1_zzz","body":"not a post"}}]}}
    """.utf8))
    let payload = SiriContentSanitizer.listingPayload(listing.data.children)
    let rows = (payload.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [[String: Any]] ?? []
    check("Siri capture: a listing forwards posts and communities only", rows.count == 2)
    check("Siri capture: only allowlisted keys are forwarded",
          rows.allSatisfy { $0["secret_token"] == nil && $0["email"] == nil && $0["upvote_ratio"] == nil })
    check("Siri capture: a forwarded post still parses as eligible",
          rows.first.flatMap { SiriContentRecord.parse($0, now: siriNow) }?.commentCount == 4)
    check("Siri capture: a zero score stays a number, not a flag",
          rows.first.flatMap { SiriContentRecord.parse($0, now: siriNow) }?.score == 0)
    check("Siri capture: a forwarded community parses as eligible",
          rows.last.flatMap { SiriContentRecord.parse($0, now: siriNow) }?.id == "reddit:subreddit:apple")
    check("Siri capture: a listing names its communities",
          SiriContentSanitizer.communityIDs(listing.data.children) == ["reddit:subreddit:apple"])

    let long = String(repeating: "x", count: 5000)
    let longListing = try JSONDecoder.reddit.decode(RedditListing.self, from: Data("""
    {"kind":"Listing","data":{"children":[{"kind":"t3","data":{"name":"t3_abc","title":"\(long)","selftext":"\(long)",
      "subreddit":"apple","author":"u","subreddit_type":"public","over_18":false,"hidden":false}}]}}
    """.utf8))
    let longRow = (SiriContentSanitizer.listingPayload(longListing.data.children)
        .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]])?.first
    check("Siri capture: long text is cut before it leaves the response",
          (longRow?["title"] as? String)?.count == 512 && (longRow?["selftext"] as? String)?.count == 2048)

    // A /comments/<id> response: the post, and every loaded comment with its depth.
    let thread = Data("""
    [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{"name":"t3_abc","title":"Hello","subreddit":"apple",
       "author":"op","selftext":"","subreddit_type":"public","over_18":false,"hidden":false,"score":5,"num_comments":3}}]}},
     {"kind":"Listing","data":{"children":[
       {"kind":"t1","data":{"name":"t1_c1","link_id":"t3_abc","subreddit":"apple","author":"op","body":"first","score":3,
         "is_submitter":true,"created_utc":1700000000,"depth":0,
         "replies":{"kind":"Listing","data":{"children":[
           {"kind":"t1","data":{"name":"t1_c2","link_id":"t3_abc","subreddit":"apple","author":"b","body":"reply","score":1,
             "is_submitter":false,"created_utc":1700000100,"depth":1,"replies":""}}]}}}},
       {"kind":"more","data":{"count":3,"children":["x"]}}]}}]
    """.utf8)
    let (openedPost, commentChunks) = SiriContentSanitizer.commentsResponse(thread)
    let openedRow = (openedPost.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]])?.first
    check("Siri capture: an opened post is parsed from its comments response",
          openedRow.flatMap { SiriContentRecord.parse($0, now: siriNow) }?.id == "reddit:post:t3_abc")
    let commentRows = commentChunks.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [[String: Any]] ?? [] }
    let comments = commentRows.compactMap { SiriCommentRecord.parse($0, order: ($0["order"] as? NSNumber)?.intValue ?? 0) }
    check("Siri capture: nested replies are flattened, other rows skipped", comments.map(\.id) == ["reddit:comment:t1_c1", "reddit:comment:t1_c2"])
    check("Siri capture: a comment keeps its depth and OP flag",
          comments.first?.isOP == true && comments.last?.depth == 1 && comments.last?.isOP == false)
    check("Siri capture: comments keep the thread's order", comments.map(\.order) == [0, 1])
    check("Siri capture: a response that isn't a thread yields nothing",
          SiriContentSanitizer.commentsResponse(Data("{}".utf8)).post == nil
            && SiriContentSanitizer.commentsResponse(Data("[]".utf8)).comments.isEmpty)
    let moreThings = try JSONDecoder.reddit.decode([JSONValue].self, from: Data("""
    [{"kind":"t1","data":{"name":"t1_m1","link_id":"t3_abc","subreddit":"apple","author":"c","body":"more","score":2,"depth":2}}]
    """.utf8))
    let moreRows = SiriContentSanitizer.moreChildren(moreThings).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [[String: Any]] ?? [] }
    check("Siri capture: loaded 'more comments' are forwarded too",
          moreRows.compactMap { SiriCommentRecord.parse($0, order: 0) }.first?.depth == 2)

    // Nothing is read from a response while the setting is off or no app sink exists.
    nonisolated(unsafe) var events = 0
    SiriContentCapture.sink = { _ in events += 1 }
    FavoriteSubredditsAccountContext.currentUsernameProvider = { "someone" }
    SiriContentCapture.listingLoaded(listing, requestedBy: "someone")
    check("Siri capture: nothing is captured while indexing is off", events == 0)
    SiriContentSettings.enabled.save(true)
    SiriContentCapture.listingLoaded(listing, requestedBy: "someone")
    check("Siri capture: a listing is captured once indexing is on", events == 1)
    SiriContentCapture.listingLoaded(listing, requestedBy: "somebody-else")
    check("Siri capture: a response for another account is dropped", events == 1)
    SiriContentCapture.eligibilityChanged(["t3_abc"], allow: false)
    check("Siri capture: a hide is reported", events == 2)
    SiriContentCapture.eligibilityChanged([], allow: true)
    check("Siri capture: an empty change is ignored", events == 2)
    SiriContentSettings.enabled.save(false)
    SiriContentCapture.eligibilityChanged(["t3_abc"], allow: false)
    check("Siri capture: nothing is reported once indexing is off again", events == 2)
    SiriContentCapture.sink = nil
    FavoriteSubredditsAccountContext.currentUsernameProvider = { nil }

    // The account the index belongs to is read from the stored accounts.
    let signedIn = AccountStorePersisted(accounts: [StoredAccount(username: "Alice"), StoredAccount(username: "Bob")], activeIndex: 1)
    check("Siri account: the active stored account is the index's account",
          SiriAccountStatus.resolve(signedIn, locked: false) == .signedIn("bob"))
    check("Siri account: no stored accounts is signed out",
          SiriAccountStatus.resolve(AccountStorePersisted(accounts: [], activeIndex: nil), locked: false) == .signedOut)
    check("Siri account: a locked keychain is unresolved, not signed out",
          SiriAccountStatus.resolve(nil, locked: true) == .unresolved && SiriAccountStatus.resolve(nil, locked: false) == .signedOut)
    check("Siri account: the fingerprint is one-way and case-insensitive",
          SiriAccountStatus.fingerprint("Bob") == SiriAccountStatus.fingerprint("bob")
            && SiriAccountStatus.fingerprint("bob").count == 64 && !SiriAccountStatus.fingerprint("bob").contains("bob"))

    // Incremental publication: only what changed, and a rebuild when the scope changes.
    let a = SiriContentRecord.parse(siriPost("a"), now: siriNow)!
    let b = SiriContentRecord.parse(siriPost("b"), now: siriNow)!
    let apple = SiriContentRecord.parse(siriCommunity("Apple"), now: siriNow)!
    let first = SiriPublicationPlan.make(checkpoint: nil, account: "acct", forceReset: false, posts: [a, b], subreddits: [apple])
    check("Siri publish: with no checkpoint everything is published after a reset",
          first.reset && first.changedPosts.count == 2 && first.changedSubreddits.count == 1 && !first.isEmpty)
    let steady = SiriPublicationPlan.make(checkpoint: first.next, account: "acct", forceReset: false, posts: [a, b], subreddits: [apple])
    check("Siri publish: nothing changed, nothing to publish", steady.isEmpty && !steady.reset)
    let edited = SiriContentRecord.parse(siriPost("a", title: "Edited"), now: siriNow)!
    let changed = SiriPublicationPlan.make(checkpoint: first.next, account: "acct", forceReset: false, posts: [edited], subreddits: [apple])
    check("Siri publish: an edited post is upserted and a dropped one deleted",
          changed.changedPosts.map(\.id) == [a.id] && changed.removedPostIDs == [b.id] && changed.changedSubreddits.isEmpty)
    let later = SiriContentRecord.parse(siriPost("a"), now: siriNow.addingTimeInterval(8 * 24 * 60 * 60))!
    check("Siri publish: a record seen again a week later is refreshed so its expiry keeps up",
          SiriPublicationPlan.make(checkpoint: first.next, account: "acct", forceReset: false, posts: [later, b], subreddits: [apple])
            .changedPosts.map(\.id) == [a.id])
    check("Siri publish: another account rebuilds from nothing",
          SiriPublicationPlan.make(checkpoint: first.next, account: "other", forceReset: false, posts: [a], subreddits: []).reset)
    let off = SiriPublicationPlan.make(checkpoint: first.next, account: nil, forceReset: false, posts: [], subreddits: [])
    check("Siri publish: turning indexing off resets the index and publishes nothing",
          off.reset && off.changedPosts.isEmpty && off.changedSubreddits.isEmpty && off.next.posts.isEmpty)
    check("Siri publish: a forced reset republishes the unchanged",
          SiriPublicationPlan.make(checkpoint: first.next, account: "acct", forceReset: true, posts: [a, b], subreddits: [apple]).changedPosts.count == 2)
    check("Siri publish: the client state follows the checkpoint",
          first.next.clientState.count == 32 && first.next.clientState == steady.next.clientState
            && first.next.clientState != changed.next.clientState)
    let saved = try JSONDecoder().decode(SiriPublishCheckpoint.self, from: JSONEncoder().encode(first.next))
    check("Siri publish: the checkpoint survives a relaunch", saved == first.next)

    // Status text and the onscreen registry.
    check("Siri status: off says the index is cleared",
          SiriContentStatus.text(enabled: false, signedIn: true, posts: 3, communities: 2).contains("is off"))
    check("Siri status: on without an account asks to sign in",
          SiriContentStatus.text(enabled: true, signedIn: false, posts: 0, communities: 0).contains("Sign in"))
    check("Siri status: on reports the counts and limits",
          SiriContentStatus.text(enabled: true, signedIn: true, posts: 12, communities: 3)
            == "Phoebus catalogue: 12 posts and 3 subscribed communities. Public, non-NSFW content only; up to 30 days of loaded content.")
    check("Siri status: an incomplete refresh says no entries were removed",
          SiriContentStatus.incompleteRefresh("x").contains("500-subscription") && SiriContentStatus.incompleteRefresh("x").contains("no missing entries"))
    nonisolated(unsafe) var announced = 0
    let observer = NotificationCenter.default.addObserver(forName: .phoebusSiriOnscreenChanged, object: nil, queue: nil) { _ in announced += 1 }
    SiriOnscreen.replace(with: ["reddit:post:t3_a"])
    SiriOnscreen.replace(with: ["reddit:post:t3_a"])
    check("Siri onscreen: an unchanged set isn't announced twice", announced == 1)
    check("Siri onscreen: only the allowed ids are annotatable",
          SiriOnscreen.contains("reddit:post:t3_a") && !SiriOnscreen.contains("reddit:post:t3_b"))
    SiriOnscreen.replace(with: [])
    check("Siri onscreen: clearing the set removes every annotation",
          !SiriOnscreen.contains("reddit:post:t3_a") && announced == 2)
    NotificationCenter.default.removeObserver(observer)
    check("Siri onscreen: rows name entities by catalogue id",
          SiriOnscreen.postID("t3_AbC") == "reddit:post:t3_abc" && SiriOnscreen.commentID("t1_x") == "reddit:comment:t1_x"
            && SiriOnscreen.postID("t1_x") == nil)
}

private actor SiriGateProbe {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var starts = 0
    private(set) var staleWrites = 0

    func suspend() async {
        starts += 1
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
    func recordWrite() { staleWrites += 1 }
}

private struct SiriGateFailure: Error {}

@MainActor func checkSiriPublicationGate() async throws {
    let gate = SiriPublicationGate()
    try await gate.run { }
    var surfaced = false
    do { try await gate.run { throw SiriGateFailure() } } catch is SiriGateFailure { surfaced = true }
    check("Siri gate: an SDK error reaches the caller", surfaced)
    try await gate.run { }

    // An SDK callback that ignores cancellation until released.
    let probe = SiriGateProbe()
    let started = ContinuousClock.now
    var timedOut = false
    do {
        try await gate.run(timeout: .milliseconds(30)) {
            await probe.suspend()
            try Task.checkCancellation()
            await probe.recordWrite()
        }
    } catch SiriPublicationGate.Failure.timedOut { timedOut = true }
    check("Siri gate: a missing SDK callback times out and releases its caller",
          timedOut && started.duration(to: .now) < .seconds(2))
    var refused = 0
    for _ in 0..<100 {
        do { try await gate.run { await probe.suspend() } } catch SiriPublicationGate.Failure.stillRunning { refused += 1 }
    }
    let starts = await probe.starts
    check("Siri gate: a timed-out operation keeps its slot, so retries don't pile up", refused == 100 && starts == 1)
    await probe.release()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    var drained = false
    while ContinuousClock.now < deadline {
        do { try await gate.run { }; drained = true; break }
        catch SiriPublicationGate.Failure.stillRunning { await Task.yield() }
    }
    check("Siri gate: a late completion frees the slot", drained)
    let staleWrites = await probe.staleWrites
    check("Siri gate: a cancelled publication doesn't keep writing", staleWrites == 0)

    // Old timers must neither resume a finished run's waiter nor cancel the next run.
    var clean = true
    for _ in 0..<100 {
        do { try await gate.run(timeout: .milliseconds(10)) { } } catch { clean = false }
    }
    try await Task.sleep(for: .milliseconds(30))
    do { try await gate.run { } } catch { clean = false }
    for _ in 0..<50 {
        do { try await gate.run(timeout: .milliseconds(1)) { try await Task.sleep(for: .milliseconds(1)) } }
        catch SiriPublicationGate.Failure.timedOut { }
        let limit = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            do { try await gate.run(timeout: .seconds(1)) { try await Task.sleep(for: .milliseconds(2)) }; break }
            catch SiriPublicationGate.Failure.stillRunning {
                if ContinuousClock.now >= limit { clean = false; break }
                await Task.yield()
            } catch { clean = false; break }
        }
    }
    check("Siri gate: success, timeout and timer races never cross runs", clean)
}

@MainActor func checkSiriSettingsAndBackup() async throws {
    check("Siri settings: a fresh install has indexing off", !SiriContentSettings.enabled.load())
    let summary = ApolloSettingsMigration.apply(.init(preferences: ["ApolloSiriContentEnabled": true]))
    check("Siri settings: a Reborn backup carries the opt-in over",
          SiriContentSettings.isEnabled && summary.skippedUnknown == 0)
    check("Siri settings: the opt-in is in Phoebus's own backups",
          SettingsDomainSnapshot.isBackedUp(SiriContentSettings.enabledKey))
    _ = ApolloSettingsMigration.apply(.init(preferences: ["ApolloSiriContentEnabled": false]))
    check("Siri settings: a backup can switch it off", !SiriContentSettings.isEnabled)
    _ = ApolloSettingsMigration.apply(.init(preferences: ["ApolloSiriContentEnabled": "yes"]))
    check("Siri settings: a value of the wrong type leaves it alone", !SiriContentSettings.isEnabled)
    check("Siri settings: the screen is found by its rows in Settings search",
          SettingsSearch.results(for: "index phoebus content").first?.screen == .siriSpotlight
            && SettingsSearch.results(for: "siri spotlight").contains { $0.screen == .siriSpotlight })
}

