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
