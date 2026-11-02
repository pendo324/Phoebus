import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Image caching
//
// The avatar, account-age and image caches: what they remember about a
// failed lookup, how concurrent callers share one fetch, and the sizes
// pictures are decoded at.

private actor Counter {
    var count = 0
    func hit() { count += 1 }
}

@MainActor func checkProfileLookupFailures() async throws {
    check("a 404, 403 and 410 are a missing account",
          [404, 403, 410].allSatisfy { ProfileLookupFailure(RedditAPIError.httpError(status: $0, body: "")) == .noSuchAccount })
    check("a 429 is rate limiting, a 500 and 503 transient",
          ProfileLookupFailure(RedditAPIError.httpError(status: 429, body: "")) == .rateLimited
          && ProfileLookupFailure(RedditAPIError.httpError(status: 500, body: "")) == .transient
          && ProfileLookupFailure(RedditAPIError.httpError(status: 503, body: "")) == .transient)
    check("a dropped connection and a timeout are transient",
          ProfileLookupFailure(URLError(.notConnectedToInternet)) == .transient && ProfileLookupFailure(URLError(.timedOut)) == .transient)
    check("a cancelled lookup is neither a miss nor an error",
          ProfileLookupFailure(CancellationError()) == .cancelled && ProfileLookupFailure(URLError(.cancelled)) == .cancelled)
    check("only a missing account is a miss to remember",
          ProfileLookupFailure.noSuchAccount.isDefinitiveMiss && ![ProfileLookupFailure.rateLimited, .cancelled, .transient].contains(where: \.isDefinitiveMiss))

    // Account age: a second call re-fetches after URLError and 429, not after a 404.
    let cache = AccountAgeCache.shared
    await cache.clear()
    let created = Date(timeIntervalSinceNow: -3 * 24 * 60 * 60)
    let offline = Counter()
    _ = await cache.createdDate(for: "smokeoffline") { await offline.hit(); throw URLError(.notConnectedToInternet) }
    let recovered = await cache.createdDate(for: "smokeoffline") { await offline.hit(); return created }
    let offlineCount = await offline.count
    check("a transient failure is retried by the next row and the date then arrives", offlineCount == 2 && recovered == created)

    let limited = Counter()
    _ = await cache.createdDate(for: "smokelimited") { await limited.hit(); throw RedditAPIError.httpError(status: 429, body: "") }
    _ = await cache.createdDate(for: "smokelimited") { await limited.hit(); return created }
    let limitedCount = await limited.count
    check("a 429 is not remembered as a missing account", limitedCount == 2)

    let missing = Counter()
    _ = await cache.createdDate(for: "smokegone") { await missing.hit(); throw RedditAPIError.httpError(status: 404, body: "") }
    _ = await cache.createdDate(for: "smokegone") { await missing.hit(); return created }
    let missingCount = await missing.count
    check("a 404 is remembered, so a missing account is asked once", missingCount == 1)

    // While Reddit's rate limit hold runs, no lookup is sent and nothing is cached.
    RedditRateLimitHold.shared.record(reset: "300", retryAfter: nil)
    let held = Counter()
    let heldDate = await cache.createdDate(for: "smokeheld") { await held.hit(); return created }
    RedditRateLimitHold.shared.reset()
    let afterHold = await cache.createdDate(for: "smokeheld") { await held.hit(); return created }
    let heldCount = await held.count
    check("no age lookup is sent during the rate limit hold, and it works once the hold ends",
          heldDate == nil && afterHold == created && heldCount == 1)
    await cache.clear()

    // Avatars: the same rule.
    let avatars = AvatarCache.shared
    await avatars.clear()
    await avatars.store(failure: .transient, for: "SmokeFlaky")
    await avatars.store(failure: .rateLimited, for: "SmokeFlaky")
    await avatars.store(failure: .cancelled, for: "SmokeFlaky")
    let flakyFresh = await avatars.hasFreshEntry(for: "smokeflaky")
    check("transient, rate limited and cancelled lookups leave no avatar entry", !flakyFresh)
    await avatars.store(failure: .noSuchAccount, for: "SmokeFlaky")
    let goneFresh = await avatars.hasFreshEntry(for: "smokeflaky")
    let goneURL = await avatars.cachedURL(for: "smokeflaky")
    check("a missing account is remembered as having no avatar", goneFresh && goneURL == nil)
    await avatars.clear()
}

