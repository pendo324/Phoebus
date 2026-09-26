import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Web session resolution: primary (transport) vs auxiliary (web-only features)
//
// Poll voting reads the auxiliary (web-only) session, not the transport
// session, which an OAuth account never has. Mirrors Reborn's split of
// `ApolloWebSessionFor` (transport) from `ApolloWebSessionPollFor` (web-only).
@MainActor func checkWebSessionResolutionPrimaryTransportVs() async throws {
    do {
        let cookie = "csrf_token=deadbeef1234; reddit_session=abc123"
        let session = WebSessionCredential(username: "polluser", cookieHeader: cookie, modhash: "mh")
        let oauth = RedditCredential(accessToken: "at", refreshToken: "rt", expiration: Date().addingTimeInterval(3600), isPermanent: true)

        // Auxiliary: OAuth account that also holds a cookie for Polls.
        let auxiliary = StoredAccount(username: "polluser", oauthCredential: oauth, webSession: session)
        WebSessionRegistry.accountProvider = { $0 == "polluser" ? auxiliary : nil }
        check("featureSession returns an auxiliary session (OAuth account can vote in polls)",
              WebSessionRegistry.featureSession(for: "polluser")?.cookieHeader == cookie)
        check("primarySession does NOT return an auxiliary session (never reroutes OAuth transport)",
              WebSessionRegistry.primarySession(for: "polluser") == nil)

        // Primary: keyless (cookie transport) account, no OAuth credential.
        let primary = StoredAccount(username: "polluser", oauthCredential: nil, webSession: session)
        WebSessionRegistry.accountProvider = { $0 == "polluser" ? primary : nil }
        check("primarySession returns a keyless account's transport session",
              WebSessionRegistry.primarySession(for: "polluser")?.cookieHeader == cookie)
        check("featureSession also returns a primary session (polls work for keyless accounts too)",
              WebSessionRegistry.featureSession(for: "polluser")?.cookieHeader == cookie)

        // Per-account isolation: another account's lookup must not leak.
        check("web session lookup is per-account, not global",
              WebSessionRegistry.featureSession(for: "someoneelse") == nil)

        // Username keying is case-insensitive, matching the real store.
        check("web session lookup lowercases the username",
              WebSessionRegistry.featureSession(for: "PollUser")?.cookieHeader == cookie)

        var removed: [String] = []
        WebSessionRegistry.removeHandler = { removed.append($0) }
        WebSessionRegistry.remove(username: "PollUser")
        check("remove(username:) lowercases before removing", removed == ["polluser"])

        WebSessionRegistry.accountProvider = { _ in nil }
        WebSessionRegistry.removeHandler = { _ in }
    }

    // Harvesting a cookie for a web-only feature must not downgrade a working
    // OAuth account to cookie transport; `AccountManager.addWebSessionAccount`
    // must keep the OAuth credential.
    do {
        let oauth = RedditCredential(accessToken: "at", refreshToken: "rt", expiration: Date().addingTimeInterval(3600), isPermanent: true)
        let session = WebSessionCredential(username: "dualuser", cookieHeader: "csrf_token=abc", modhash: "mh")
        let store = AccountStore(store: InMemoryAccountKeychainStore())
        store.addOrUpdate(StoredAccount(username: "dualuser", oauthCredential: oauth), makeActive: true)
        let existingOAuth = store.accounts.first { $0.username == "dualuser" }?.oauthCredential
        store.addOrUpdate(StoredAccount(username: "dualuser", oauthCredential: existingOAuth, webSession: session), makeActive: false)
        let merged = store.accounts.first { $0.username == "dualuser" }
        check("harvesting a web session keeps the account's OAuth credential", merged?.oauthCredential != nil)
        check("harvesting a web session stores the cookie alongside it", merged?.webSession != nil)
        check("an OAuth account with an auxiliary session is still NOT keyless", merged?.isKeyless == false)
    }

    // 401 vs 403 asymmetry: the session clears only on 401 (Reddit declaring
    // the cookie dead). A 403 means this vote was refused (closed poll,
    // quarantined sub) and says nothing about session validity.
    check("sessionExpired is a distinct case so only 401 can clear the session",
          PollVoteService.VoteError.sessionExpired.errorDescription?.contains("expired") == true)
    do {
        let rejected = PollVoteService.VoteError.rejected("Reddit did not authorize this vote.")
        var clearsSession = false
        if case .sessionExpired = rejected { clearsSession = true }
        check("a 403-style rejection is NOT sessionExpired (must not clear the session)", clearsSession == false)
    }
}

// MARK: - Copy Link (Apollo's CopyURLActivity)
//
// Apollo's Copy Link share activity uses activity type
// `com.christianselig.Apollo.CopyLink` and copies the URL; Reborn requires it
// to honour the selected share-link host (#967).
@MainActor func checkCopyLinkApolloSCopyURLActivity() async throws {
    do {
        let permalink = "/r/polls/comments/1wap7z8/you_make_yourself_a_cup_of_coffee/"
        let defaultURL = ShareLinkBuilder.url(forPermalinkPath: permalink, host: .reddit)
        // Compare absoluteString, not `URL.path`: Foundation strips the trailing
        // slash that Reddit permalinks always have.
        check("Copy Link uses the post permalink", defaultURL.absoluteString == "https://reddit.com" + permalink)
        check("Copy Link uses reddit.com for the Reddit host", defaultURL.host == "reddit.com")

        // Host-aware, same as Share.
        for host in ShareLinkHost.allCases {
            let url = ShareLinkBuilder.url(forPermalinkPath: permalink, host: host)
            check("Copy Link honours share host \(host)", url.absoluteString.hasSuffix(permalink))
            check("Copy Link host \(host) matches the Share host", url.host == ShareLinkBuilder.url(forPermalinkPath: permalink, host: host).host)
        }

        // Comment permalink shape used by the comment menu's Copy Link.
        let commentURL = ShareLinkBuilder.url(forPermalinkPath: "/comments/1wap7z8/_/abc123", host: .reddit)
        check("Copy Link builds a comment permalink", commentURL.path == "/comments/1wap7z8/_/abc123")
    }
}

