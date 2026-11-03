import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Fewer Reddit requests
//
// Reddit gives an API-Key-Free (web session) account a small request budget
// and answers 429 to everything once it is spent. These checks count the
// requests a feed page, an Inbox page, a "more replies" expansion and a
// link preview make, and what stands down while Reddit's rate limit hold runs.

/// Answers every request from `respond` and records the URLs.
private final class DietStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var urls: [URL] = []
    nonisolated(unsafe) static var respond: @Sendable (URL) -> (status: Int, body: String) = { _ in (200, "{}") }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.urls.append(url)
        let answer = Self.respond(url)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        urls = []
        respond = { _ in (200, "{}") }
    }

    static func count(_ part: String) -> Int { urls.filter { $0.absoluteString.contains(part) }.count }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DietStub.self]
        return URLSession(configuration: configuration)
    }

    /// The ids of a `user_data_by_account_ids` request, answered with a picture each.
    static func userData(for url: URL) -> String {
        let ids = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ids" }?.value ?? ""
        let records = ids.split(separator: ",").map { id in
            #""\#(id)":{"name":"u\#(id)","profile_img":"https://styles.example/\#(id).png"}"#
        }
        return "{" + records.joined(separator: ",") + "}"
    }
}

private func dietRepository(session: URLSession) throws -> RedditRepository {
    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt",
                                          expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let auth = RedditAuthClient(session: session, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    return RedditRepository(client: RedditAPIClient(auth: auth, session: session))
}

private func dietPost(_ id: String, author: String, fullname: String?) -> RedditPost {
    let extra = fullname.map { #","author_fullname":"\#($0)""# } ?? ""
    let json = """
    {"id":"\(id)","name":"t3_\(id)","title":"t","author":"\(author)","subreddit":"test",
     "permalink":"/r/test/comments/\(id)/t/","score":1,"num_comments":0,"created_utc":0,
     "is_self":true,"over_18":false,"spoiler":false,"stickied":false,"saved":false\(extra)}
    """
    return try! JSONDecoder.reddit.decode(RedditPost.self, from: Data(json.utf8))
}

private func dietMessage(_ id: String, author: String, fullname: String?) -> RedditMessage {
    let extra = fullname.map { #","author_fullname":"\#($0)""# } ?? ""
    let json = """
    {"id":"\(id)","name":"t1_\(id)","author":"\(author)","subject":"s","body":"b","created_utc":0,
     "new":false,"was_comment":true\(extra)}
    """
    return try! JSONDecoder.reddit.decode(RedditMessage.self, from: Data(json.utf8))
}

@MainActor func checkFeedPageAvatarBatch() async throws {
    // Which authors a page hands to the batch lookup.
    let page = [dietPost("a", author: "Alice", fullname: "t2_alice"),
                dietPost("b", author: "alice", fullname: "t2_alice"),
                dietPost("c", author: "Bob", fullname: "t2_bob"),
                dietPost("d", author: "[deleted]", fullname: "t2_gone"),
                dietPost("e", author: "NoId", fullname: nil),
                dietPost("f", author: "Odd", fullname: "t5_notauser")]
    let authors = AvatarBatchAuthors.authors(in: page)
    check("a page's batch has each author with a t2_ id once, without deleted or id-less authors",
          authors.map(\.username) == ["Alice", "Bob"] && authors.map(\.fullname) == ["t2_alice", "t2_bob"])
    check("a post carries its author's t2_ id from the listing JSON", page[0].authorFullname == "t2_alice" && page[4].authorFullname == nil)
    let messages = [dietMessage("m1", author: "AHMessengerBot", fullname: "t2_bot"),
                    dietMessage("m2", author: "u/someone is permanently banned from r/x", fullname: "t2_notice"),
                    dietMessage("m3", author: "ahmessengerbot", fullname: "t2_bot")]
    check("an inbox page's batch skips a sender that is not a username, and repeats",
          AvatarBatchAuthors.authors(in: messages).map(\.fullname) == ["t2_bot"])

    // One request per 100 authors instead of one /about each.
    let session = DietStub.session()
    let repository = try dietRepository(session: session)
    await AvatarCache.shared.clear()
    DietStub.reset()
    DietStub.respond = { url in
        url.path.contains("user_data_by_account_ids") ? (200, DietStub.userData(for: url)) : (200, "{}")
    }
    let big = (0..<130).map { (username: "DietUser\($0)", fullname: "t2_diet\($0)") }
    await AvatarCache.shared.prefetch(authors: big, repository: repository)
    for author in big { await AvatarCache.shared.awaitPending(author.username) }
    check("130 authors of a feed page cost two batch requests and no /about", DietStub.count("user_data_by_account_ids") == 2 && DietStub.count("/about") == 0)
    let first = await AvatarCache.shared.cachedURL(for: "dietuser0")
    let last = await AvatarCache.shared.cachedURL(for: "dietuser129")
    check("every author's picture is known afterwards, so no row asks", first == "https://styles.example/t2_diet0.png" && last == "https://styles.example/t2_diet129.png")
    await AvatarCache.shared.prefetch(authors: big, repository: repository)
    check("the next page with the same authors sends nothing", DietStub.count("user_data_by_account_ids") == 2)

    // A mixed page: only the authors nobody has asked for go out.
    let more = [(username: "DietUser1", fullname: "t2_diet1"), (username: "DietNew", fullname: "t2_dietnew")]
    await AvatarCache.shared.prefetch(authors: more, repository: repository)
    await AvatarCache.shared.awaitPending("DietNew")
    check("a page with one new author asks for that author only",
          DietStub.count("user_data_by_account_ids") == 3 && DietStub.urls.last?.absoluteString.contains("t2_dietnew") == true
          && DietStub.urls.last?.absoluteString.contains("t2_diet1,") == false)

    // While Reddit's rate limit hold runs, nothing is looked up.
    await AvatarCache.shared.clear()
    DietStub.urls = []
    RedditRateLimitHold.shared.record(reset: "300", retryAfter: nil)
    await AvatarCache.shared.prefetch(authors: big, repository: repository)
    RedditRateLimitHold.shared.reset()
    check("no batch is sent during the rate limit hold", DietStub.count("user_data_by_account_ids") == 0)
    await AvatarCache.shared.clear()
    DietStub.reset()
}

@MainActor func checkOptionalLookupsStandDownDuringHold() async throws {
    struct Counted: Error {}
    actor Hits { var count = 0; func hit() { count += 1 } }
    let created = Date(timeIntervalSinceNow: -86_400)

    // The avatar and NEW badge share one /about; neither asks while the hold runs.
    let profiles = UserProfileSnapshotCache.shared
    await AvatarCache.shared.clear()
    let profileHits = Hits()
    RedditRateLimitHold.shared.record(reset: "300", retryAfter: nil)
    var held = false
    do {
        _ = try await profiles.snapshot(for: "DietHeld") { await profileHits.hit(); return UserProfileSnapshot(iconURL: nil, createdAt: created) }
    } catch is RedditRateLimitHold.Held { held = true } catch {}
    let heldHits = await profileHits.count
    let remembered = await AvatarCache.shared.hasFreshEntry(for: "dietheld")
    check("no /about is sent for a picture during the rate limit hold, and nothing is remembered", held && heldHits == 0 && !remembered)
    check("a lookup the hold stopped is a rate limit, not a missing account",
          ProfileLookupFailure(RedditRateLimitHold.Held()) == .rateLimited)
    RedditRateLimitHold.shared.reset()
    let after = try await profiles.snapshot(for: "DietHeld") { await profileHits.hit(); return UserProfileSnapshot(iconURL: "https://styles.example/h.png", createdAt: created) }
    let afterHits = await profileHits.count
    check("the picture arrives once the hold ends", afterHits == 1 && after.iconURL == "https://styles.example/h.png")
    await AvatarCache.shared.clear()
    await AccountAgeCache.shared.clear()

    // Subreddit icons: known icons still show; an unknown one waits for the hold to end.
    let icons = SubredditIconCache()
    let about = #"{"name":"t5_abc","display_name":"dietsub","title":"D","community_icon":"https://styles.example/s.png"}"#
    let subreddit = try JSONDecoder.reddit.decode(RedditSubreddit.self, from: Data(about.utf8))
    let iconHits = Hits()
    RedditRateLimitHold.shared.record(reset: "300", retryAfter: nil)
    let duringHold = await icons.icons(for: "dietsub") { await iconHits.hit(); return subreddit }
    let duringHits = await iconHits.count
    check("a subreddit icon is not looked up during the rate limit hold", duringHold == nil && duringHits == 0)
    await icons.store(SubredditIconCache.Icons(classic: nil, community: "https://styles.example/k.png"), for: "knownsub")
    let known = await icons.icons(for: "knownsub") { await iconHits.hit(); return subreddit }
    check("an icon already known still shows during the hold", known?.community == "https://styles.example/k.png")
    RedditRateLimitHold.shared.reset()
    let later = await icons.icons(for: "dietsub") { await iconHits.hit(); return subreddit }
    let laterHits = await iconHits.count
    check("the icon is fetched once the hold ends", later?.community == "https://styles.example/s.png" && laterHits == 1)

    // Link previews: a walled page's Reddit lookup waits, and the miss is not remembered.
    let session = DietStub.session()
    await LinkPreviewCache.shared.clear()
    DietStub.reset()
    DietStub.respond = { url in
        url.host?.contains("reddit.com") == true ? (200, #"{"data":{"children":[]}}"#) : (403, "")
    }
    let link = URL(string: "https://news.example/walled-story")!
    RedditRateLimitHold.shared.record(reset: "300", retryAfter: nil)
    let heldPreview = await LinkPreviewFetcher.preview(for: link, session: session)
    let heldRequests = DietStub.count("reddit.com")
    let heldKnown = await LinkPreviewCache.shared.cached(for: link).isKnown
    check("a walled link asks Reddit for nothing during the rate limit hold", heldPreview == nil && heldRequests == 0)
    check("...and the missing card is not remembered as a link with no preview", !heldKnown)
    RedditRateLimitHold.shared.reset()
    _ = await LinkPreviewFetcher.preview(for: link, session: session)
    let afterRequests = DietStub.count("reddit.com")
    let afterKnown = await LinkPreviewCache.shared.cached(for: link).isKnown
    check("the lookup goes out once the hold ends and its answer is remembered", afterRequests >= 1 && afterKnown)
    await LinkPreviewCache.shared.clear()
    DietStub.reset()
}

@MainActor func checkLinkPreviewLookupsAreTrimmed() async throws {
    let session = DietStub.session()
    let url = URL(string: "https://news.example/story")!
    func outcome(_ json: String) -> String {
        let object = try! JSONSerialization.jsonObject(with: Data(json.utf8))
        switch LinkPreviewFetcher.redditInfoOutcome(object, url: url) {
        case .preview: return "preview"
        case .noPreview: return "noPreview"
        case .noSubmission: return "noSubmission"
        }
    }
    check("Reddit with no submission of an address says so", outcome(#"{"data":{"children":[]}}"#) == "noSubmission")
    check("Reddit with submissions that carry no picture says so", outcome(#"{"data":{"children":[{"data":{"title":"t","thumbnail":"self"}}]}}"#) == "noPreview")
    check("a submission with a picture is a preview", outcome(#"{"data":{"children":[{"data":{"title":"t","thumbnail":"https://b.thumbs.example/x.jpg"}}]}}"#) == "preview")
    check("an unreadable answer is not an invitation to try the sibling", outcome("{}") == "noPreview")

    // The www sibling is a second request, so it is sent only when Reddit has no submission of the first.
    func lookups(_ name: String, info: (Int, String)) async -> (info: Int, other: Int) {
        await LinkPreviewCache.shared.clear()
        DietStub.reset()
        DietStub.respond = { u in u.host?.contains("reddit.com") == true ? info : (403, "") }
        let link = URL(string: "https://news.example/\(name)")!
        _ = await LinkPreviewFetcher.preview(for: link, session: session)
        return (DietStub.count("api/info.json"), DietStub.count("reddit.com") - DietStub.count("api/info.json"))
    }
    let unknown = await lookups("a", info: (200, #"{"data":{"children":[]}}"#))
    check("a link Reddit has no submission of tries both host spellings", unknown.info == 2)
    let wallOnly = await lookups("b", info: (200, #"{"data":{"children":[{"data":{"title":"t","thumbnail":"self"}}]}}"#))
    check("a link whose submissions have no picture is asked once", wallOnly.info == 1)
    let limited = await lookups("c", info: (429, "{}"))
    check("a refused lookup is not repeated for the sibling", limited.info == 1)
    let failed = await lookups("d", info: (500, ""))
    check("a failed lookup is not repeated for the sibling", failed.info == 1)

    // A deleted Bluesky post settles at one request, once per launch.
    func bluesky(_ rkey: String, handle: (Int, String), thread: (Int, String)) async -> (card: LinkPreview?, requests: Int, page: Int, repeated: Int) {
        await LinkPreviewCache.shared.clear()
        DietStub.reset()
        DietStub.respond = { u in
            if u.path.contains("resolveHandle") { return handle }
            if u.path.contains("getPostThread") { return thread }
            return (u.host?.contains("reddit.com") == true) ? (200, #"{"data":{"children":[]}}"#) : (403, "")
        }
        let link = URL(string: "https://bsky.app/profile/gone.example/post/\(rkey)")!
        let card = await LinkPreviewFetcher.preview(for: link, session: session)
        let first = DietStub.urls.count
        _ = await LinkPreviewFetcher.preview(for: link, session: session)
        _ = await LinkPreviewFetcher.preview(for: link, session: session)
        return (card, first, DietStub.count("bsky.app/profile"), DietStub.urls.count - first)
    }
    let deleted = await bluesky("3aaa", handle: (200, #"{"did":"did:plc:abc"}"#), thread: (400, #"{"error":"InvalidRequest"}"#))
    check("a deleted Bluesky post is one request and a settled card, not a page fetch and Reddit lookups",
          deleted.requests == 2 && deleted.page == 0 && DietStub.count("reddit.com") == 0
          && deleted.card?.kind == .socialPost && deleted.card?.postText == "This post is no longer available."
          && deleted.card?.authorHandle == "@gone.example")
    check("...and showing the card again asks nothing", deleted.repeated == 0)
    let notFound = await bluesky("3bbb", handle: (200, #"{"did":"did:plc:abc"}"#),
                                 thread: (200, #"{"thread":{"$type":"app.bsky.feed.defs#notFoundPost","uri":"at://x"}}"#))
    check("a notFoundPost answer settles the same way", notFound.card?.postText == "This post is no longer available." && notFound.page == 0)
    let unknownHandle = await bluesky("3ccc", handle: (400, #"{"error":"InvalidRequest"}"#), thread: (200, "{}"))
    check("a handle that no longer resolves settles too", unknownHandle.card?.postText == "This post is no longer available." && unknownHandle.requests == 1)
    let limitedBsky = await bluesky("3ddd", handle: (200, #"{"did":"did:plc:abc"}"#), thread: (429, "{}"))
    check("a rate limited Bluesky answer is not a deleted post", limitedBsky.card?.postText != "This post is no longer available.")
    await LinkPreviewCache.shared.clear()
    DietStub.reset()
}

@MainActor func checkSubscriptionWalkUsesFullPages() async throws {
    // A web session spends one request per page: every page of the walk asks for 100, never Reddit's default 25.
    let session = DietStub.session()
    let repository = try dietRepository(session: session)
    DietStub.reset()
    DietStub.respond = { url in
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let after = items.first { $0.name == "after" }?.value
        let row = { (id: String) in #"{"kind":"t5","data":{"name":"t5_\#(id)","display_name":"sub\#(id)","title":"S"}}"# }
        switch after {
        case nil: return (200, #"{"kind":"Listing","data":{"after":"t5_p1","children":[\#(row("a"))]}}"#)
        case "t5_p1": return (200, #"{"kind":"Listing","data":{"after":"t5_p2","children":[\#(row("b"))]}}"#)
        default: return (200, #"{"kind":"Listing","data":{"after":null,"children":[\#(row("c"))]}}"#)
        }
    }
    let subscribed = try await repository.fetchSubscribedSubreddits()
    let limits = DietStub.urls.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "limit" }?.value }
    check("the subscription walk reads every page and asks for 100 on each", subscribed.count == 3 && limits == ["100", "100", "100"])
    DietStub.reset()
}