@MainActor func checkInFlightCoalescer() async throws {
    struct Failed: Error {}
    let coalescer = InFlightCoalescer<String, Int>()

    let runs = Counter()
    let results = await withTaskGroup(of: Int?.self) { group -> [Int?] in
        for _ in 0..<100 {
            group.addTask { try? await coalescer.value(for: "a") { await runs.hit(); try await Task.sleep(nanoseconds: 100_000_000); return 7 } }
        }
        var all: [Int?] = []
        for await result in group { all.append(result) }
        return all
    }
    let aRuns = await runs.count
    check("100 concurrent callers for one key run the work once and all get its result", aRuns == 1 && results.count == 100 && results.allSatisfy { $0 == 7 })

    let other = try await coalescer.value(for: "b") { await runs.hit(); return 9 }
    let afterB = await runs.count
    check("another key runs its own work", other == 9 && afterB == 2)

    let again = try await coalescer.value(for: "a") { await runs.hit(); return 8 }
    let afterAgain = await runs.count
    check("a finished key is not kept: the next caller runs the work again", again == 8 && afterAgain == 3)

    let failing = Counter()
    do {
        _ = try await coalescer.value(for: "f") { await failing.hit(); throw Failed() }
        check("a throwing run reaches its caller", false)
    } catch {
        check("a throwing run reaches its caller", error is Failed)
    }
    let retried = try await coalescer.value(for: "f") { await failing.hit(); return 1 }
    let failingRuns = await failing.count
    check("a failed run is not retained: the next caller retries and succeeds", retried == 1 && failingRuns == 2)

    // A caller cancelled while waiting stops waiting but leaves the shared work to the rest.
    let slow = Counter()
    let first = Task { try await coalescer.value(for: "c") { await slow.hit(); try await Task.sleep(nanoseconds: 200_000_000); return 5 } }
    try await Task.sleep(nanoseconds: 30_000_000)
    let second = Task { try await coalescer.value(for: "c") { await slow.hit(); return 6 } }
    try await Task.sleep(nanoseconds: 30_000_000)
    first.cancel()
    let survivor = try await second.value
    let slowRuns = await slow.count
    check("cancelling the caller that started the work does not cancel it for the others", survivor == 5 && slowRuns == 1)
    let idle = await coalescer.runningCount
    check("nothing is left running once the work ends", idle == 0)
}

@MainActor func checkHTTPCacheLimits() async throws {
    check("the HTTP cache holds 32 MB in memory and 256 MB on disk",
          HTTPCacheLimits.memoryCapacity == 32 * 1024 * 1024 && HTTPCacheLimits.diskCapacity == 256 * 1024 * 1024)
    check("the Storage footer and the explainer name the disk size",
          HTTPCacheLimits.storageFooter == "Maximum of around 256 MB." && HTTPCacheLimits.explainerNote.contains("256 MB"))
}

@MainActor func checkInboxAvatarPolicy() async throws {
    check("an inbox sender with a username gets an avatar lookup",
          InboxAvatarPolicy.avatarUsername(forAuthor: "AHMessengerBot") == "AHMessengerBot"
          && InboxAvatarPolicy.avatarUsername(forAuthor: "a-b_9") == "a-b_9")
    check("no avatar lookup for a deleted, empty or subreddit-notice sender",
          InboxAvatarPolicy.avatarUsername(forAuthor: "[deleted]") == nil && InboxAvatarPolicy.avatarUsername(forAuthor: "") == nil
          && InboxAvatarPolicy.avatarUsername(forAuthor: "u/pendo324 is permanently banned from r/ApolloReborn") == nil)
    check("a chat row named after one person looks that person up",
          InboxAvatarPolicy.avatarUsername(forChatTitle: "pendo324") == "pendo324")
    check("no lookup for a chat row titled by a notice, several names, an id or the fallback",
          InboxAvatarPolicy.avatarUsername(forChatTitle: "u/pendo324 is permanently banned from r/ApolloReborn") == nil
          && InboxAvatarPolicy.avatarUsername(forChatTitle: "alice, bob") == nil
          && InboxAvatarPolicy.avatarUsername(forChatTitle: "t2_abc123") == nil
          && InboxAvatarPolicy.avatarUsername(forChatTitle: "Conversation") == nil)
}