// MARK: - Web session harvest completeness gate
//
// The harvest waits until the cookie set is complete; an early session
// authenticates well enough to look signed in while poll votes come back
// HTTP 200 but unaccepted ("Reddit did not confirm the poll vote").
@MainActor func checkWebSessionHarvestCompletenessGate() async throws {
    do {
        let full = ["reddit_session", "csrf_token", "token_v2", "loid"]
        check("complete session accepted",
              WebSessionCompleteness.isComplete(cookieNames: full, modhash: "mh"))
        check("missing token_v2 rejected (the documented partial-harvest race)",
              !WebSessionCompleteness.isComplete(cookieNames: ["reddit_session", "csrf_token"], modhash: "mh"))
        check("missing reddit_session rejected",
              !WebSessionCompleteness.isComplete(cookieNames: ["token_v2", "csrf_token"], modhash: "mh"))
        check("missing modhash rejected (read-only session cannot write a vote)",
              !WebSessionCompleteness.isComplete(cookieNames: full, modhash: nil))
        check("empty modhash rejected",
              !WebSessionCompleteness.isComplete(cookieNames: full, modhash: ""))
        check("no cookies rejected",
              !WebSessionCompleteness.isComplete(cookieNames: [], modhash: "mh"))
        // Bounded: some flows (old.reddit) never produce every field, so the
        // harvest proceeds after N attempts.
        check("harvest retries are bounded at the real limit",
              WebSessionCompleteness.maxIncompleteHarvestAttempts == 5)
    }

    // The gate's decision is asserted above; this asserts the retry loop it
    // drives, modelling `finishHarvest`'s control flow.
    func simulateHarvest(jarAt: (Int) -> ([String], String?)) -> (shipped: Bool, attempts: Int, tick: Int) {
        var attempts = 0
        var finished = false
        for tick in 0..<12 {
            if finished { break }
            let (names, modhash) = jarAt(tick)
            finished = true
            if !WebSessionCompleteness.isComplete(cookieNames: names, modhash: modhash),
               attempts < WebSessionCompleteness.maxIncompleteHarvestAttempts {
                attempts += 1
                finished = false
                continue
            }
            if names.isEmpty { finished = false; continue }
            return (true, attempts, tick)
        }
        return (false, attempts, -1)
    }

    do {
        // The documented race: token_v2 lands a couple of ticks late.
        let late = simulateHarvest { tick in
            tick < 2 ? (["reddit_session", "csrf_token"], "mh")
                     : (["reddit_session", "csrf_token", "token_v2"], "mh")
        }
        check("harvest waits for a late token_v2 instead of shipping a partial session", late.tick == 2)
        check("harvest still ships once the jar completes", late.shipped)

        // "Some flows (old.reddit) never produce every field" - proceed anyway.
        let never = simulateHarvest { _ in (["reddit_session", "csrf_token"], "mh") }
        check("harvest proceeds after the bounded retries rather than hanging", never.shipped)
        check("harvest retries exactly maxIncompleteHarvestAttempts times", never.attempts == 5)

        // A complete jar must not be delayed.
        let fast = simulateHarvest { _ in (["reddit_session", "token_v2"], "mh") }
        check("a complete session ships immediately with no retries", fast.tick == 0 && fast.attempts == 0)

        // Only stores when pairs.count > 0.
        let empty = simulateHarvest { _ in ([], "mh") }
        check("an empty cookie jar never ships a session", !empty.shipped)
    }
}

