import Foundation
import PhoebusCore

// MARK: - Web-session moderator requests with the web bearer
//
// Reborn "Removal reasons" (#1292), "Mod user lists" (#1304) and "Moderator
// Mail" (#1311): a web-session account sends the endpoints Reddit refuses over
// its cookie to oauth.reddit.com with its web bearer.

private actor MintLog {
    private var count = 0
    func next() -> Int { count += 1; return count }
    func total() -> Int { count }
}

private func anonymousJWT() -> String {
    let payload: [String: Any] = ["exp": Date().addingTimeInterval(3600).timeIntervalSince1970, "sub": "loid_abc123"]
    let b64 = try! JSONSerialization.data(withJSONObject: payload).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(b64).signature"
}

@MainActor func checkWebSessionModeratorRequestsWebBearer() async throws {
    typealias R = WebBearerRouting
    check("removal reasons go to the bearer, list and by id",
          R.needsBearer(path: "/api/v1/swift/removal_reasons")
            && R.needsBearer(path: "/api/v1/swift/removal_reasons/abc123")
            && R.needsBearer(path: "api/v1/swift/removal_reasons?raw_json=1"))
    check("every modactions action goes to the bearer",
          R.needsBearer(path: "/api/v1/modactions/removal_reasons")
            && R.needsBearer(path: "/api/v1/modactions/removal_link_message")
            && R.needsBearer(path: "/api/v1/modactions/removal_comment_message"))
    check("the user lists and declining an invite go to the bearer",
          ["contributors", "banned", "muted", "moderators", "moderators_invited", "decline_mod_invite"]
            .allSatisfy { R.needsBearer(path: "/api/v1/swift/\($0)") })
    check("ban, invite, unban and accepting an invite go to the bearer",
          ["friend", "unfriend", "accept_moderator_invite"].allSatisfy { R.needsBearer(path: "/r/swift/api/\($0)") })
    check("mod notes and their recent list use the web bearer",
          R.needsBearer(path: "/api/mod/notes?subreddit=a&user=b") && R.needsBearer(path: "/api/mod/notes/recent"))
    check("new modmail's mute and unmute go to the bearer",
          R.needsBearer(path: "/api/mod/conversations/abc/mute")
            && R.needsBearer(path: "/api/mod/conversations/abc/unmute")
            && R.needsBearer(path: "/api/mod/conversations"))
    check("sending a private message goes to the bearer, www answers its cookie with 401",
          R.needsBearer(path: "/api/compose") && R.needsBearer(path: "api/compose?raw_json=1")
            && R.needsBearer(path: "/API/Compose/"))
    check("only the compose endpoint itself is routed, not look-alikes",
          !R.needsBearer(path: "/api/compose/extra") && !R.needsBearer(path: "/message/compose")
            && !R.needsBearer(path: "/api/comment") && !R.needsBearer(path: "/api"))
    check("matching ignores case and a trailing slash",
          R.needsBearer(path: "/API/v1/Swift/Removal_Reasons/") && R.needsBearer(path: "/r/Swift/api/FRIEND"))
    check("ordinary cookie requests stay on the cookie",
          !R.needsBearer(path: "/api/remove") && !R.needsBearer(path: "/api/approve")
            && !R.needsBearer(path: "/api/v1/me") && !R.needsBearer(path: "/r/swift/about/banned")
            && !R.needsBearer(path: "/r/swift/api/selectflair") && !R.needsBearer(path: "/api/v1/swift/unknown")
            && !R.needsBearer(path: "/api/mod") && !R.needsBearer(path: "/api/v1/swift/removal_reasons/a/b")
            && !R.needsBearer(path: "/api/v1/modactions/removal_reasons/extra") && !R.needsBearer(path: ""))

    func session(_ username: String, cookie: String = "loid=1; reddit_session=x") -> WebSessionCredential {
        WebSessionCredential(username: username, cookieHeader: cookie, modhash: "mh")
    }

    // The cache: mint once per account, share concurrent mints, re-mint on demand.
    let log = MintLog()
    let cache = WebBearerCache { _ in
        let n = await log.next()
        try await Task.sleep(nanoseconds: 20_000_000)
        return makeChatJWT(expiringIn: 3600 + Double(n))
    }
    let first = try await cache.bearer(for: session("Mod"))
    let second = try await cache.bearer(for: session("mod"))
    var mints = await log.total()
    check("a minted bearer is cached per account, whatever the name's case", first == second && mints == 1)
    let other = try await cache.bearer(for: session("other"))
    mints = await log.total()
    check("another account mints its own", other != first && mints == 2)
    let forced = try await cache.bearer(for: session("mod"), forceMint: true)
    let afterForced = try await cache.bearer(for: session("mod"))
    mints = await log.total()
    check("a forced mint replaces the cached bearer", forced != first && afterForced == forced && mints == 3)
    await cache.clear(account: "MOD")
    _ = try await cache.bearer(for: session("mod"))
    mints = await log.total()
    check("a cleared bearer is minted again", mints == 4)

    let sharedLog = MintLog()
    let sharing = WebBearerCache { _ in
        let n = await sharedLog.next()
        try await Task.sleep(nanoseconds: 50_000_000)
        return makeChatJWT(expiringIn: 3600 + Double(n))
    }
    let tokens = try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<4 { group.addTask { try await sharing.bearer(for: session("racer")) } }
        var collected: [String] = []
        for try await token in group { collected.append(token) }
        return collected
    }
    mints = await sharedLog.total()
    check("concurrent requests for one account share a single mint", Set(tokens).count == 1 && mints == 1)

    let stored = makeChatJWT(expiringIn: 3600)
    let storedLog = MintLog()
    let storedCache = WebBearerCache { _ in _ = await storedLog.next(); return "minted" }
    let ownCookie = "reddit_session=x; token_v2=\(stored)"
    let own = try await storedCache.bearer(for: session("mod", cookie: ownCookie))
    mints = await storedLog.total()
    check("the session's own token_v2 is used without a mint", own == stored && mints == 0)
    _ = try await storedCache.bearer(for: session("mod", cookie: ownCookie), forceMint: true)
    mints = await storedLog.total()
    check("a forced mint skips the session's token_v2", mints == 1)

    let anonymousCache = WebBearerCache { _ in anonymousJWT() }
    var refused = false
    do { _ = try await anonymousCache.bearer(for: session("mod")) } catch { refused = true }
    check("a signed-out cookie's anonymous token is refused", refused)
}