private func subreddit(_ name: String, icon: String? = nil, community: String? = nil) throws -> RedditSubreddit {
    var json: [String: Any] = ["name": "t5_\(name)", "display_name": name, "title": name]
    if let icon { json["icon_img"] = icon }
    if let community { json["community_icon"] = community }
    return try JSONDecoder().decode(RedditSubreddit.self, from: JSONSerialization.data(withJSONObject: json))
}

@MainActor func checkSubredditIconCache() async throws {
    let cache = SubredditIconCache()
    let fetches = Counter()

    // Rows of one subreddit that ask together share a single /about.
    let infos = await withTaskGroup(of: String?.self) { group -> [String?] in
        for _ in 0..<20 {
            group.addTask {
                try? await cache.info(for: "Anime") {
                    await fetches.hit(); try await Task.sleep(nanoseconds: 100_000_000)
                    return try subreddit("anime", icon: "https://x/classic.png?a=1&amp;b=2", community: "https://x/community.png")
                }.displayName
            }
        }
        var all: [String?] = []
        for await name in group { all.append(name) }
        return all
    }
    let fetchCount = await fetches.count
    check("twenty rows of one subreddit make one /about", fetchCount == 1 && infos.allSatisfy { $0 == "anime" })
    let known = await cache.lookup("anime")
    check("the answer's icons are remembered, with &amp; fixed, for both icon settings",
          known?.url(useCommunityIcons: false) == "https://x/classic.png?a=1&b=2" && known?.url(useCommunityIcons: true) == "https://x/community.png")

    // The header's /about teaches the cache what the icon view would have fetched.
    _ = try await cache.info(for: "Headered") { try subreddit("Headered", community: "https://x/h.png") }
    let header = await cache.lookup("headered")
    check("a fetch for the feed header seeds the icon", header?.url(useCommunityIcons: true) == "https://x/h.png")

    // Seeding from the subscription list does not overwrite a live answer.
    await cache.seed(from: [try subreddit("anime", icon: "https://x/stale.png"), try subreddit("fresh", icon: "https://x/fresh.png")])
    let afterSeed = await cache.lookup("anime")
    let seeded = await cache.lookup("fresh")
    check("seeding fills unknown subreddits and leaves known ones alone",
          afterSeed?.url(useCommunityIcons: true) == "https://x/community.png" && seeded?.url(useCommunityIcons: false) == "https://x/fresh.png")

    // A private or banned subreddit is remembered as having no icon for five minutes; a blip is not.
    let now = Date()
    let gone = Counter()
    for _ in 0..<2 {
        _ = try? await cache.info(for: "banned", now: now) { await gone.hit(); throw RedditAPIError.httpError(status: 403, body: "") }
    }
    let missing = await cache.lookup("banned", now: now.addingTimeInterval(60))
    check("a subreddit Reddit refuses is remembered as having no icon",
          missing == SubredditIconCache.Icons(classic: nil, community: nil))
    let expired = await cache.lookup("banned", now: now.addingTimeInterval(SubredditIconCache.missRetryDelay + 1))
    check("...for five minutes, then asked again", expired == nil)
    _ = try? await cache.info(for: "offline", now: now) { throw URLError(.notConnectedToInternet) }
    let blip = await cache.lookup("offline", now: now)
    check("a failed connection is not remembered as a subreddit without an icon", blip == nil)

    await cache.removeAll()
    let cleared = await cache.lookup("anime")
    check("removeAll forgets every subreddit", cleared == nil)
}

