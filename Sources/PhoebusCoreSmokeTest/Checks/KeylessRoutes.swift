import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Keyless route fallback
//
// Reborn "Keyless route fallback": www.reddit.com answers some reads for the
// session cookie with its 403 block page, so an API-Key-Free account sends
// them by an ordered list of routes.

private final class KeylessRouteStub: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status = 200
        var contentType = "application/json"
        var body = #"{"ok":true}"#
        /// The URL the answer comes from, when a redirect landed somewhere else.
        var finalURL: URL?
    }

    struct Captured {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var captured: [Captured] = []
    nonisolated(unsafe) static var respond: @Sendable (URLRequest) -> Reply = { _ in Reply() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.captured.append(Captured(url: url, method: request.httpMethod ?? "GET",
                                      headers: request.allHTTPHeaderFields ?? [:], body: Self.body(of: request)))
        let reply = Self.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: reply.finalURL ?? url, statusCode: reply.status, httpVersion: nil,
                                                              headerFields: ["Content-Type": reply.contentType])!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private let blockPage = KeylessRouteStub.Reply(status: 403, contentType: "text/html; charset=utf-8",
                                               body: "<html><body>whoa there, pardner!</body></html>")

@MainActor func checkKeylessRouteTable() {
    typealias T = KeylessRouteTable
    func routes(_ method: String, _ path: String) -> [KeylessRoute] { T.routes(method: method, path: path) }

    check("/api/info and /api/morechildren go www with /.json, then old, whatever the spelling",
          routes("GET", "/api/info") == [.wwwDotJSON, .old] && routes("GET", "/api/info.json") == [.wwwDotJSON, .old]
            && routes("GET", "/API/Info/.json?id=t3_a") == [.wwwDotJSON, .old]
            && routes("POST", "/api/morechildren.json") == [.wwwDotJSON, .old]
            && routes("GET", "/api/morechildren") == [.wwwDotJSON, .old])
    check("post and subreddit search go oauth with the cookie, then old",
          routes("GET", "/search.json") == [.oauth, .old] && routes("GET", "/subreddits/search.json") == [.oauth, .old]
            && routes("GET", "/r/swift/search.json") == [.oauth, .old] && routes("GET", "/r/swift+ios/search.json") == [.oauth, .old])
    check("r/all and everything under it go oauth, api, then old",
          routes("GET", "/r/all") == [.oauth, .api, .old] && routes("GET", "/r/All/hot.json") == [.oauth, .api, .old]
            && routes("GET", "/r/all/top.json") == [.oauth, .api, .old])
    check("...r/all's filter forms too, and r/all/search is r/all rather than a community search",
          routes("GET", "/r/all-funny/hot.json") == [.oauth, .api, .old] && routes("GET", "/r/all+pics/new.json") == [.oauth, .api, .old]
            && routes("GET", "/r/all-funny-pics/top.json") == [.oauth, .api, .old]
            && routes("GET", "/r/all/search.json") == [.oauth, .api, .old])
    check("everything else stays on www, popular and single subreddits included",
          routes("GET", "/r/popular/hot.json") == [.www] && routes("GET", "/r/allergies/hot.json") == [.www]
            && routes("GET", "/r/swift+ios/hot.json") == [.www] && routes("GET", "/user/x/submitted.json") == [.www]
            && routes("GET", "/comments/abc.json") == [.www] && routes("GET", "/r/swift/comments/abc.json") == [.www]
            && routes("GET", "/api/me.json") == [.www] && routes("GET", "/hot.json") == [.www])
    check("a search with a different segment count is not a search entry",
          routes("GET", "/search/extra.json") == [.www] && routes("GET", "/r/swift/search/extra.json") == [.www])
    check("no write has a second route, and the morechildren POST is the only POST with one",
          ["/api/vote", "/api/comment", "/api/save", "/api/submit", "/api/info", "/r/all/hot", "/search"]
            .allSatisfy { routes("POST", $0) == [.www] }
            && routes("DELETE", "/api/info") == [.www] && routes("PUT", "/r/all/hot") == [.www]
            && T.mayResend(method: "POST", path: "/api/morechildren.json") && !T.mayResend(method: "POST", path: "/api/vote"))
    check("every built-in entry other than the morechildren POST is a GET",
          T.builtIn.filter { $0.method != "GET" }.map(\.pattern) == ["/api/morechildren"])
    check("routes name their hosts and write /api endpoints as /.json only on www-dotjson",
          KeylessRoute.wwwDotJSON.host == "www.reddit.com" && KeylessRoute.old.host == "old.reddit.com"
            && KeylessRoute.api.host == "api.reddit.com" && KeylessRoute.oauth.host == "oauth.reddit.com"
            && KeylessRoute.wwwDotJSON.path(for: "/api/info.json") == "/api/info/.json"
            && KeylessRoute.wwwDotJSON.path(for: "/api/morechildren.json") == "/api/morechildren/.json"
            && KeylessRoute.old.path(for: "/api/info.json") == "/api/info.json"
            && KeylessRoute.api.path(for: "/r/all/hot.json") == "/r/all/hot.json")
}

@MainActor func checkKeylessRouteResponses() {
    typealias R = KeylessRouteResponse
    check("a 403 text/html answer is the block page, in any case or charset",
          R.isBlockPage(status: 403, contentType: "text/html") && R.isBlockPage(status: 403, contentType: "Text/HTML; charset=utf-8"))
    check("a 403 with JSON, a 200 page, a 429 and a 5xx are not the block page",
          !R.isBlockPage(status: 403, contentType: "application/json; charset=UTF-8") && !R.isBlockPage(status: 200, contentType: "text/html")
            && !R.isBlockPage(status: 429, contentType: "text/html") && !R.isBlockPage(status: 503, contentType: "text/html")
            && !R.isBlockPage(status: 403, contentType: nil))
    check("old.reddit.com's redirect to its sign-in page is a refusal",
          R.isSignInGate(finalURL: URL(string: "https://old.reddit.com/login?dest=x"), contentType: "text/html; charset=UTF-8")
            && R.isSignInGate(finalURL: URL(string: "https://www.reddit.com/login/"), contentType: "text/html")
            && R.isRefusal(status: 200, contentType: "text/html", finalURL: URL(string: "https://old.reddit.com/login")))
    check("...but a page that merely mentions login, another host or a JSON answer is not",
          !R.isSignInGate(finalURL: URL(string: "https://old.reddit.com/r/swift/login"), contentType: "text/html")
            && !R.isSignInGate(finalURL: URL(string: "https://example.com/login"), contentType: "text/html")
            && !R.isSignInGate(finalURL: URL(string: "https://notreddit.com/login"), contentType: "text/html")
            && !R.isSignInGate(finalURL: URL(string: "https://old.reddit.com/login"), contentType: "application/json")
            && !R.isRefusal(status: 200, contentType: "application/json", finalURL: URL(string: "https://old.reddit.com/api/info.json")))
}

@MainActor func checkKeylessRouteHealth() {
    typealias Record = KeylessRouteRecord
    let hour = Record.firstCooldown

    var record = Record()
    check("two refusals in a row start no cooldown", !record.noteRefusal(now: 0) && !record.noteRefusal(now: 1)
            && record.cooldownRemaining(now: 2) == 0)
    check("the third starts one hour", record.noteRefusal(now: 10) && record.cooldownRemaining(now: 10) == hour)
    check("a refusal for a request sent before the cooldown began changes nothing",
          !record.noteRefusal(now: 20) && record.cooldownRemaining(now: 20) == hour - 10)
    check("the cooldown runs out", record.cooldownRemaining(now: 10 + hour) == 0 && record.cooldownRemaining(now: 10 + hour + 1) == 0)
    check("the first try after a cooldown that fails goes straight to two hours",
          record.noteRefusal(now: 10 + hour + 5) && record.cooldownLength == 2 * hour
            && record.cooldownRemaining(now: 10 + hour + 5) == 2 * hour)
    _ = record.noteRefusal(now: 10 + 3 * hour + 10)
    check("...then four, then eight, and stays at eight", record.cooldownLength == 4 * hour)
    _ = record.noteRefusal(now: 10 + 7 * hour + 20)
    check("...eight hours", record.cooldownLength == Record.longestCooldown && Record.longestCooldown == 8 * hour)
    _ = record.noteRefusal(now: 10 + 15 * hour + 30)
    check("...and no more", record.cooldownLength == 8 * hour)
    record.noteSuccess()
    check("a success clears the cooldown and the streak",
          record.cooldownRemaining(now: 10 + 15 * hour + 40) == 0 && record.cooldownLength == 0 && record.consecutiveRefusals == 0
            && record.successes == 1)
    var broken = Record()
    _ = broken.noteRefusal(now: 0); _ = broken.noteRefusal(now: 1); broken.noteSuccess()
    check("a success in between restarts the count of three", !broken.noteRefusal(now: 2) && !broken.noteRefusal(now: 3)
            && broken.noteRefusal(now: 4))

    let health = KeylessRouteHealth()
    func choose(_ account: String, _ path: String, tried: Set<KeylessRoute> = [], now: TimeInterval) -> KeylessRoute? {
        health.choose(account: account, method: "GET", path: path, tried: tried, now: now)
    }
    check("the first route of the entry is chosen to begin with", choose("alice", "/r/all/hot.json", now: 0) == .oauth)
    for t in 0..<3 { health.noteRefusal(account: "alice", method: "GET", path: "/r/all/hot.json", route: .oauth, now: TimeInterval(t)) }
    check("three refusals skip the route", choose("alice", "/r/all/hot.json", now: 3) == .api)
    check("...for that account and endpoint only",
          choose("bob", "/r/all/hot.json", now: 3) == .oauth && choose("alice", "/search.json", now: 3) == .oauth)
    check("...and for every path under the same entry, the filter forms too",
          choose("alice", "/r/all/top.json", now: 3) == .api && choose("alice", "/r/all-funny/new.json", now: 3) == .api)
    check("a resend skips what was tried", choose("alice", "/r/all/hot.json", tried: [.api], now: 3) == .old
            && choose("alice", "/r/all/hot.json", tried: [.api, .old], now: 3) == nil)
    check("the route comes back after the hour", choose("alice", "/r/all/hot.json", now: 2 + hour + 1) == .oauth)
    for route in [KeylessRoute.oauth, .api, .old] {
        for t in 0..<3 { health.noteRefusal(account: "carol", method: "GET", path: "/r/all/hot.json", route: route, now: TimeInterval(t)) }
    }
    check("when every route is cooling the first is still tried, but a resend stops",
          choose("carol", "/r/all/hot.json", now: 5) == .oauth && choose("carol", "/r/all/hot.json", tried: [.oauth], now: 5) == nil)
    health.noteSuccess(account: "alice", method: "GET", path: "/r/all/hot.json", route: .oauth)
    check("a success puts the route back", choose("alice", "/r/all/hot.json", now: 5) == .oauth)
    check("an endpoint with one route is always www and keeps no record",
          health.choose(account: "alice", method: "GET", path: "/r/popular/hot.json", tried: [], now: 0) == .www
            && !health.noteRefusal(account: "alice", method: "GET", path: "/r/popular/hot.json", route: .www, now: 0))
}

@MainActor func checkKeylessRouteFallbackRequests() async throws {
    typealias Stub = KeylessRouteStub
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Stub.self]
    let session = URLSession(configuration: configuration)

    func makeClient(_ username: String) async -> RedditAPIClient {
        let auth = RedditAuthClient(session: session, credentialStore: InMemoryCredentialStore(), webSessionStore: InMemoryWebSessionStore())
        await auth.setWebSession(WebSessionCredential(username: username, cookieHeader: "reddit_session=abc; loid=1", modhash: "mh"))
        return RedditAPIClient(auth: auth, session: session)
    }
    func hosts() -> [String] { Stub.captured.compactMap { $0.url.host } }
    func paths() -> [String] { Stub.captured.map { $0.url.path } }
    func refusing(_ blocked: Set<String>, signInGateOn gate: Set<String> = []) -> @Sendable (URLRequest) -> Stub.Reply {
        { request in
            let host = request.url?.host ?? ""
            if blocked.contains(host) { return blockPage }
            if gate.contains(host) {
                return Stub.Reply(status: 200, contentType: "text/html; charset=UTF-8", body: "<html>Log in</html>",
                                  finalURL: URL(string: "https://old.reddit.com/login?dest=x"))
            }
            return Stub.Reply(body: #"{"from":"\#(host)"}"#)
        }
    }
    func reset(_ respond: @escaping @Sendable (URLRequest) -> Stub.Reply) {
        Stub.captured = []
        Stub.respond = respond
    }
    func body(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
    func status(of error: Error?) -> Int? {
        if case RedditAPIError.httpError(let status, _)? = error as? RedditAPIError { return status }
        return nil
    }

    KeylessRouteHealth.shared.reset()
    let client = await makeClient("fallbackuser")

    // /api/info: www with /.json, then old.
    reset(refusing([]))
    let served = try await client.get(path: "/api/info", parameters: ["id": "t3_a"])
    check("/api/info goes to www as /api/info/.json when it isn't refused",
          hosts() == ["www.reddit.com"] && paths() == ["/api/info/.json"] && body(served).contains("www.reddit.com"))
    check("...with the cookie, a browser identity and no bearer",
          Stub.captured.first?.headers["Cookie"] == "reddit_session=abc; loid=1" && Stub.captured.first?.headers["Authorization"] == nil
            && Stub.captured.first?.headers["User-Agent"] == RedditAPIClient.webBrowserUserAgent
            && Stub.captured.first?.url.query?.contains("id=t3_a") == true)

    reset(refusing(["www.reddit.com"]))
    let resent = try await client.get(path: "/api/info", parameters: ["id": "t3_a"])
    check("the block page sends the same read to old.reddit.com",
          hosts() == ["www.reddit.com", "old.reddit.com"] && paths() == ["/api/info/.json", "/api/info.json"] && body(resent).contains("old.reddit.com")
            && Stub.captured.last?.headers["Cookie"] == "reddit_session=abc; loid=1" && Stub.captured.last?.url.query == Stub.captured.first?.url.query)

    // Three refusals put www on cooldown for this account.
    reset(refusing(["www.reddit.com"]))
    _ = try await client.get(path: "/api/info", parameters: ["id": "t3_a"])
    _ = try await client.get(path: "/api/info", parameters: ["id": "t3_a"])
    check("a refusing route is tried on every read until its third refusal", hosts() == Array(repeating: ["www.reddit.com", "old.reddit.com"], count: 2).flatMap { $0 })
    reset(refusing(["www.reddit.com"]))
    _ = try await client.get(path: "/api/info", parameters: ["id": "t3_a"])
    check("...then skipped: the next read goes straight to old", hosts() == ["old.reddit.com"])
    let other = await makeClient("otheruser")
    reset(refusing(["www.reddit.com"]))
    _ = try await other.get(path: "/api/info", parameters: ["id": "t3_a"])
    check("...for that account only", hosts() == ["www.reddit.com", "old.reddit.com"])

    // morechildren: a POST that only reads is resent with its body.
    KeylessRouteHealth.shared.reset()
    reset(refusing(["www.reddit.com"]))
    let more = try await client.post(path: "/api/morechildren.json", parameters: ["link_id": "t3_a", "children": "b,c"])
    check("the morechildren POST is resent to old.reddit.com with the same form body",
          hosts() == ["www.reddit.com", "old.reddit.com"] && Stub.captured.map(\.method) == ["POST", "POST"]
            && paths() == ["/api/morechildren/.json", "/api/morechildren.json"]
            && Stub.captured[0].body == Stub.captured[1].body && body(Stub.captured[1].body).contains("children=b%2Cc")
            && Stub.captured[1].headers["X-Modhash"] == "mh" && body(more).contains("old.reddit.com"))

    // Search: oauth with the cookie and no bearer, then old.
    KeylessRouteHealth.shared.reset()
    reset(refusing([]))
    _ = try await client.get(path: "/search", parameters: ["q": "swift"])
    check("post search goes to oauth.reddit.com with the cookie and no bearer",
          hosts() == ["oauth.reddit.com"] && paths() == ["/search.json"]
            && Stub.captured[0].headers["Cookie"] == "reddit_session=abc; loid=1" && Stub.captured[0].headers["Authorization"] == nil)
    for path in ["/search", "/subreddits/search", "/r/swift/search", "/r/swift+ios/search"] {
        reset(refusing(["oauth.reddit.com"]))
        _ = try await client.get(path: path, parameters: ["q": "x"])
        check("a refused \(path) falls back to old.reddit.com",
              hosts() == ["oauth.reddit.com", "old.reddit.com"] && paths() == [path + ".json", path + ".json"]
                && Stub.captured[1].headers["Cookie"] == "reddit_session=abc; loid=1" && Stub.captured[1].headers["Authorization"] == nil)
    }

    // r/all: oauth, api, old.
    KeylessRouteHealth.shared.reset()
    reset(refusing(["oauth.reddit.com", "api.reddit.com"]))
    let listing = try await client.get(path: "/r/all/hot", parameters: ["limit": "25"])
    check("r/all falls through oauth and api to old.reddit.com, the listing keeping its .json",
          hosts() == ["oauth.reddit.com", "api.reddit.com", "old.reddit.com"]
            && paths() == ["/r/all/hot.json", "/r/all/hot.json", "/r/all/hot.json"] && body(listing).contains("old.reddit.com"))
    for path in ["/r/all-funny-pics/new", "/r/all+pics/top", "/r/all"] {
        reset(refusing(["oauth.reddit.com"]))
        _ = try await client.get(path: path)
        check("\(path) is sent by the r/all routes", hosts().first == "oauth.reddit.com" && hosts().count == 2 && hosts().last == "api.reddit.com")
    }

    // Refusals by sign-in gate, and all routes refusing.
    KeylessRouteHealth.shared.reset()
    reset(refusing(["oauth.reddit.com"], signInGateOn: ["api.reddit.com"]))
    let gated = try? await client.get(path: "/r/all/rising")
    check("old.reddit.com's sign-in redirect counts as a refusal like the block page",
          hosts() == ["oauth.reddit.com", "api.reddit.com", "old.reddit.com"] && gated.map(body)?.contains("old.reddit.com") == true)
    KeylessRouteHealth.shared.reset()
    reset(refusing(["oauth.reddit.com", "api.reddit.com"], signInGateOn: ["old.reddit.com"]))
    var allRefused: Error?
    do { _ = try await client.get(path: "/r/all/rising") } catch { allRefused = error }
    check("when every route refuses the read fails with the 403, not with the sign-in page as data",
          hosts().count == 3 && status(of: allRefused) == 403)
    check("...and the screen is told Reddit blocked it, not that the feed is private",
          allRefused.flatMap { UserFacingError.message(for: $0) } == "Reddit blocked this request. Try again in a while.")

    // What is not a refusal is not resent.
    KeylessRouteHealth.shared.reset()
    reset { _ in Stub.Reply(status: 429, contentType: "application/json", body: #"{"message":"Too Many Requests","error":429}"#) }
    var limited: Error?
    do { _ = try await client.get(path: "/api/info", parameters: ["id": "t3_a"]) } catch { limited = error }
    RedditRateLimitHold.shared.reset()
    check("a 429 is returned to the caller, not resent", hosts().count == 1 && status(of: limited) == 429)
    reset { _ in Stub.Reply(status: 403, contentType: "application/json", body: #"{"reason":"private"}"#) }
    var privateSub: Error?
    do { _ = try await client.get(path: "/r/all/hot") } catch { privateSub = error }
    check("a 403 with a JSON body is a normal answer, not resent", hosts().count == 1 && status(of: privateSub) == 403)
    reset { _ in Stub.Reply(status: 500, contentType: "text/html", body: "oops") }
    var broken: Error?
    do { _ = try await client.get(path: "/search", parameters: ["q": "x"]) } catch { broken = error }
    check("a 5xx is not resent", hosts().count == 1 && status(of: broken) == 500)

    // Writes are never resent, whatever the answer.
    KeylessRouteHealth.shared.reset()
    reset(refusing(["www.reddit.com"]))
    var voteError: Error?
    do { try await client.post(path: "/api/vote", parameters: ["id": "t3_a", "dir": "1"]) } catch { voteError = error }
    check("a refused write is sent once and fails", hosts() == ["www.reddit.com"] && status(of: voteError) == 403)
    reset(refusing(["www.reddit.com"]))
    var commentError: Error?
    do { try await client.post(path: "/api/comment", parameters: ["thing_id": "t3_a", "text": "x"]) } catch { commentError = error }
    check("...a comment too", hosts().count == 1 && status(of: commentError) == 403)

    // Reads that have no second route are unchanged.
    reset(refusing([]))
    _ = try await client.get(path: "/r/popular/hot", parameters: ["limit": "25"])
    check("a listing with no entry still goes to www as <path>.json", hosts() == ["www.reddit.com"] && paths() == ["/r/popular/hot.json"])

    // An API-key account has none of this.
    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt", expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let oauthAuth = RedditAuthClient(session: session, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    let oauthClient = RedditAPIClient(auth: oauthAuth, session: session)
    reset(refusing([]))
    _ = try await oauthClient.get(path: "/api/info", parameters: ["id": "t3_a"])
    check("an API-key account reads /api/info from oauth.reddit.com with its bearer, as before",
          hosts() == ["oauth.reddit.com"] && paths() == ["/api/info"] && Stub.captured[0].headers["Authorization"] == "Bearer tok")

    #if DEBUG
    KeylessRouteHealth.shared.reset()
    KeylessRouteDebug.blockedRoutes = [.wwwDotJSON]
    reset(refusing([]))
    let forced = try await client.get(path: "/api/info", parameters: ["id": "t3_a"])
    KeylessRouteDebug.blockedRoutes = []
    check("the debug switch counts a route as refused without sending anything to it",
          hosts() == ["old.reddit.com"] && body(forced).contains("old.reddit.com"))
    #endif
    KeylessRouteHealth.shared.reset()
}
