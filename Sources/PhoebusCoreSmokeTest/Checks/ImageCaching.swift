import Foundation
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