@MainActor func checkAvatarDownsampleTargets() async throws {
    let avatar256 = CGSize(width: 256, height: 256)
    let row = ImageDownsampleTarget.avatar(pointSize: 27, scale: 3)
    let header = ImageDownsampleTarget.avatar(pointSize: 96, scale: 3)
    check("a 27pt avatar row decodes at 81 px", row.maxPixelSize(for: avatar256, screenPixelWidth: 1170) == 81)
    check("a 96pt profile header decodes the 256 px picture as it is", header.maxPixelSize(for: avatar256, screenPixelWidth: 1170) == nil)
    check("the header asks for more pixels than the row, so the row's bitmap is never stretched into it",
          header.cacheKey == "288" && row.cacheKey == "81" && header.cacheKey != row.cacheKey)
    check("a picture smaller than the target is not scaled up",
          row.maxPixelSize(for: CGSize(width: 64, height: 64), screenPixelWidth: 1170) == nil)
    check("a huge picture is brought down to the header's pixels",
          header.maxPixelSize(for: CGSize(width: 2000, height: 1000), screenPixelWidth: 1170) == 288)
    check("an unreadable size still gets the target", row.maxPixelSize(for: .zero, screenPixelWidth: 1170) == 81)
    check("the screen-width and full-size targets are unchanged",
          ImageDownsampleTarget.screenWidth.maxPixelSize(for: CGSize(width: 2340, height: 1170), screenPixelWidth: 1170) == 1170
          && ImageDownsampleTarget.screenWidth.maxPixelSize(for: avatar256, screenPixelWidth: 1170) == nil
          && ImageDownsampleTarget.none.maxPixelSize(for: avatar256, screenPixelWidth: 1170) == nil
          && ImageDownsampleTarget.galleryTile.cacheKey == "1280")
}

@MainActor func checkImageURLCleaning() async throws {
    check("&amp; in an image URL is unescaped and the signed query survives",
          ImageURLCleaning.cleaned("https://styles.redditmedia.com/a.png?width=256&amp;height=256&amp;s=abc") == "https://styles.redditmedia.com/a.png?width=256&height=256&s=abc")
    check("an empty or missing URL is no URL", ImageURLCleaning.cleaned("") == nil && ImageURLCleaning.cleaned(nil) == nil)
    let avatars = AvatarCache.shared
    await avatars.clear()
    await avatars.store(url: "https://x/a.png?w=1&amp;s=2", for: "Escaped")
    await avatars.store(url: "", for: "Blank")
    let escaped = await avatars.cachedURL(for: "escaped")
    let blank = await avatars.cachedURL(for: "blank")
    let blankKnown = await avatars.hasFreshEntry(for: "blank")
    check("the avatar cache stores the unescaped URL", escaped == "https://x/a.png?w=1&s=2")
    check("an empty avatar URL is stored as a known 'no avatar'", blank == nil && blankKnown)
    await avatars.clear()
}

@MainActor func checkUserProfileSnapshotCache() async throws {
    let shared = UserProfileSnapshotCache.shared
    let avatars = AvatarCache.shared, ages = AccountAgeCache.shared
    let created = Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
    let snapshot = UserProfileSnapshot(iconURL: "https://x/a.png?w=1&amp;s=2", createdAt: created)
    await avatars.clear(); await ages.clear()

    // The avatar asks first; the badge then reads the date without a request.
    let aboutCalls = Counter()
    _ = try await shared.snapshot(for: "SmokeBoth") { await aboutCalls.hit(); return snapshot }
    let badgeDate = await ages.createdDate(for: "smokeboth") { await aboutCalls.hit(); return Date() }
    let avatarURL = await avatars.cachedURL(for: "smokeboth")
    let aboutAfterAvatar = await aboutCalls.count
    check("one /about serves the avatar and then the badge", aboutAfterAvatar == 1 && badgeDate == created && avatarURL == "https://x/a.png?w=1&s=2")

    // The badge asks first; the avatar then finds its picture.
    let aboutCalls2 = Counter()
    let date = await ages.createdDate(for: "SmokeBadgeFirst") {
        try await shared.snapshot(for: "SmokeBadgeFirst") { await aboutCalls2.hit(); return snapshot }.createdAt
    }
    let freshAvatar = await avatars.hasFreshEntry(for: "smokebadgefirst")
    let aboutAfterBadge = await aboutCalls2.count
    check("one /about serves the badge and then the avatar", aboutAfterBadge == 1 && date == created && freshAvatar)

    // Rows asking together share the request.
    let aboutCalls3 = Counter()
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask {
                _ = try? await shared.snapshot(for: "SmokeBusy") { await aboutCalls3.hit(); try await Task.sleep(nanoseconds: 80_000_000); return snapshot }
            }
        }
    }
    let busyCalls = await aboutCalls3.count
    check("ten concurrent callers for one author make one /about", busyCalls == 1)

    // A picture the batch lookup already supplied is not swapped for /about's.
    await avatars.store(url: "https://i.redd.it/snoovatar/batch.png", for: "SmokeBatched")
    _ = try await shared.snapshot(for: "SmokeBatched") { snapshot }
    let batched = await avatars.cachedURL(for: "smokebatched")
    let batchedAge = await ages.cachedCreatedDate(for: "smokebatched")
    check("a fresh batch picture is kept, and /about still supplies the date", batched == "https://i.redd.it/snoovatar/batch.png" && batchedAge == created)

    // A missing account is a miss for both; a failed connection is neither.
    do { _ = try await shared.snapshot(for: "SmokeGone") { throw RedditAPIError.httpError(status: 404, body: "") } } catch {}
    let goneAvatar = await avatars.hasFreshEntry(for: "smokegone")
    let goneAge = await ages.hasFreshEntry(for: "smokegone")
    check("a missing account is recorded as a miss for the avatar and the badge", goneAvatar && goneAge)
    do { _ = try await shared.snapshot(for: "SmokeBlip") { throw URLError(.notConnectedToInternet) } } catch {}
    let blipAvatar = await avatars.hasFreshEntry(for: "smokeblip")
    let blipAge = await ages.hasFreshEntry(for: "smokeblip")
    check("a failed connection is recorded for neither", !blipAvatar && !blipAge)
    await avatars.clear(); await ages.clear()
}

