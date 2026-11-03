import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Listing paging through a stubbed transport

private final class ListingStub: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
    }

    nonisolated(unsafe) static var requests: [URL] = []
    nonisolated(unsafe) static var respond: @Sendable (URL) -> Reply = { _ in Reply() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requests.append(url)
        let reply = Self.respond(url)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil,
                                                              headerFields: reply.headers)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedRepository() throws -> RedditRepository {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ListingStub.self]
    let session = URLSession(configuration: configuration)
    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt",
                                          expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let auth = RedditAuthClient(session: session, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    return RedditRepository(client: RedditAPIClient(auth: auth, session: session))
}

private func query(_ url: URL, _ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

/// `pages` pages of `perPage` subscriptions each, cursor `p<N>` to the next, the last with a null `after`.
private func subscriptionPages(pages: Int, perPage: Int = 100) -> @Sendable (URL) -> ListingStub.Reply {
    { url in
        let page = query(url, "after").flatMap { Int($0.dropFirst()) } ?? 0
        let children = (0..<perPage).map { index -> String in
            let number = page * perPage + index
            return #"{"kind":"t5","data":{"id":"s\#(number)","name":"t5_s\#(number)","display_name":"sub\#(number)","title":"Sub \#(number)"}}"#
        }
        let after = page + 1 < pages ? #""p\#(page + 1)""# : "null"
        let body = #"{"kind":"Listing","data":{"after":\#(after),"before":null,"children":[\#(children.joined(separator: ","))]}}"#
        return .init(body: Data(body.utf8))
    }
}

@MainActor func checkListingPaging() async throws {
    let repository = try stubbedRepository()

    // Subscriptions: every page, however many an account has (a 1,935-subscription account is 20 pages).
    ListingStub.requests = []
    ListingStub.respond = subscriptionPages(pages: 15)
    let fifteenPages = try await repository.fetchSubscribedSubreddits()
    check("an account with 15 pages of subscriptions lists all 1,500", fifteenPages.count == 1500)
    check("...each asked for once, 100 to a page", ListingStub.requests.count == 15
          && ListingStub.requests.allSatisfy { query($0, "limit") == "100" })

    ListingStub.respond = subscriptionPages(pages: 20)
    let twentyPages = try await repository.fetchSubscribedSubreddits()
    check("a 2,000-subscription account lists all 2,000, in order",
          twentyPages.count == 2000 && twentyPages.first?.displayName == "sub0" && twentyPages.last?.displayName == "sub1999")

    ListingStub.requests = []
    ListingStub.respond = subscriptionPages(pages: 1, perPage: 7)
    let short = try await repository.fetchSubscribedSubreddits()
    check("a short account is one request", short.count == 7 && ListingStub.requests.count == 1)

    // A cursor that never advances must not spin forever.
    ListingStub.requests = []
    ListingStub.respond = { _ in
        .init(body: Data(#"{"kind":"Listing","data":{"after":"same","children":[]}}"#.utf8))
    }
    let stuck = try await repository.fetchSubscribedSubreddits()
    check("a repeated cursor ends the walk", stuck.isEmpty && ListingStub.requests.count <= 2)
}

// MARK: - A refused page is a failed load, not the end of the listing

private let rateLimitJSON = Data(#"{"message":"Too Many Requests","error":429}"#.utf8)
private let blockPageHTML = Data("<html><head><title>Blocked</title></head><body>whoa there, pardner</body></html>".utf8)

/// The thrown HTTP status, "decode" for a decoding failure, "none" when nothing was thrown.
@MainActor private func outcome(_ work: () async throws -> Void) async -> String {
    do {
        try await work()
        return "none"
    } catch RedditAPIError.httpError(let status, _) {
        return "\(status)"
    } catch is DecodingError {
        return "decode"
    } catch {
        return "other"
    }
}

@MainActor func checkRefusedPagesFailTheLoad() async throws {
    let repository = try stubbedRepository()

    // A feed's page 2 that Reddit refuses throws, so the feed keeps its cursor; the same page then loads.
    ListingStub.requests = []
    ListingStub.respond = { _ in .init(status: 429, headers: ["Content-Type": "text/html"], body: blockPageHTML) }
    let refusedHTML = await outcome { _ = try await repository.fetchListing(subreddit: "swift", after: "t3_cursor") }
    check("a feed page answered with an HTML 429 throws, not an empty page", refusedHTML == "429")
    ListingStub.respond = { _ in .init(status: 429, headers: ["Content-Type": "application/json"], body: rateLimitJSON) }
    let refusedJSON = await outcome { _ = try await repository.fetchListing(subreddit: "swift", after: "t3_cursor") }
    check("...and so does a JSON 429", refusedJSON == "429")
    ListingStub.respond = subscriptionPages(pages: 1, perPage: 3)
    let retried = try await repository.fetchListing(subreddit: "swift", after: "t3_cursor")
    check("asking for the same cursor again loads it", retried.data.children.count == 3
          && ListingStub.requests.count == 3 && ListingStub.requests.allSatisfy { query($0, "after") == "t3_cursor" })

    // The first page: an error, never an empty listing that reads as "No posts".
    ListingStub.respond = { _ in .init(status: 403, headers: ["Content-Type": "text/html"], body: blockPageHTML) }
    let blocked = await outcome { _ = try await repository.fetchListing(subreddit: "swift") }
    check("a 403 block page on the first page throws", blocked == "403")
    ListingStub.respond = { _ in .init(status: 200, headers: ["Content-Type": "text/html"], body: blockPageHTML) }
    let htmlListing = await outcome { _ = try await repository.fetchListing(subreddit: "swift") }
    check("a 200 HTML page in place of a listing throws", htmlListing == "decode")
    ListingStub.respond = { _ in .init(status: 503, headers: ["Content-Type": "text/html"], body: blockPageHTML) }
    let outage = await outcome { _ = try await repository.fetchListing(subreddit: "swift") }
    check("an HTML 503 throws", outage == "503")
    check("a 429 reads as rate limiting to the user",
          UserFacingError.message(for: RedditAPIError.httpError(status: 429, body: ""))
            == "Reddit is rate-limiting requests. Try again in a minute.")
}

// MARK: - Comment loads survive a rate-limit body

@MainActor func checkCommentLoadsSurviveRateLimitBodies() async throws {
    let repository = try stubbedRepository()

    // The body Reddit sends with a 429, arriving with a 200 and with a 429, through every comment-thread load.
    for status in [200, 429] {
        ListingStub.respond = { _ in .init(status: status, headers: ["Content-Type": "application/json"], body: rateLimitJSON) }
        let thrown = status == 200 ? "none" : "429"
        var bodies: [Data] = []
        let thread = await outcome { bodies.append(try await repository.fetchComments(subreddit: "swift", postID: "abc")) }
        check("the comment thread given a \(status) rate-limit body: \(thrown)", thread == thrown)
        let permalink = await outcome {
            bodies.append(try await repository.fetchCommentThread(subreddit: "swift", postID: "abc", commentID: "def"))
        }
        check("a comment permalink given a \(status) rate-limit body: \(thrown)", permalink == thrown)
        for data in bodies {
            let parsed = try? CommentTreeBuilder.parseCommentsResponse(data, postID: "abc")
            check("a rate-limit body is no comment tree", parsed == nil)
            let captured = SiriContentSanitizer.commentsResponse(data)
            check("...and Siri capture takes nothing from it", captured.post == nil && captured.comments.isEmpty)
        }
        let single = await outcome { _ = try await repository.fetchPost(subreddit: "swift", postID: "abc") }
        check("fetching one post given a \(status) rate-limit body throws", single == (status == 200 ? "decode" : "429"))
        let more = await outcome { _ = try await repository.fetchMoreChildren(linkFullname: "t3_abc", childIDs: ["x", "y"]) }
        check("\"more replies\" given a \(status) rate-limit body: \(thrown)", more == thrown)
    }
    ListingStub.respond = { _ in .init(status: 429, headers: ["Content-Type": "application/json"], body: rateLimitJSON) }
    let byName = await outcome { _ = try await repository.fetchPost(fullname: "t3_abc") }
    check("a post by fullname given a 429 throws", byName == "429")

    // Valid JSON that is not [post listing, comment listing] parses to no tree.
    for body in ["[]", "{}", "null", "42", #""text""#, "[{}]", #"[{"data":{}},{"data":{"children":"x"}}]"#,
                 "[1,2]", #"["a","b","c"]"#, #"[{"kind":"Listing"},{"kind":"Listing","data":null}]"#] {
        let data = Data(body.utf8)
        let parsed = try? CommentTreeBuilder.parseCommentsResponse(data, postID: "abc")
        let captured = SiriContentSanitizer.commentsResponse(data)
        check("\(body) is no comment tree and nothing for Siri capture", parsed == nil && captured.post == nil && captured.comments.isEmpty)
    }
}
