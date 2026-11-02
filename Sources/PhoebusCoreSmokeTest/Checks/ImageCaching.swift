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