@MainActor func checkShortLivedLookup() async throws {
    struct Blip: Error {}
    let lookup = ShortLivedLookup<Int>()
    let calls = Counter()

    // Ten concurrent askers share one request.
    let results = await withTaskGroup(of: Int?.self) { group -> [Int?] in
        for _ in 0..<10 {
            group.addTask { try? await lookup.value(for: "a", maxAge: 300) { await calls.hit(); try await Task.sleep(nanoseconds: 80_000_000); return 5 } }
        }
        var all: [Int?] = []
        for await r in group { all.append(r) }
        return all
    }
    let afterConcurrent = await calls.count
    check("ten concurrent askers make one request", afterConcurrent == 1 && results.allSatisfy { $0 == 5 })

    // Later askers within maxAge are answered without one; after it, they ask again.
    let sequential = try await lookup.value(for: "a", maxAge: 300) { await calls.hit(); return 6 }
    let afterSequential = await calls.count
    check("a later asker inside maxAge reads the kept answer", sequential == 5 && afterSequential == 1)
    let expired = try await lookup.value(for: "a", maxAge: 300, now: Date().addingTimeInterval(301)) { await calls.hit(); return 7 }
    let afterExpiry = await calls.count
    check("after maxAge the next asker asks again", expired == 7 && afterExpiry == 2)

    // maxAge 0 asks now, and what it learns is what later askers get.
    let fresh = try await lookup.value(for: "a", maxAge: 0) { await calls.hit(); return 8 }
    let later = try await lookup.value(for: "a", maxAge: 300) { await calls.hit(); return 9 }
    let afterFresh = await calls.count
    check("a fresh ask bypasses the kept answer and refreshes it", fresh == 8 && later == 8 && afterFresh == 3)

    // forget (a subscribe, a quarantine opt-in) makes the next ask go out.
    await lookup.forget("a")
    let afterForget = try await lookup.value(for: "a", maxAge: 300) { await calls.hit(); return 10 }
    check("forgetting an answer makes the next ask go out", afterForget == 10)

    // A failure is not kept: the next asker retries, and keys are independent.
    let flaky = Counter()
    _ = try? await lookup.value(for: "b", maxAge: 300) { await flaky.hit(); throw Blip() }
    let recovered = try await lookup.value(for: "b", maxAge: 300) { await flaky.hit(); return 1 }
    let flakyCalls = await flaky.count
    check("a transient failure is not kept, the next asker retries", recovered == 1 && flakyCalls == 2)

    // The table does not grow without bound.
    let small = ShortLivedLookup<Int>(limit: 10)
    for i in 0..<40 { _ = try await small.value(for: "k\(i)", maxAge: 300) { i } }
    let kept = await small.keptCount
    check("a long session keeps a bounded number of answers", kept <= 10)
}