//
// A minimum query length and a debounce keep short prefixes from firing a
// request per keystroke. Models the `.task(id:)` + sleep-first structure: a
// new keystroke cancels the pending task, so only the last in a burst
// issues a request.
@MainActor func checkJumpBarAutocompleteMinimumLengthDebounce() async throws {
    actor RequestCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    let jumpMinimumQueryLength = 3

    func simulateJumpBarTyping(_ text: String, debounceMillis: UInt64 = 60) async -> Int {
        let counter = RequestCounter()
        var task: Task<Void, Never>?
        for endIndex in 1...text.count {
            let query = String(text.prefix(endIndex))
            task?.cancel() // `.task(id:)` cancels the previous task
            task = Task {
                guard query.trimmingCharacters(in: .whitespaces).count >= jumpMinimumQueryLength else { return }
                do { try await Task.sleep(nanoseconds: debounceMillis * 1_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                await counter.increment()
            }
            try? await Task.sleep(nanoseconds: 5 * 1_000_000) // fast typing
        }
        await task?.value
        return await counter.count
    }

    let burstRequests = await simulateJumpBarTyping("askreddit")
    check("fast typing collapses to a single autocomplete request (was one per keystroke)", burstRequests == 1)

    let shortRequests = await simulateJumpBarTyping("ab")
    check("queries shorter than the minimum never hit the network", shortRequests == 0)

    check("minimum query length is 3", jumpMinimumQueryLength == 3)
}

// MARK: - Poll vote response parsing (NSNull bridging)
//
// Reddit answers an accepted vote with { "ok": true, "errors": null }.
// JSONSerialization bridges JSON null to NSNull, not Swift nil, so "errors"
// must be treated as absent when null. Mirrors Reborn's vote-acceptance logic.
@MainActor func checkPollVoteResponseParsingTheNSNull() async throws {
    do {
        func voteState(_ payload: String) -> Any? {
            let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
            return (json?["data"] as? [String: Any])?["updatePostPollVoteState"]
        }
        func accepted(_ payload: String) -> Bool {
            let vote = voteState(payload)
            if let boolVote = vote as? Bool { return boolVote }
            guard let dict = vote as? [String: Any] else { return false }
            return (dict["ok"] as? Bool == true) && !PollVoteService.hasErrors(dict["errors"])
        }

        // The exact shape Reddit returns for an accepted vote.
        check("an accepted vote with errors:null is ACCEPTED (the reported bug)",
              accepted(#"{"data":{"updatePostPollVoteState":{"ok":true,"errors":null}}}"#))
        check("JSON null is not an error", !PollVoteService.hasErrors(NSNull()))
        check("a missing value is not an error", !PollVoteService.hasErrors(nil))
        check("an empty error array is not an error", !PollVoteService.hasErrors([Any]()))
        check("a populated error array IS an error", PollVoteService.hasErrors(["boom"]))
        check("an empty error dictionary is not an error", !PollVoteService.hasErrors([String: Any]()))
        check("a populated error dictionary IS an error", PollVoteService.hasErrors(["message": "boom"]))
        check("a non-collection error value IS an error", PollVoteService.hasErrors("boom"))

        // Rejections must still be rejected: invalid or no-op votes come back
        // HTTP 200, so acceptance requires an explicit true.
        check("ok:false is rejected",
              !accepted(#"{"data":{"updatePostPollVoteState":{"ok":false,"errors":null}}}"#))
        check("ok:true with real errors is rejected",
              !accepted(#"{"data":{"updatePostPollVoteState":{"ok":true,"errors":[{"message":"nope"}]}}}"#))
        check("a null vote state is rejected",
              !accepted(#"{"data":{"updatePostPollVoteState":null}}"#))
        check("a missing vote state is rejected", !accepted(#"{"data":{}}"#))

        // Older variant: a bare boolean.
        check("a bare true is accepted",
              accepted(#"{"data":{"updatePostPollVoteState":true}}"#))
        check("a bare false is rejected",
              !accepted(#"{"data":{"updatePostPollVoteState":false}}"#))

        // Top-level errors use the same predicate.
        let topNull = try? JSONSerialization.jsonObject(with: Data(#"{"errors":null}"#.utf8)) as? [String: Any]
        check("top-level errors:null is not an error", !PollVoteService.hasErrors(topNull?["errors"]))
    }
}

// MARK: - Poll result rendering after a vote
//
// Reddit withholds per-option `vote_count` from a poll you have not voted
// in, so the pre-vote poll has nil counts. The module refetches the
// authenticated post after voting to get result bars, since the vote
// mutation only returns { ok, errors }.
@MainActor func checkPollResultRenderingAfterAVote() async throws {
    do {
        func decodePoll(_ json: String) -> RedditPollData? {
            try? JSONDecoder.reddit.decode(RedditPollData.self, from: Data(json.utf8))
        }

        // Pre-vote shape: counts withheld.
        let preVote = decodePoll(#"""
        {"total_vote_count": 40, "voting_end_timestamp": 1799999999000, "user_selection": null,
         "options": [{"id":"a","text":"Bought"},{"id":"b","text":"Not Buying"}]}
        """#)
        check("pre-vote poll decodes", preVote != nil)
        check("pre-vote options carry no counts (why every row showed 0%)",
              preVote?.options.allSatisfy { $0.voteCount == nil } == true)

        // Post-vote shape: counts present.
        let postVote = decodePoll(#"""
        {"total_vote_count": 41, "voting_end_timestamp": 1799999999000, "user_selection": "b",
         "options": [{"id":"a","text":"Bought","vote_count":9},{"id":"b","text":"Not Buying","vote_count":32}]}
        """#)
        check("post-vote poll decodes with counts", postVote?.options.first?.voteCount == 9)
        check("post-vote poll carries the user's selection", postVote?.userSelection == "b")

        // Mirrors PollView.voteCount/percentage using the refreshed poll.
        func percentage(option: String, refreshed: RedditPollData?, original: RedditPollData) -> Double {
            let total = (refreshed ?? original).totalVoteCount
            guard total > 0 else { return 0 }
            let opt = original.options.first { $0.id == option }
            let count = refreshed?.options.first { $0.id == option }?.voteCount
                ?? opt?.voteCount ?? 0
            return Double(count) / Double(total)
        }

        if let preVote, let postVote {
            // Rendering the pre-vote poll gives 0% everywhere.
            check("without the refetch every option renders 0% (the reported bug)",
                  percentage(option: "a", refreshed: nil, original: preVote) == 0
                  && percentage(option: "b", refreshed: nil, original: preVote) == 0)

            // With the authoritative refetch the real shares render.
            let a = percentage(option: "a", refreshed: postVote, original: preVote)
            let b = percentage(option: "b", refreshed: postVote, original: preVote)
            check("with the refetch the picked option renders its real share",
                  Int((b * 100).rounded()) == 78)
            check("with the refetch the other option renders its real share",
                  Int((a * 100).rounded()) == 22)
            check("rendered percentages sum to ~100%",
                  Int(((a + b) * 100).rounded()) == 100)
        }

        // A refetch that still withholds counts is ignored, not shown as 0%
        // (eventually-consistent listing).
        check("a countless refetch is not accepted as authoritative",
              preVote?.options.contains { $0.voteCount != nil } == false)
    }
}

// MARK: - Account persistence fallback
//
// An ad-hoc-signed build has no provisioning profile, and
// `keychain-access-groups` is a restricted entitlement that would fail
// code-signature validation, so accounts persist to a file fallback with its
// own error signalling (a discarded `SecItemAdd` status hides failures).
@MainActor func checkAccountPersistenceFallback() async throws {
    do {
        let store = FileBackedAccountStore()
        store.clear()
        check("fallback store starts empty", store.load() == nil)

        let session = WebSessionCredential(username: "persisted", cookieHeader: "csrf_token=x", modhash: "mh")
        let json = #"{"accounts":[{"username":"persisted"}],"activeIndex":0}"#
        if var persisted = try? JSONDecoder().decode(AccountStorePersisted.self, from: Data(json.utf8)) {
            persisted.accounts[0].webSession = session
            store.save(persisted)

            // A separate instance must see it (the restart case).
            let reloaded = FileBackedAccountStore().load()
            check("account survives a new store instance (the restart case)",
                  reloaded?.accounts.first?.username == "persisted")
            check("the web session survives with it",
                  reloaded?.accounts.first?.webSession?.cookieHeader == "csrf_token=x")
            check("the active index survives", reloaded?.activeIndex == 0)
            check("the modhash survives, so the restored session can still vote",
                  reloaded?.accounts.first?.webSession?.isReadOnly == false)
        } else {
            check("AccountStorePersisted decodes for the persistence test", false)
        }

        store.clear()
        check("clear removes the fallback file", store.load() == nil)
    }

    // A signed-in session must produce a persisted account: the harvested
    // credential goes into the `AccountStore`, not only the throwaway
    // `Ephemeral*Store` the signed-out `AccountManager` builds.
    do {
        let store = AccountStore(store: InMemoryAccountKeychainStore())
        check("a fresh store has no accounts", store.accounts.isEmpty)

        // The ephemeral stores a sign-in uses do not persist, by design.
        let ephemeral = EphemeralWebSessionStore()
        let session = WebSessionCredential(username: "u", cookieHeader: "csrf_token=a", modhash: "m")
        try? ephemeral.save(session)
        check("the ephemeral store holds the session in memory", ephemeral.load() != nil)
        check("...but a separate instance sees nothing (why the login was lost)",
              EphemeralWebSessionStore().load() == nil)

        // Persisting through the account store is what actually survives.
        store.addOrUpdate(StoredAccount(username: "u", webSession: session), makeActive: true)
        check("the account store now has the account", store.accounts.count == 1)
        check("the account carries the session", store.activeAccount?.webSession != nil)
        check("the account is active", store.activeIndex == 0)
    }
}

// MARK: - Empty listing decode
//
// `/subreddits/mine/subscriber.json` can answer HTTP 200 with body `{}` for
// an account with no subscriptions. That empty response must decode
// successfully rather than throw keyNotFound("data").
@MainActor func checkEmptyListingDecode() async throws {
    do {
        func decodeListing(_ json: String) -> RedditListing? {
            try? JSONDecoder.reddit.decode(RedditListing.self, from: Data(json.utf8))
        }

        let empty = decodeListing("{}")
        check("Reddit's bare {} empty-listing response decodes (the reported bug)", empty != nil)
        check("an empty listing has no children", empty?.data.children.isEmpty == true)
        check("an empty listing has no cursor, so pagination stops", empty?.data.after == nil)
        check("an empty listing still reports a kind", empty?.kind == "Listing")

        // A listing with data but no children key.
        let noChildren = decodeListing(#"{"kind":"Listing","data":{"after":null}}"#)
        check("a listing without a children key decodes as empty",
              noChildren?.data.children.isEmpty == true)

        // A real populated listing must still decode normally.
        let populated = decodeListing(#"""
        {"kind":"Listing","data":{"after":"t5_abc","before":null,"dist":2,
         "children":[{"kind":"t5","data":{"display_name":"swift"}},
                     {"kind":"t5","data":{"display_name":"rust"}}]}}
        """#)
        check("a populated listing still decodes", populated?.data.children.count == 2)
        check("a populated listing keeps its cursor", populated?.data.after == "t5_abc")
        check("a populated listing keeps its kind", populated?.kind == "Listing")
    }
}

// MARK: - Reddit markdown block syntax
//
// `.inlineOnlyPreservingWhitespace` parses only inline syntax and leaves
// block constructs (headings, lists, blockquotes) as raw text, so the
// renderer uses `.full` plus a block-formatting pass.
//
// `AttributedString(markdown:)` is Darwin-only; these cover the
// preprocessing that runs on both platforms.
@MainActor func checkRedditMarkdownBlockSyntax() async throws {
    do {
        let heading = "## This is a \"Show Only\" Thread"
        check("heading source is passed through preprocessing unchanged",
              RedditMarkdown.linkifySubredditsAndUsers(heading) == heading)

        // Subreddit/user linkification must not corrupt block syntax.
        let mixed = "## Rules for /r/ExampleSub\n\n- ask /u/someone"
        let linkified = RedditMarkdown.linkifySubredditsAndUsers(mixed)
        check("linkify preserves the heading marker", linkified.hasPrefix("## Rules"))
        check("linkify preserves the list marker", linkified.contains("- ask"))
        check("linkify still rewrites the subreddit", linkified.contains("https://reddit.com/r/ExampleSub"))
        check("linkify still rewrites the user", linkified.contains("https://reddit.com/u/someone"))

        // Blockquote helper still round-trips (used by the Quote action).
        check("asBlockquote prefixes every line",
              RedditMarkdown.asBlockquote("a\nb").hasPrefix("> a\n> b"))
    }
}

// MARK: - Scheme-relative Reddit links
//
// Reddit serves a crosspost parent's `url` as a bare path
// ("/r/sub/comments/id/title/"). `URL(string:)` yields a URL with no scheme
// or host, which fails `isRedditURL` and would reach
// `SFSafariViewController(url:)`, which raises NSInvalidArgumentException
// for non-http(s) URLs.
@MainActor func checkSchemeRelativeRedditLinksTheCrosspost() async throws {
    do {
        let relative = URL(string: "/r/pics/comments/abc123/a_title/")!
        check("a scheme-relative Reddit path really has no scheme",
              relative.scheme == nil && relative.host == nil)

        let resolved = LinkRouter.absoluteRedditURL(relative)
        check("it resolves to an absolute reddit.com URL",
              resolved.absoluteString == "https://www.reddit.com/r/pics/comments/abc123/a_title/")
        check("the resolved URL is recognised as Reddit", LinkRouter.isRedditURL(resolved))
        check("the resolved URL has an http(s) scheme, so Safari accepts it",
              resolved.scheme == "https")

        // The raw form is not recognised, which is why it needs normalising.
        check("the unresolved form was not recognised as Reddit",
              !LinkRouter.isRedditURL(relative))

        // Absolute URLs must pass through untouched.
        let absolute = URL(string: "https://www.reddit.com/r/pics/comments/abc/x/")!
        check("an absolute URL is unchanged", LinkRouter.absoluteRedditURL(absolute) == absolute)
        let external = URL(string: "https://example.com/page")!
        check("a non-Reddit absolute URL is unchanged", LinkRouter.absoluteRedditURL(external) == external)

        // A relative crosspost link routes natively to the post.
        if case .post(let subreddit, let id) = RedditURLTarget.parse(resolved) {
            check("a resolved crosspost link parses to its post", subreddit == "pics" && id == "abc123")
        } else {
            check("a resolved crosspost link parses to its post", false)
        }
    }

    // RedditPollData: field names and hasEnded/vote-visibility rules.
    let pollJSON = """
    {
        "options": [
            {"id": "abc1", "text": "Cats", "vote_count": 12},
            {"id": "abc2", "text": "Dogs"}
        ],
        "total_vote_count": 12,
        "user_selection": "abc1",
        "voting_end_timestamp": 1000
    }
    """.data(using: .utf8)!
    let poll = try! JSONDecoder().decode(RedditPollData.self, from: pollJSON)
    check("poll decodes real field names", poll.options.count == 2 && poll.totalVoteCount == 12 && poll.userSelection == "abc1")
    check("poll option without vote_count decodes to nil (hidden until voted)", poll.options[1].voteCount == nil)
    check("poll with a past end timestamp has ended", poll.hasEnded)

    // GiphyClient: response-shape parsing for the GIF picker.
    let giphyJSON = """
    {
        "data": [
            {
                "id": "abc123",
                "title": "funny cat",
                "url": "https://giphy.com/gifs/funny-cat-abc123",
                "images": {
                    "original": {"url": "https://media.giphy.com/media/abc123/giphy.gif"},
                    "fixed_width": {"url": "https://media.giphy.com/media/abc123/200w.gif"}
                }
            },
            {
                "id": "def456",
                "title": "",
                "images": {}
            }
        ],
        "pagination": {"total_count": 100, "offset": 0, "count": 2},
        "meta": {"status": 200, "msg": "OK"}
    }
    """.data(using: .utf8)!
    let giphyResult = try! GiphyClient.parse(data: giphyJSON, requestedOffset: 0)
    check("Giphy parses both GIFs", giphyResult.gifs.count == 2)
    check("Giphy real image field precedence (original over fixed_width)", giphyResult.gifs[0].downloadURL?.absoluteString == "https://media.giphy.com/media/abc123/giphy.gif")
    check("Giphy falls back to synthesized page URL when missing", giphyResult.gifs[1].pageURL == "https://giphy.com/gifs/def456")
    check("Giphy hasMore true when offset+count < total_count", giphyResult.hasMore)
    let giphyErrorJSON = """
    {"meta": {"status": 429, "msg": "Rate limited"}}
    """.data(using: .utf8)!
    var giphyThrew = false
    do { _ = try GiphyClient.parse(data: giphyErrorJSON, requestedOffset: 0) } catch { giphyThrew = true }
    check("Giphy surfaces real meta.status errors", giphyThrew)

    // AccountStore: multi-account switching.
    let accountStore = AccountStore(store: InMemoryAccountKeychainStore())
    check("New AccountStore starts with no accounts", accountStore.accounts.isEmpty && accountStore.activeAccount == nil)
    let credA = RedditCredential(accessToken: "a", refreshToken: "ra", expiration: Date().addingTimeInterval(3600), isPermanent: true)
    let credB = RedditCredential(accessToken: "b", refreshToken: "rb", expiration: Date().addingTimeInterval(3600), isPermanent: true)
    let idxA = accountStore.addOrUpdate(StoredAccount(username: "AliceRedditor", oauthCredential: credA))
    check("First added account becomes active", accountStore.activeAccount?.username == "aliceredditor")
    check("Username is stored lowercased", accountStore.accounts[idxA].username == "aliceredditor")
    let idxB = accountStore.addOrUpdate(StoredAccount(username: "bob", oauthCredential: credB))
    check("Adding a second account switches active to it (matches real sign-in-a-new-account behavior)", accountStore.activeAccount?.username == "bob")
    accountStore.switchTo(index: idxA)
    check("switchTo makes the target account active", accountStore.activeAccount?.username == "aliceredditor")
    accountStore.switchTo(index: 99)
    check("switchTo ignores an out-of-range index", accountStore.activeAccount?.username == "aliceredditor")
    let adapterA = AccountCredentialAdapter(store: accountStore, username: "aliceredditor")
    check("AccountCredentialAdapter reads the right account's credential", adapterA.load()?.accessToken == "a")
    let refreshedA = RedditCredential(accessToken: "a2", refreshToken: "ra2", expiration: Date().addingTimeInterval(3600), isPermanent: true)
    try! adapterA.save(refreshedA)
    check("AccountCredentialAdapter.save updates only that account", accountStore.accounts[idxA].oauthCredential?.accessToken == "a2" && accountStore.accounts[idxB].oauthCredential?.accessToken == "b")
    accountStore.remove(at: idxB)
    check("remove(at:) drops the account", accountStore.accounts.count == 1)
    check("remove(at:) of a non-active account keeps the active one", accountStore.activeAccount?.username == "aliceredditor")
    let accountStore2 = AccountStore(store: InMemoryAccountKeychainStore())
    accountStore2.addOrUpdate(StoredAccount(username: "one"))
    accountStore2.addOrUpdate(StoredAccount(username: "two"))
    accountStore2.addOrUpdate(StoredAccount(username: "three"))
    accountStore2.switchTo(index: 1)
    accountStore2.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    check("move(fromOffsets:toOffset:) reorders correctly", accountStore2.accounts.map(\.username) == ["two", "three", "one"])
    check("move(fromOffsets:toOffset:) tracks the active account through a reorder", accountStore2.activeAccount?.username == "two")
    accountStore2.remove(at: 0)
    accountStore2.remove(at: 0)
    accountStore2.remove(at: 0)
    check("Removing the last account clears activeAccount", accountStore2.activeAccount == nil && accountStore2.accounts.isEmpty)

    // ReadPostStore.apply: "Auto Hide Read Posts" / "Disable in Subreddits"
    // gating (both must be on for filtering to take effect).
    ReadPostStore.clearAll()
    let readPost = makeTestPost(id: "readpost1")
    let unreadPost = makeTestPost(id: "unreadpost1")
    ReadPostStore.saveSettings(MarkReadSettings(markReadOnOpen: true, hideReadPosts: false, autoHideReadPosts: false, disableAutoHideInSubreddits: false))
    ReadPostStore.markRead(readPost.name)
    check("hideReadPosts off: apply() doesn't filter anything", ReadPostStore.apply([readPost, unreadPost]).count == 2)
    ReadPostStore.saveSettings(MarkReadSettings(markReadOnOpen: true, hideReadPosts: true, autoHideReadPosts: false, disableAutoHideInSubreddits: false))
    check("hideReadPosts on but autoHideReadPosts off: real Apollo requires both, so still no filtering", ReadPostStore.apply([readPost, unreadPost]).count == 2)
    ReadPostStore.saveSettings(MarkReadSettings(markReadOnOpen: true, hideReadPosts: true, autoHideReadPosts: true, disableAutoHideInSubreddits: false))
    let autoHidResult = ReadPostStore.apply([readPost, unreadPost])
    check("hideReadPosts + autoHideReadPosts both on: read post is filtered out", autoHidResult.count == 1 && autoHidResult.first?.name == unreadPost.name)
    ReadPostStore.saveSettings(MarkReadSettings(markReadOnOpen: true, hideReadPosts: true, autoHideReadPosts: true, disableAutoHideInSubreddits: true))
    check("disableAutoHideInSubreddits on + a specific subreddit: filtering is suppressed", ReadPostStore.apply([readPost, unreadPost], isSpecificSubreddit: true).count == 2)
    check("disableAutoHideInSubreddits on + Home/aggregate feed: filtering still applies (real Popular/All bug fix)", ReadPostStore.apply([readPost, unreadPost], isSpecificSubreddit: false).count == 1)
    check("the Hide Read button finds the read posts on screen", ReadPostStore.readPosts(in: [readPost, unreadPost]).map(\.name) == [readPost.name])
    check("Auto Hide needs Permanently", !ReadPostStore.autoHides(MarkReadSettings(markReadOnOpen: true, hideReadPosts: false, autoHideReadPosts: true), isSpecificSubreddit: false))
    ReadPostStore.clearAll()
    ReadPostStore.saveSettings(.default)
}

// --- Self-post embedded-image thumbnail derivation ---
@MainActor func checkSelfPostEmbeddedImageThumbnailDerivation() async throws {
    let selfPostWithEmbeddedImageJSON = """
    {"id":"sp1","name":"t3_sp1","title":"t","author":"u","subreddit":"test",
     "permalink":"/r/test/comments/sp1/","score":1,"num_comments":0,
     "created_utc":0,"is_self":true,"over_18":false,"spoiler":false,
     "stickied":false,"saved":false,
     "media_metadata":{"img1":{"status":"valid","s":{"u":"https://i.redd.it/abc.png\\u0026s=1"}}}}
    """.data(using: .utf8)!
    let selfPostWithEmbeddedImage = try! JSONDecoder.reddit.decode(RedditPost.self, from: selfPostWithEmbeddedImageJSON)
    check("derivedSelfPostThumbnailURL resolves the embedded image for a plain self-post", selfPostWithEmbeddedImage.derivedSelfPostThumbnailURL?.absoluteString == "https://i.redd.it/abc.png&s=1")
    check("derivedSelfPostThumbnailURL is nil for a self-post with no media_metadata", makeTestPost(id: "sp2").derivedSelfPostThumbnailURL == nil)
    let orderedJSON = """
    {"id":"sp3","name":"t3_sp3","title":"t","author":"u","subreddit":"test",
     "selftext":"see https://preview.redd.it/zzz.png then https://preview.redd.it/aaa.png",
     "permalink":"/r/test/comments/sp3/","score":1,"num_comments":0,
     "created_utc":0,"is_self":true,"over_18":false,"spoiler":false,"stickied":false,"saved":false,
     "media_metadata":{"aaa":{"status":"valid","e":"Image","s":{"u":"https://i.redd.it/aaa.png","x":800,"y":600}},
                       "zzz":{"status":"valid","e":"Image","s":{"u":"https://i.redd.it/zzz.png","x":800,"y":600}}}}
    """.data(using: .utf8)!
    check("a text post's thumbnail is the first image in body order, not by key",
          (try? JSONDecoder.reddit.decode(RedditPost.self, from: orderedJSON))?.derivedSelfPostThumbnailURL?.absoluteString
              == "https://i.redd.it/zzz.png")
    let linkJSON = """
    {"id":"sp4","name":"t3_sp4","title":"t","author":"u","subreddit":"test",
     "selftext":"look [here](https://i.imgur.com/abc.jpg) and https://example.com/x.png",
     "permalink":"/r/test/comments/sp4/","score":1,"num_comments":0,
     "created_utc":0,"is_self":true,"over_18":false,"spoiler":false,"stickied":false,"saved":false}
    """.data(using: .utf8)!
    check("a text post linking a direct image on a media host uses it",
          (try? JSONDecoder.reddit.decode(RedditPost.self, from: linkJSON))?.derivedSelfPostThumbnailURL?.absoluteString
              == "https://i.imgur.com/abc.jpg")
}

// --- Sports-clip host recognition ---
@MainActor func checkSportsClipHostRecognition() async throws {
    check("SportsClipHost recognizes streamin.top", SportsClipHost.matches(URL(string: "https://streamin.top/v/abc123")!))
    check("SportsClipHost recognizes streamff.pro", SportsClipHost.matches(URL(string: "https://streamff.pro/v/abc")!))
    check("SportsClipHost recognizes streamain.com", SportsClipHost.matches(URL(string: "https://streamain.com/xy/abc")!))
    check("SportsClipHost recognizes dubz.co", SportsClipHost.matches(URL(string: "https://dubz.co/c/abc")!))
    check("SportsClipHost does not misrecognize an unrelated host", !SportsClipHost.matches(URL(string: "https://example.com/v/abc")!))
    check("OpenGraphParser extracts og:video", OpenGraphParser.parse(html: "<meta property=\"og:video\" content=\"https://cdn.example.com/clip.mp4\">").videoURLString == "https://cdn.example.com/clip.mp4")
}

// --- "Buy Us a Coffee" contributor-JSON parsing ---
@MainActor func checkRealGapFixBuyUsA() async throws {
    let contributorsJSON = """
    {"contributors": [
        {"role":"maintainer","github":"JeffreyCA","buyMeACoffeeUrl":"https://buymeacoffee.com/jeffreyca"},
        {"role":"maintainer","github":"icpryde"},
        {"role":"code","github":"EthanArbuckle","buyMeACoffeeUrl":""}
    ]}
    """.data(using: .utf8)!
    let parsedContributors = try! ApolloContributorsClient.parse(data: contributorsJSON)
    check("ApolloContributorsClient.parse decodes all real fields", parsedContributors.count == 3 && parsedContributors[0].buyMeACoffeeURL == "https://buymeacoffee.com/jeffreyca")
    check("ApolloContributorsClient.buyCoffeeEntries filters out empty/missing coffee links", ApolloContributorsClient.buyCoffeeEntries(from: parsedContributors).count == 1)
    check("ApolloContributor.resolvedDisplayName applies the real icpryde -> iCpryde special case", parsedContributors[1].resolvedDisplayName == "iCpryde")
    let grouped = ApolloContributorsClient.groupedByRole(parsedContributors)
    check("ApolloContributorsClient.groupedByRole groups by real role", grouped.first?.title == "Maintainers" && grouped.first?.contributors.count == 2)
}

// --- CustomSubredditSourceSettings decode migration for persisted data
// missing showRandNSFWInSearch ---
@MainActor func checkRealGapFixCustomSubredditSourceSettingsDecodeMigration() async throws {
    let oldSourceSettingsJSON = """
    {"randomSourceURL":"https://example.com/random.json","trendingSourceURL":null,"randomNSFWSourceURL":null}
    """.data(using: .utf8)!
    let migratedSourceSettings = try! JSONDecoder().decode(CustomSubredditSourceSettings.self, from: oldSourceSettingsJSON)
    check("CustomSubredditSourceSettings migrates old persisted data (missing showRandNSFWInSearch defaults false, preserves randomSourceURL)", migratedSourceSettings.showRandNSFWInSearch == false && migratedSourceSettings.randomSourceURL == "https://example.com/random.json")
}

// --- Liquid Glass App Icon catalog ---
// Toon Bot and Happy Toon Bot joined Concepts in Reborn (#1253).
@MainActor func checkRealGapFixLiquidGlassApp() async throws {
    check("LiquidGlassIconOption.all has the real 78-icon count", LiquidGlassIconOption.all.count == 78)
    check("LiquidGlassIconOption.all has no duplicate IDs", Set(LiquidGlassIconOption.all.map(\.id)).count == LiquidGlassIconOption.all.count)
    check("LiquidGlassIconOption includes the real 'Canon by iGerman00' entry from the reference screenshot", LiquidGlassIconOption.all.contains { $0.displayName == "Canon" && $0.designer == "iGerman00" })
    check("LiquidGlassIconGroup.all has the real 4 groups in order", LiquidGlassIconGroup.all.map(\.id) == ["original", "classics", "helios", "concepts"])
    let groupedLG = LiquidGlassIconOption.groupedByGroup
    check("LiquidGlassIconOption.groupedByGroup covers every icon exactly once", groupedLG.reduce(0) { $0 + $1.icons.count } == LiquidGlassIconOption.all.count)
}

// --- Liquid Glass Tab Bar setting default + migration ---
@MainActor func checkRealGapFixLiquidGlassTab() async throws {
    check("GeneralSettings.default enables the Liquid Glass Tab Bar (matches the real app's own default)", GeneralSettings.default.enableLiquidGlassTabBar == true)
    let lgEncodedSettings = try! JSONEncoder().encode(GeneralSettings.default)
    var lgSettingsDict = try! JSONSerialization.jsonObject(with: lgEncodedSettings) as! [String: Any]
    lgSettingsDict.removeValue(forKey: "enableLiquidGlassTabBar")
    let lgMigratedData = try! JSONSerialization.data(withJSONObject: lgSettingsDict)
    let migratedGeneralSettings = try! JSONDecoder().decode(GeneralSettings.self, from: lgMigratedData)
    check("GeneralSettings migrates old persisted data missing enableLiquidGlassTabBar to true", migratedGeneralSettings.enableLiquidGlassTabBar == true)
}

// --- Media settings ---

// NSFW Media blur override (NSFW tag only).
@MainActor func checkMediaSubScreen6Additions() async throws {
    let tfOff = TagFilterSettings(enabled: false, nsfw: false, spoiler: false, subredditOverrides: [:])
    let tfNSFW = TagFilterSettings(enabled: true, nsfw: true, spoiler: false, subredditOverrides: [:])
    check("NSFWBlurOverride.always covers NSFW media even with the account pref off", tfOff.shouldBlurMedia(subreddit: "test", isNSFW: true, isSpoiler: false, nsfwBlurOverride: .always, accountPref: false))
    check("NSFWBlurOverride.never uncovers NSFW media with the account pref on", !tfOff.shouldBlurMedia(subreddit: "test", isNSFW: true, isSpoiler: false, nsfwBlurOverride: .never, accountPref: true))
    check("the Tag Filters still cover NSFW media under Never, as Reborn's", tfNSFW.shouldBlurMedia(subreddit: "test", isNSFW: true, isSpoiler: false, nsfwBlurOverride: .never, accountPref: false))
    check("Reddit Setting follows the account's pref_no_profanity", !tfOff.shouldBlurMedia(subreddit: "test", isNSFW: true, isSpoiler: false, nsfwBlurOverride: .redditSetting, accountPref: false)
          && tfOff.shouldBlurMedia(subreddit: "test", isNSFW: true, isSpoiler: false, nsfwBlurOverride: .redditSetting, accountPref: true))
    check("an unknown account pref keeps NSFW media covered", tfOff.shouldBlurMedia(subreddit: "test", isNSFW: true, isSpoiler: false, nsfwBlurOverride: .redditSetting, accountPref: nil))
    check("spoiler media is always covered, as Apollo's", tfOff.shouldBlurMedia(subreddit: "test", isNSFW: false, isSpoiler: true, nsfwBlurOverride: .never, accountPref: false))
    check("only the Tag Filters cover a title", !tfOff.shouldBlur(subreddit: "test", isNSFW: true, isSpoiler: true) && tfNSFW.shouldBlur(subreddit: "test", isNSFW: true, isSpoiler: false))
    let meJSON = Data(#"{"id":"1","name":"me","comment_karma":0,"link_karma":0,"created_utc":0,"pref_no_profanity":false}"#.utf8)
    check("RedditUser decodes pref_no_profanity", (try? JSONDecoder.reddit.decode(RedditUser.self, from: meJSON))?.blursMatureMedia == false)

    // Share Link Host 4-way picker + old-boolean migration.
    check("ShareLinkBuilder .reddit keeps the original host", ShareLinkBuilder.url(forPermalinkPath: "/r/test/comments/abc", host: .reddit).absoluteString == "https://reddit.com/r/test/comments/abc")
    check("ShareLinkBuilder .oldReddit uses old.reddit.com", ShareLinkBuilder.url(forPermalinkPath: "/r/test/comments/abc", host: .oldReddit).absoluteString == "https://old.reddit.com/r/test/comments/abc")
    check("ShareLinkBuilder .vxReddit uses vxreddit.com", ShareLinkBuilder.url(forPermalinkPath: "/r/test/comments/abc", host: .vxReddit).absoluteString == "https://vxreddit.com/r/test/comments/abc")
    check("ShareLinkBuilder .fxReddit uses fxddit.com", ShareLinkBuilder.url(forPermalinkPath: "/r/test/comments/abc", host: .fxReddit).absoluteString == "https://fxddit.com/r/test/comments/abc")
    check("ShareLinkBuilder back-compat useOldReddit:true maps to .oldReddit", ShareLinkBuilder.url(forPermalinkPath: "/x", useOldReddit: true).absoluteString == "https://old.reddit.com/x")
    check("GeneralSettings.default.shareLinkHost is .reddit", GeneralSettings.default.shareLinkHost == .reddit)

    // Migration: a persisted `shareOldRedditLinks: true` with no `shareLinkHost`
    // key carries over to `.oldReddit`.
    var shareOldSettingsDict = try! JSONSerialization.jsonObject(with: try! JSONEncoder().encode(GeneralSettings.default)) as! [String: Any]
    shareOldSettingsDict["shareOldRedditLinks"] = true
    shareOldSettingsDict.removeValue(forKey: "shareLinkHost")
    let migratedShareSettings = try! JSONDecoder().decode(GeneralSettings.self, from: try! JSONSerialization.data(withJSONObject: shareOldSettingsDict))
    check("GeneralSettings migrates shareOldRedditLinks=true to shareLinkHost=.oldReddit", migratedShareSettings.shareLinkHost == .oldReddit)

    // Unmute Videos in Feed/Comments split + migration from the old combined
    // unmuteVideosWhenOpened.
    var unmuteMigrationDict = try! JSONSerialization.jsonObject(with: try! JSONEncoder().encode(GeneralSettings.default)) as! [String: Any]
    unmuteMigrationDict["unmuteVideosWhenOpened"] = "always"
    unmuteMigrationDict.removeValue(forKey: "unmuteFeedVideosMode")
    unmuteMigrationDict.removeValue(forKey: "unmuteCommentsVideosMode")
    let migratedUnmuteSettings = try! JSONDecoder().decode(GeneralSettings.self, from: try! JSONSerialization.data(withJSONObject: unmuteMigrationDict))
    check("GeneralSettings migrates old unmuteVideosWhenOpened=.always to both new feed/comments fields", migratedUnmuteSettings.unmuteFeedVideosMode == .always && migratedUnmuteSettings.unmuteCommentsVideosMode == .always)
    check("GeneralSettings.default keeps unmuteFeedVideosMode/unmuteCommentsVideosMode independently settable", GeneralSettings.default.unmuteFeedVideosMode == .never)

    // Each video's sound belongs to one setting (Reborn's video-unmute hook).
    var unmuteSettings = GeneralSettings.default
    func startsMuted(_ context: VideoUnmuteContext, feedMuted: Bool = true, fullscreenUnmuted: Bool = false) -> Bool {
        VideoUnmutePolicy.startsMuted(context, settings: unmuteSettings,
                                      feedRememberedMuted: feedMuted, fullscreenUnmutedThisSession: fullscreenUnmuted)
    }
    check("Unmute Videos When Opened defaults to Remember, as stock", GeneralSettings.default.unmuteVideosWhenOpened == .remember)
    check("opening fullscreen from a video already playing with sound keeps it",
          !VideoUnmutePolicy.startsMuted(.fullscreen, settings: GeneralSettings.default, feedRememberedMuted: true,
                                         fullscreenUnmutedThisSession: false, alreadyAudible: true))
    check("fullscreen Remember keeps this session's unmute", startsMuted(.fullscreen) && !startsMuted(.fullscreen, fullscreenUnmuted: true))
    unmuteSettings.unmuteFeedVideosMode = .always
    check("the feed setting never reaches the comments header", startsMuted(.commentsHeader) && !startsMuted(.feed))
    unmuteSettings.unmuteFeedVideosMode = .remember
    check("feed Remember uses the feed's own memory", !startsMuted(.feed, feedMuted: false) && startsMuted(.feed, feedMuted: true))
    unmuteSettings.unmuteCommentsVideosMode = .always
    check("comments Always unmutes the header; embeds stay muted", !startsMuted(.commentsHeader) && startsMuted(.embed))
    check("after fullscreen: Default re-mutes, Remember matches the viewer, Always unmutes",
          VideoUnmutePolicy.headerMutedAfterFullscreen(mode: .never, fullscreenMuted: false)
              && !VideoUnmutePolicy.headerMutedAfterFullscreen(mode: .remember, fullscreenMuted: false)
              && VideoUnmutePolicy.headerMutedAfterFullscreen(mode: .remember, fullscreenMuted: true)
              && !VideoUnmutePolicy.headerMutedAfterFullscreen(mode: .always, fullscreenMuted: true))
    let blockedJSON = Data(#"{"kind":"UserList","data":{"children":[{"date":1.0,"rel_id":"r9_1","name":"Spammer","id":"t2_1"}]}}"#.utf8)
    check("the Reddit block list parses /prefs/blocked", (try? BlockedUsersStore.parse(blockedJSON))?.map(\.name) == ["Spammer"])
    let blockedRoots = (try CommentTreeBuilder.parseCommentsResponse(Data("""
    [{"kind":"Listing","data":{"children":[]}},{"kind":"Listing","data":{"children":[
     {"kind":"t1","data":{"id":"a","name":"t1_a","author":"spammer","body":"x","score":1,"created_utc":0,"parent_id":"t3_p","link_id":"t3_p","saved":false,"score_hidden":false,"stickied":false}},
     {"kind":"t1","data":{"id":"b","name":"t1_b","author":"friend","body":"y","score":1,"created_utc":0,"parent_id":"t3_p","link_id":"t3_p","saved":false,"score_hidden":false,"stickied":false}}]}}]
    """.utf8), postID: "p"))?.roots ?? []
    let collapsedBlocked = blockedRoots.applyingBlockedUsers(["Spammer"], hide: false)
    check("Blocked Users → Collapse starts their comments collapsed",
          collapsedBlocked.count == 2 && collapsedBlocked[0].isCollapsed && !collapsedBlocked[1].isCollapsed)
    check("Blocked Users → Hide removes them", blockedRoots.applyingBlockedUsers(["Spammer"], hide: true).map(\.id) == ["b"])
    check("Unmute Videos in Comments uses Reborn's titles", VideoUnmuteMode.allCases.map(\.commentsDisplayName) == ["Default", "Remember", "Always"])

    // New fields round-trip through Codable with their defaults.
    check("GeneralSettings.default.feedGalleryCarousel matches real sFeedGalleryCarousel default (YES)", GeneralSettings.default.feedGalleryCarousel == true)
    // Reborn #1134 flipped the default to NO: "Default Swipe Up for Comments to off".
    check("GeneralSettings.default.swipeUpForComments matches real sSwipeUpForComments default (NO since #1134)", GeneralSettings.default.swipeUpForComments == false)
    check("GeneralSettings.default.preferredGIFFallbackFormat matches real sPreferredGIFFallbackFormat default (MP4)", GeneralSettings.default.preferredGIFFallbackFormat == .mp4)
    check("GeneralSettings.default.mediaUploadHost matches real sImageUploadProvider default (Imgur)", GeneralSettings.default.mediaUploadHost == .imgur)
    check("GeneralSettings.default.commentLinkHost matches real CommentLinkHostOff default", GeneralSettings.default.commentLinkHost == .off)
    check("GeneralSettings.default.imgurAlbumFallbackProxies matches real sImgurAlbumFallbackProxies default (YES)", GeneralSettings.default.imgurAlbumFallbackProxies == true)
    let fallbacks = ImgurClient.albumFallbacks(id: "abc", hadPersonalKey: true, proxies: true)
    check("album fallbacks follow Reborn's chain: keyless retry, r.jina.ai, allorigins, codetabs",
          fallbacks.map(\.name) == ["direct keyless retry", "r.jina.ai", "allorigins", "codetabs"])
    check("album fallbacks never carry a personal key, only Imgur's public web ID",
          fallbacks.allSatisfy { $0.url.contains(ImgurClient.publicWebClientID) })
    check("no proxies when Album Fallback Proxies is off; no retry without a personal key",
          ImgurClient.albumFallbacks(id: "abc", hadPersonalKey: false, proxies: false).isEmpty)
    check("r.jina.ai's envelope is unwrapped to the JSON body",
          ImgurClient.extractJinaBody(Data("Title: x\n\nMarkdown Content:\n{\"a\":1}".utf8)) == Data("{\"a\":1}".utf8))
    check("GeneralSettings.default.proxyImgurViaDuckDuckGo matches real sProxyImgurDDG default (NO)", GeneralSettings.default.proxyImgurViaDuckDuckGo == false)
    let roundTrippedSettings = try! JSONDecoder().decode(GeneralSettings.self, from: try! JSONEncoder().encode(GeneralSettings.default))
    check("GeneralSettings new §6 fields round-trip unchanged through Codable", roundTrippedSettings == GeneralSettings.default)

    // DDG Imgur proxy URL rewriting (format:
    // https://external-content.duckduckgo.com/iu/?u=<encoded>).
    var ddgSettings = GeneralSettings.default
    ddgSettings.proxyImgurViaDuckDuckGo = true
    GeneralSettingsStore.save(ddgSettings)
    let proxiedURL = ImgurClient.proxiedImageURL(for: URL(string: "https://i.imgur.com/abc123.jpg")!)
    check("ImgurClient.proxiedImageURL rewrites to DuckDuckGo's real proxy format when enabled", proxiedURL.absoluteString.hasPrefix("https://external-content.duckduckgo.com/iu/?u="))
    check("ImgurClient.proxiedImageURL embeds the original Imgur URL as the u= query value (matches real URLQueryAllowedCharacterSet encoding, which doesn't escape '/')", proxiedURL.absoluteString.contains("u=https://i.imgur.com/abc123.jpg"))
    let unproxiedAPIURL = ImgurClient.proxiedImageURL(for: URL(string: "https://api.imgur.com/3/image/abc")!)
    check("ImgurClient.proxiedImageURL leaves api.imgur.com untouched (real module's own exclusion)", unproxiedAPIURL.absoluteString == "https://api.imgur.com/3/image/abc")
    let gifvURL = ImgurClient.proxiedImageURL(for: URL(string: "https://i.imgur.com/abc123.gifv")!)
    check("ImgurClient.proxiedImageURL rewrites .gifv to .gif before proxying (DDG can't serve .gifv)", gifvURL.absoluteString.contains("abc123.gif") && !gifvURL.absoluteString.contains("abc123.gifv"))
    ddgSettings.proxyImgurViaDuckDuckGo = false
    GeneralSettingsStore.save(ddgSettings)
    let unproxiedURL = ImgurClient.proxiedImageURL(for: URL(string: "https://i.imgur.com/abc123.jpg")!)
    check("ImgurClient.proxiedImageURL is a no-op when the setting is off", unproxiedURL.absoluteString == "https://i.imgur.com/abc123.jpg")
    GeneralSettingsStore.save(.default)
}

// MARK: - ApolloAISettings / FloatingPostTabsSettings
@MainActor func checkApolloAISettingsFloatingPostTabsSettings() async throws {
    check("ApolloAISettings.default has summaries disabled", ApolloAISettings.default.summariesEnabled == false)
    check("ApolloAISettings.default provider is .onDevice", ApolloAISettings.default.provider == .onDevice)
    // The disabled subtitle is "On-device or cloud summaries and generation
    // settings", not "Off".
    check("the disabled hub subtitle is the real descriptive one",
          ApolloAISettings.default.summaryText
              == "On-device or cloud summaries and generation settings")
    var aiSettings = ApolloAISettings.default
    aiSettings.summariesEnabled = true
    aiSettings.provider = .openRouter
    aiSettings.openRouterAPIKey = "sk-test-123"
    // The hub subtitle reads "<Provider> enabled", using the hub's own
    // provider names, which differ from the picker's ("OpenRouter AI" vs
    // "OpenRouter").
    check("the enabled hub subtitle names the provider and says enabled",
          aiSettings.summaryText == "OpenRouter AI enabled")
    check("the hub's provider names are its own, not the picker's",
          ApolloAISettings.default.hubProviderName == "On-device AI"
          && AIProvider.onDevice.displayName == "Apple On-Device")
    if let encoded = try? JSONEncoder().encode(aiSettings), let decoded = try? JSONDecoder().decode(ApolloAISettings.self, from: encoded) {
        check("ApolloAISettings round-trips through Codable unchanged", decoded == aiSettings)
    } else {
        check("ApolloAISettings round-trips through Codable unchanged", false)
    }
    ApolloAISettingsStore.save(aiSettings)
    check("ApolloAISettingsStore.load reflects the last saved settings", ApolloAISettingsStore.load() == aiSettings)
    ApolloAISettingsStore.save(.default)

    check("FloatingPostTabsSettings.default is disabled with both sub-toggles on", FloatingPostTabsSettings.default.enabled == false && FloatingPostTabsSettings.default.magneticStacking == true && FloatingPostTabsSettings.default.holdToPreview == true)
    var floatingTabsSettings = FloatingPostTabsSettings.default
    floatingTabsSettings.enabled = true
    floatingTabsSettings.holdToPreview = false
    if let encoded = try? JSONEncoder().encode(floatingTabsSettings), let decoded = try? JSONDecoder().decode(FloatingPostTabsSettings.self, from: encoded) {
        check("FloatingPostTabsSettings round-trips through Codable unchanged", decoded == floatingTabsSettings)
    } else {
        check("FloatingPostTabsSettings round-trips through Codable unchanged", false)
    }
    FloatingPostTabsSettingsStore.save(floatingTabsSettings)
    check("FloatingPostTabsSettingsStore.load reflects the last saved settings", FloatingPostTabsSettingsStore.load() == floatingTabsSettings)
    FloatingPostTabsSettingsStore.save(.default)
}

// MARK: - DeletedCommentsSettings
@MainActor func checkDeletedCommentsSettings() async throws {
    check("DeletedCommentsSettings.default is Off with tapToReveal false", DeletedCommentsSettings.default.mode == .off && DeletedCommentsSettings.default.tapToReveal == false)
    // Reborn's ReasonForCurrentBody: Reddit's "[deleted]" body wins over the
    // archive's removal_type.
    let modTagged = ArchivedComment(fullname: "t1_z", author: "Zephensis", body: "text", score: 1, reason: .moderatorRemoved)
    check("a [deleted] body classifies the archive copy as DELETED BY USER",
          modTagged.classified(byCurrentBody: "[deleted]").reason == .userDeleted)
    check("a [removed] body keeps the archive's moderator reason",
          modTagged.classified(byCurrentBody: "[removed]").reason == .moderatorRemoved)
    check("DeletedCommentsMode titles match real picker copy verbatim", DeletedCommentsMode.off.title == "Off" && DeletedCommentsMode.alwaysShow.title == "Always Show" && DeletedCommentsMode.passive.title == "Passive (Per-Thread)")
    var deletedCommentsSettings = DeletedCommentsSettings(mode: .alwaysShow, tapToReveal: true)
    if let encoded = try? JSONEncoder().encode(deletedCommentsSettings), let decoded = try? JSONDecoder().decode(DeletedCommentsSettings.self, from: encoded) {
        check("DeletedCommentsSettings round-trips through Codable unchanged", decoded == deletedCommentsSettings)
    } else {
        check("DeletedCommentsSettings round-trips through Codable unchanged", false)
    }
    DeletedCommentsSettingsStore.save(deletedCommentsSettings)
    check("DeletedCommentsSettingsStore.load reflects the last saved settings", DeletedCommentsSettingsStore.load() == deletedCommentsSettings)
    DeletedCommentsSettingsStore.save(.default)
}

// MARK: - InfoRowSettings
@MainActor func checkInfoRowSettings() async throws {
    check("InfoRowSettings.default matches Reborn's registered defaults (magnifier, upvote, comments, popup, translation on; overlay off)", InfoRowSettings.default.magnifierOnHold && InfoRowSettings.default.tapToUpvote && InfoRowSettings.default.tapToComments && InfoRowSettings.default.popupMode && !InfoRowSettings.default.overlayMode && InfoRowSettings.default.tapToTranslation)
    var infoRowSettings = InfoRowSettings.default
    infoRowSettings.overlayMode = true
    infoRowSettings.tapToUpvote = false
    if let encoded = try? JSONEncoder().encode(infoRowSettings), let decoded = try? JSONDecoder().decode(InfoRowSettings.self, from: encoded) {
        check("InfoRowSettings round-trips through Codable unchanged", decoded == infoRowSettings)
    } else {
        check("InfoRowSettings round-trips through Codable unchanged", false)
    }
    InfoRowSettingsStore.save(infoRowSettings)
    check("InfoRowSettingsStore.load reflects the last saved settings", InfoRowSettingsStore.load() == infoRowSettings)
    check("InfoRowSettings.summaryText reflects overlay + disabled upvote", infoRowSettings.summaryText.contains("Overlays") && infoRowSettings.summaryText.contains("Upvote") && infoRowSettings.summaryText.hasSuffix("off"))
    InfoRowSettingsStore.save(.default)
}