// MARK: - Subreddit-scoped writes over the cookie
//
// Reborn "Post flair and wiki saves" (#1309): www 404s POST /r/<sub>/api/<action>
// for the cookie, so a web-session account sends flair and wiki saves as
// POST /api/<action> with the subreddit in an `r` form field.
@MainActor func checkWebSessionSubredditWritesUseRField() async throws {
    let flair = WebSubredditWrite.rewrite(path: "/r/swift/api/selectflair",
                                          parameters: ["link": "t3_abc", "flair_template_id": "tpl"])
    check("selectflair goes to /api/selectflair with r and its other fields kept",
          flair?.path == "/api/selectflair"
            && flair?.parameters == ["link": "t3_abc", "flair_template_id": "tpl", "r": "swift"])
    check("setflairenabled goes to /api/setflairenabled",
          WebSubredditWrite.rewrite(path: "/r/swift/api/setflairenabled", parameters: ["flair_enabled": "true"])?.path
            == "/api/setflairenabled")
    let wiki = WebSubredditWrite.rewrite(path: "/r/Swift/api/wiki/edit",
                                         parameters: ["page": "config/automoderator", "content": "x"])
    check("wiki/edit keeps its two-segment action and the subreddit's case",
          wiki?.path == "/api/wiki/edit" && wiki?.parameters["r"] == "Swift" && wiki?.parameters["page"] == "config/automoderator")
    check("an r field already in the body is kept",
          WebSubredditWrite.rewrite(path: "/r/swift/api/selectflair", parameters: ["r": "other"])?.parameters["r"] == "other")
    check("a trailing slash and any case are accepted",
          WebSubredditWrite.rewrite(path: "/R/swift/API/SelectFlair/", parameters: [:])?.path == "/api/selectflair")
    check("other writes are left alone",
          WebSubredditWrite.rewrite(path: "/api/selectflair", parameters: [:]) == nil
            && WebSubredditWrite.rewrite(path: "/r/swift/api/friend", parameters: [:]) == nil
            && WebSubredditWrite.rewrite(path: "/r/swift/api/flairselector", parameters: [:]) == nil
            && WebSubredditWrite.rewrite(path: "/r/swift/api/wiki/revert", parameters: [:]) == nil
            && WebSubredditWrite.rewrite(path: "/r/swift/about/rules", parameters: [:]) == nil)
    check("the encoded body carries r for the subreddit",
          FormEncoding.encode(flair?.parameters ?? [:]).contains("r=swift"))
}