// MARK: - Repeated lookups through the repository

private final class AboutStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var paths: [String] = []
    nonisolated(unsafe) static var fail = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.paths.append(url.path)
        let status = Self.fail ? 503 : 200
        let user = #"{"id":"u1","name":"exampleuser","comment_karma":1,"link_karma":2,"created_utc":1700000000}"#
        let body: String
        if url.path.contains("/about") && url.path.contains("/user/") {
            body = #"{"kind":"t2","data":\#(user)}"#
        } else if url.path.contains("/about") {
            body = #"{"kind":"t5","data":{"name":"t5_abc","display_name":"anime","title":"Anime","user_is_subscriber":false}}"#
        } else if url.path.contains("/me") {
            body = user
        } else {
            body = "{}"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor func checkRepeatedLookupsShareARequest() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AboutStub.self]
    let session = URLSession(configuration: configuration)
    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt",
                                          expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let auth = RedditAuthClient(session: session, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    let repository = RedditRepository(client: RedditAPIClient(auth: auth, session: session))
    func count(_ part: String) -> Int { AboutStub.paths.filter { $0.contains(part) }.count }

    // A thread's moderator check and a feed header's icon ask for one subreddit together and again later.
    AboutStub.paths = []; AboutStub.fail = false
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<5 { group.addTask { _ = try? await repository.fetchSubredditInfo(name: "anime") } }
    }
    _ = try await repository.fetchSubredditInfo(name: "Anime")
    check("five concurrent and one later /r/anime/about askers make one request", count("/r/anime/about") == 1)
    _ = try await repository.fetchSubredditInfo(name: "anime", fresh: true)
    check("a fresh ask goes out", count("/r/anime/about") == 2)

    // Subscribing and a quarantine opt-in make the kept answer stale.
    try await repository.subscribe(subredditName: "anime", subscribe: true)
    _ = try await repository.fetchSubredditInfo(name: "anime")
    check("the about data is asked again after subscribing", count("/r/anime/about") == 3)
    _ = try await repository.fetchSubredditInfo(name: "anime")
    check("...and is kept again after that", count("/r/anime/about") == 3)
    try await repository.setQuarantineOptIn(subredditName: "anime", optIn: true)
    _ = try await repository.fetchSubredditInfo(name: "anime")
    check("a quarantine opt-in makes the next about read go to Reddit", count("/r/anime/about") == 4)

    // A failure is not kept.
    AboutStub.fail = true
    do { _ = try await repository.fetchSubredditInfo(name: "other") } catch {}
    AboutStub.fail = false
    _ = try await repository.fetchSubredditInfo(name: "other")
    check("a failed about read is retried, not kept", count("/r/other/about") == 2)

    // The own-profile tab and the tab icon both read the account's /about.
    AboutStub.paths = []
    async let tabIcon = repository.fetchUserProfile(username: "ExampleUser")
    async let profileTab = repository.fetchUserProfile(username: "exampleuser")
    _ = try await (tabIcon, profileTab)
    _ = try await repository.fetchUserProfile(username: "exampleuser")
    check("the tab icon, the profile tab and a later read share one /user/<me>/about", count("/user/") == 1)
    _ = try await repository.fetchUserProfile(username: "exampleuser", fresh: true)
    check("a profile read after an edit goes out", count("/user/") == 2)

    // Identity: every screen that needs the signed-in name shares one /api/v1/me.
    AboutStub.paths = []
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<4 { group.addTask { _ = try? await repository.fetchIdentity() } }
    }
    _ = try await repository.fetchIdentity()
    check("the launch's identity reads make one /api/v1/me", count("/api/v1/me") == 1)
    _ = try await repository.fetchIdentity(fresh: true)
    check("a sign-in check reads it fresh", count("/api/v1/me") == 2)
    _ = try await repository.fetchUnreadInboxCount()
    check("the unread badge reuses an identity answer a moment old", count("/api/v1/me") == 2)
    let badge = RedditRepository(client: RedditAPIClient(auth: auth, session: session))
    AboutStub.paths = []
    _ = try await badge.fetchUnreadInboxCount()
    _ = try await badge.fetchIdentity()
    check("a badge poll with nothing recent asks, and identity readers then share its answer", count("/api/v1/me") == 1)
}
