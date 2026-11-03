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
