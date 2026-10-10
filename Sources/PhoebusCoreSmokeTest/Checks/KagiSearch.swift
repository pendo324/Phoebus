import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Kagi Search (Reborn #1305)
//
// The Search tab's third engine: kagi.com/html/search read with a Session
// Link. The fixtures are trimmed real Kagi pages (results, a next batch, a
// no-results page and both signed-out pages); the synthetic pages cover what
// a live search can't be relied on to produce (markup drift, a grouped
// result). The tokens below are made up.

@MainActor func checkKagiSearch() async throws {
    typealias K = KagiSearch

    func page(_ name: String) -> String {
        let path = "Tests/Fixtures/kagi/\(name)"
        let data = FileManager.default.contents(atPath: path)
            ?? FileManager.default.contents(atPath: FileManager.default.currentDirectoryPath + "/" + path)
        return String(decoding: data ?? Data(), as: UTF8.self)
    }

    // The request.
    do {
        let url = K.searchURL("best decks reddit", options: .init(timeRange: .week, exactWords: true), page: 2)?.absoluteString ?? ""
        check("kagi: the results URL is html/search with the composed query, dr=, verbatim=1 and batch N+1",
              url.hasPrefix("https://kagi.com/html/search?q=best%20decks%20site:reddit.com")
                && url.contains("&dr=2") && url.contains("&verbatim=1") && url.hasSuffix("&batch=3"))
        let plain = K.searchURL("c++ r/cpp")?.absoluteString ?? ""
        check("kagi: Any Time sends no dr=, page 0 no batch, r/name scopes the search and a + is literal",
              !plain.contains("dr=") && !plain.contains("batch=") && !plain.contains("verbatim")
                && plain.contains("c%2B%2B") && plain.contains("site:reddit.com/r/cpp"))
        check("kagi: Past 24 Hours, Month and Year map to dr=1, 3 and 4",
              K.searchURL("x", options: .init(timeRange: .day))?.query?.contains("dr=1") == true
                && K.searchURL("x", options: .init(timeRange: .month))?.query?.contains("dr=3") == true
                && K.searchURL("x", options: .init(timeRange: .year))?.query?.contains("dr=4") == true)
        check("kagi: an empty query has no URL", K.searchURL("  ") == nil)
        check("kagi: autocomplete is Kagi's own endpoint",
              K.suggestionsURL(for: "swift ui")?.absoluteString == "https://kagisuggest.com/api/autosuggest?q=swift%20ui")

        let token = "AbCdEfGhIjKlMnOp_qrs-TUV.wxyz0123456789"
        let request = K.request(for: url.isEmpty ? K.sessionCheckURL : URL(string: url)!, token: token)
        check("kagi: the session rides in a hand-set kagi_session cookie, not the cookie jar",
              request.value(forHTTPHeaderField: "Cookie") == "kagi_session=\(token)" && request.httpShouldHandleCookies == false)
        check("kagi: the request carries an iPhone Safari identity",
              request.value(forHTTPHeaderField: "User-Agent")?.contains("iPhone; CPU iPhone OS") == true
                && K.userAgent(osVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 2, patchVersion: 0))
                    .contains("iPhone OS 18_2 like Mac OS X"))
    }

    // Signed out.
    do {
        func isOut(_ status: Int, _ url: String) -> Bool { K.isSignedOut(statusCode: status, finalURL: URL(string: url)) }
        check("kagi: the landing page, Turnstile, sign-in and the account host all read as signed out",
              isOut(200, "https://kagi.com/welcome") && isOut(200, "https://kagi.com/turnstile?r=/html/search")
                && isOut(200, "https://kagi.com/signin") && isOut(200, "https://account.kagi.com/ui/login")
                && isOut(200, "https://kagi.com/loginname"))
        check("kagi: 401 and 403 read as signed out; a results URL does not",
              isOut(401, "https://kagi.com/html/search?q=x") && isOut(403, "https://kagi.com/html/search?q=x")
                && !isOut(200, "https://kagi.com/html/search?q=x") && !isOut(500, "https://kagi.com/html/search?q=x"))
        let ok = URL(string: "https://kagi.com/settings/user_details")
        check("kagi: the Session Link check is valid, rejected or unreachable",
              K.sessionCheck(statusCode: 200, finalURL: ok, failed: false) == .valid
                && K.sessionCheck(statusCode: 200, finalURL: URL(string: "https://kagi.com/welcome"), failed: false) == .rejected
                && K.sessionCheck(statusCode: 503, finalURL: ok, failed: false) == .unreachable
                && K.sessionCheck(statusCode: nil, finalURL: nil, failed: true) == .unreachable)
    }

    // Pages.
    do {
        func checkPage(_ html: String, _ name: String, minimum: Int, hasMore: Bool) {
            let parsed = K.parseResults(html: html)
            check("kagi: \(name) is a results page with at least \(minimum) results (got \(parsed.results.count))",
                  parsed.kind == .results && parsed.results.count >= minimum)
            check("kagi: \(name) \(hasMore ? "ends" : "does not end") in More Results", parsed.hasMore == hasMore)
            let clean = parsed.results.allSatisfy { result in
                let url = URL(string: result.urlString)
                return url?.scheme == "https" && url?.host?.contains("kagi.com") == false
                    && !result.title.isEmpty && !result.title.contains("<") && !result.title.contains("&#")
                    && !result.snippet.contains("Summarize") && !result.snippet.contains("<")
                    && !result.snippet.contains("&amp;") && !result.snippet.contains("&#39;")
                    && !result.snippet.hasPrefix(" ") && !result.snippet.hasSuffix(" ") && !result.snippet.contains("  ")
                    && (result.dateText.map { !result.snippet.contains($0) } ?? true)
            }
            check("kagi: \(name) results are direct links with plain titles and snippets, no date or Summarize in the snippet", clean)
            check("kagi: \(name) results carry Kagi's date", parsed.results.contains { $0.dateText != nil })
        }

        // A real first page: 12 blocks (one wrapped in a result group).
        let page1 = page("results_page1.html")
        checkPage(page1, "page 1", minimum: 10, hasMore: true)
        let parsed1 = K.parseResults(html: page1)
        let cheatSheet = parsed1.results.first { $0.urlString.contains("/r/PTCGL/comments/1bqqph1/") }
        check("kagi: the grouped r/PTCGL result is read with curly apostrophes in its title",
              cheatSheet?.title == "Here\u{2019}s a cheat sheet if you\u{2019}re wondering what deck to play")
        check("kagi: its snippet is the text, with &#39; decoded",
              cheatSheet?.snippet.hasPrefix("Most decks in the current format") == true
                && cheatSheet?.snippet.contains("If you're playing") == true)
        // The page More Results loads: no further page.
        checkPage(page("results_batch2.html"), "batch 2", minimum: 15, hasMore: false)

        let signedOut = ["signed_out_turnstile.html", "signed_out_signin.html"].map { K.parseResults(html: page($0)) }
        check("kagi: the Turnstile page and the sign-in page are signed out, with no results",
              signedOut.allSatisfy { $0.kind == .signedOut && $0.results.isEmpty })

        let none = K.parseResults(html: page("results_none.html"))
        check("kagi: a signed-in page with nothing on it is empty, not signed out (Kagi's marketing line is on every page)",
              none.kind == .results && none.results.isEmpty && !none.hasMore)
        let welcome = K.parseResults(html: #"<meta name="description" content="Welcome to Kagi, a paid search engine that gives power back to the user."><main><div class="_0_main-search-results"></div></main>"#)
        check("kagi: the marketing line alone is not a sign-out", welcome.kind == .results)

        let empty = K.parseResults(html: #"<html><body><main><div class="_0_main-search-results"></div><div class="related-searches"><a href="/html/search?q=x">x</a></div></main></body></html>"#)
        check("kagi: a results container with nothing in it is an empty results page",
              empty.kind == .results && empty.results.isEmpty && !empty.hasMore)

        var drift = "<html><body><main>"
        for i in 0..<8 { drift += #"<div class="r-\#(i)"><a href="https://www.reddit.com/r/x/comments/abc\#(i)/t/">T\#(i)</a></div>"# }
        drift += "</main></body></html>"
        check("kagi: result-looking links with none of Kagi's blocks mean the markup moved",
              K.parseResults(html: drift).kind == .unreadable && K.parseResults(html: "").kind == .unreadable)

        let grouped = K.parseResults(html: #"<div class="sr-group"><div class="__srgi"><div class="__srgi-title"><a href="https://www.reddit.com/r/a/comments/1abcd/x/">Grouped &amp; titled</a></div><div class="__sri-desc"><div>One <b>two</b>&nbsp;three</div></div></div></div>"#)
        check("kagi: the older grouped sub-result markup is still read",
              grouped.results.count == 1 && grouped.results[0].title == "Grouped & titled" && grouped.results[0].snippet == "One two three")

        let nested = K.parseResults(html: #"<div class="_0_SRI search-result"><h3><a class="__sri_title_link" href="https://www.reddit.com/r/a/">Parent</a></h3><div class="__sri-desc"><div>Parent text</div></div><div class="_0_SRI search-result"><h3><a class="__sri_title_link" href="https://www.reddit.com/r/a/comments/2abc/c/">Child</a></h3><div class="__sri-desc"><div><span class="__sri-time "> Jan 2, 2026 </span> Child text <a class="summarize-link" href="/summarizer">Summarize</a></div></div></div></div><a id="load_more_results" href="/html/search?q=a&amp;batch=2">More Results</a>"#)
        check("kagi: a group holding child results reads each once, the parent with its own text",
              nested.results.count == 2 && nested.results[0].title == "Parent" && nested.results[0].snippet == "Parent text"
                && nested.results[1].snippet == "Child text" && nested.results[1].dateText == "Jan 2, 2026" && nested.hasMore)

        check("kagi: HTML character references decode, unknown ones stay",
              K.decodeHTMLEntities("a &amp; b &lt;c&gt; &#8217; &#x1F600; &bogus; &") == "a & b <c> \u{2019} \u{1F600} &bogus; &")
    }

    // Results.
    do {
        let parsed = K.parseResults(html: page("results_page1.html"))
        let results = K.results(from: parsed)
        check("kagi: Reddit results come out with canonical www URLs and ids",
              !results.isEmpty && results.allSatisfy { $0.url?.host == "www.reddit.com" && !$0.id.isEmpty && !$0.title.isEmpty })
        check("kagi: Kagi's date is the card's line until Reddit's numbers are in",
              results.contains { $0.engineMeta != nil })
        check("kagi: no result repeats a thread", Set(results.map(\.id)).count == results.count)

        var page = KagiSearch.ParsedPage()
        func raw(_ url: String, _ title: String, snippet: String = "") -> KagiSearch.ParsedResult {
            var result = KagiSearch.ParsedResult()
            result.urlString = url
            result.title = title
            result.snippet = snippet
            return result
        }
        page.results = [raw("https://www.reddit.com/r/pics/comments/abc123/slug/", "A thing : r/pics"),
                        raw("https://old.reddit.com/r/pics/comments/ABC123/other/", "Same thread"),
                        raw("https://example.com/post", "Not Reddit"),
                        raw("https://www.reddit.com/", "Reddit home"),
                        raw("https://www.reddit.com/r/pics/comments/def456/slug/", "Link to reddit.com")]
        let filtered = K.results(from: page)
        check("kagi: other sites and Reddit home drop, the same thread is kept once, title suffixes go",
              filtered.map(\.postID) == ["abc123", "def456"] && filtered[0].title == "A thing" && filtered[0].subreddit == "pics")

        let info = Data(#"{"data":{"children":[{"kind":"t3","data":{"id":"abc123","title":"A thing","num_comments":12,"score":340,"created_utc":1700000000,"is_self":true,"selftext":"The post says  a lot\n\nof things."}},{"kind":"t3","data":{"id":"def456","title":"Other","num_comments":3,"score":9,"is_self":true,"selftext":""}}]}}"#.utf8)
        let infos = GoogleSearchRedditInfo.parse(info, for: filtered)
        check("kagi: one /api/info listing fills every result it covers, keyed by id",
              infos.count == 2 && infos[filtered[0].id]?.commentCount == 12 && infos[filtered[1].id]?.score == 9)
        let enriched = K.applying(infos, to: filtered)
        check("kagi: Reddit's numbers land on the cards, and an empty snippet is filled from the post",
              enriched[0].redditInfo?.score == 340 && enriched[0].snippet == "The post says a lot of things."
                && enriched[1].snippet.isEmpty)
        check("kagi: a read that failed leaves Kagi's data alone", K.applying([:], to: filtered) == filtered)
        let long = (1...200).map { "word\($0)" }.joined(separator: " ")
        let cut = K.snippet(fromBody: long)
        check("kagi: a snippet from the post stops at a word within the limit",
              cut.utf16.count <= K.snippetFromBodyLength && cut.hasPrefix("word1 word2") && !cut.hasSuffix(" ") && cut.split(separator: " ").last?.hasPrefix("word") == true)
    }

    // The Session Link.
    do {
        let token = "AbCdEfGhIjKlMnOp_qrs-TUV.wxyz0123456789"
        check("kagi: a bare token is accepted", K.normalizeSessionToken(token) == token)
        check("kagi: the whole Session Link is cut down to its token, whitespace trimmed",
              K.normalizeSessionToken("  https://kagi.com/search?token=\(token)\n") == token)
        check("kagi: a link without a scheme, with other query items, still works",
              K.normalizeSessionToken("kagi.com/search?q=hi&token=\(token)") == token)
        check("kagi: a link without a token, a short string, spaces and nothing are refused",
              K.normalizeSessionToken("https://kagi.com/search?q=hi") == nil && K.normalizeSessionToken("short") == nil
                && K.normalizeSessionToken("has spaces in it which is not a token") == nil
                && K.normalizeSessionToken("") == nil && K.normalizeSessionToken(nil) == nil)

        KagiSession.setToken(nil)
        check("kagi: no Session Link is saved to begin with", !KagiSession.hasToken && KagiSession.token == nil)
        UserDefaults.standard.set(SearchEngine.kagi.rawValue, forKey: SearchEngine.key)
        check("kagi: the Search tab falls back to Reddit while no Session Link is saved", SearchEngine.current == .reddit)
        check("kagi: its menu row asks for the link", SearchEngine.kagi.subtitle == "Needs your Session Link")
        check("kagi: the Session Link saves", KagiSession.setToken(token) && KagiSession.token == token)
        check("kagi: with a link saved the stored choice reads back as Kagi", SearchEngine.current == .kagi)
        check("kagi: its menu row names the engine", SearchEngine.kagi.subtitle == "Reddit threads, found with Kagi")
        KagiSession.setToken(nil)
        check("kagi: removing the link puts the tab back on Reddit",
              SearchEngine.current == .reddit && KagiSession.token == nil)
        UserDefaults.standard.removeObject(forKey: SearchEngine.key)

        check("kagi: Kagi is the third engine, external, with its own title and field prompt",
              SearchEngine.allCases == [.reddit, .google, .kagi, .answers] && SearchEngine.kagi.rawValue == 2
                && SearchEngine.kagi.isExternal && SearchEngine.google.isExternal && !SearchEngine.reddit.isExternal
                && SearchEngine.kagi.title == "Kagi" && SearchEngine.kagi.placeholder == "Search Reddit with Kagi"
                && SearchEngine.google.placeholder == "Search Reddit with Google" && SearchEngine.reddit.placeholder == nil)
        check("kagi: each engine names its own autocomplete",
              SearchEngine.reddit.suggestionsURL(for: "x") == nil
                && SearchEngine.google.suggestionsURL(for: "x")?.host == "suggestqueries.google.com"
                && SearchEngine.kagi.suggestionsURL(for: "x")?.host == "kagisuggest.com")
    }

    // Backups.
    do {
        let token = "AbCdEfGhIjKlMnOp_qrs-TUV.wxyz0123456789"
        let archive = try RebornBackupArchive.make(defaults: UserDefaults.standard, accounts: nil, kagiToken: token)
        let payload = try ApolloBackupImport.read(zipData: archive)
        check("kagi: the Session Link rides in an exported backup's keychain.plist", payload.kagiToken == token)
        let bare = try ApolloBackupImport.read(zipData: RebornBackupArchive.make(defaults: UserDefaults.standard, accounts: nil, kagiToken: nil))
        check("kagi: a backup without one carries none", bare.kagiToken == nil)

        func keychain(_ service: String, _ account: String, _ value: String) -> Data {
            let item: [[String: Any]] = [["service": service, "account": account, "data": Data(value.utf8)]]
            return try! PropertyListSerialization.data(fromPropertyList: item, format: .xml, options: 0)
        }
        check("kagi: Reborn's own Keychain item (its backup) is read",
              ApolloKeychainImport.kagiToken(fromKeychainPlist: keychain("com.christianselig.Apollo.kagi", "sessionToken", token)) == token)
        check("kagi: lookalike services and accounts are refused",
              ApolloKeychainImport.kagiToken(fromKeychainPlist: keychain("com.christianselig.Apollo.kagi.evil", "sessionToken", token)) == nil
                && ApolloKeychainImport.kagiToken(fromKeychainPlist: keychain("com.christianselig.Apollo.kagi", "sessionToken2", token)) == nil
                && ApolloKeychainImport.kagiToken(fromKeychainPlist: keychain("com.example.other", "sessionToken", token)) == nil)
        check("kagi: a stored value that is not a token is refused",
              ApolloKeychainImport.kagiToken(fromKeychainPlist: keychain("com.christianselig.Apollo.kagi", "sessionToken", "not a token")) == nil)
        check("kagi: Reborn's Kagi item is an owned identity, and only with its one account",
              ApolloKeychainImport.ownsIdentity(service: "com.christianselig.Apollo.kagi", account: "sessionToken")
                && !ApolloKeychainImport.ownsIdentity(service: "com.christianselig.Apollo.kagi", account: "other"))

        KagiSession.setToken(nil)
        check("kagi: a backup without a link leaves the saved one alone",
              !ApolloSettingsMigration.applyKagiSession(ApolloBackupImport.Payload(preferences: [:])))
        KagiSession.setToken("ZyXwVuTsRqPoNmLk_jih-GFE.dcba9876543210")
        _ = ApolloSettingsMigration.applyKagiSession(ApolloBackupImport.Payload(preferences: [:]))
        check("kagi: ...and keeps it", KagiSession.token == "ZyXwVuTsRqPoNmLk_jih-GFE.dcba9876543210")
        var restoring = ApolloBackupImport.Payload(preferences: [:])
        restoring.kagiToken = token
        check("kagi: a Reborn backup's link is restored", ApolloSettingsMigration.applyKagiSession(restoring) && KagiSession.token == token)
        KagiSession.setToken("ZyXwVuTsRqPoNmLk_jih-GFE.dcba9876543210")
        SettingsDomainSnapshot.restore(restoring)
        check("kagi: a Phoebus backup's link is restored with its settings", KagiSession.token == token)
        KagiSession.setToken(nil)
    }
}
