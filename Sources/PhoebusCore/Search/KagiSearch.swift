import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The pure parts of Reborn's "Kagi Search" (#1305), the Search tab's third
/// engine: the request, reading Kagi's server-rendered results page, and
/// turning it into the same `GoogleSearchResult`s Google mode lists.
///
/// The page is `https://kagi.com/html/search`, fetched with a subscriber's
/// Session Link token as the `kagi_session` cookie (no web view, no bot
/// check). Each result is a `div._0_SRI.search-result` block:
///
///     <a class="__sri_title_link ..." href="https://www.reddit.com/r/...">Title</a>
///     <div class="_0_DESC __sri-desc"><div>
///         <span class="__sri-time">Mar 27, 2025</span>   (optional)
///         Snippet text ...
///         <a class="_0_summarize_page summarize-link" ...>Summarize</a>
///     </div></div>
///
/// Result links are the destination URLs themselves (no redirect wrapper),
/// and a "More Results" link (`#load_more_results`, `&batch=N`) closes a
/// page that has another one after it.
public enum KagiSearch {
    // MARK: Page model

    public struct ParsedResult: Equatable, Sendable {
        public var urlString = ""
        public var title = ""
        /// Plain text, entities decoded, whitespace collapsed; the date and
        /// the "Summarize" link are not part of it.
        public var snippet = ""
        /// Kagi's date line ("Mar 27, 2025"), nil when the result has none.
        public var dateText: String?

        public init() {}
    }

    public struct ParsedPage: Equatable, Sendable {
        public enum Kind: Sendable {
            /// A results page (it may still have no results).
            case results
            /// Kagi's signed-out page (sign-in form or the marketing landing
            /// page): the Session Link is missing, expired or was revoked.
            case signedOut
            /// A page with plenty of links but no result block Kagi's markup
            /// is known to use: the markup changed and the parser needs
            /// updating.
            case unreadable
        }

        public var kind = Kind.results
        public var results: [ParsedResult] = []
        /// The page ends in a "More Results" link.
        public var hasMore = false

        public init() {}
    }

    // MARK: Request

    /// One results page takes 25 s at most, covering the page and the Reddit
    /// read that follows it.
    public static let searchTimeout: TimeInterval = 25
    public static let sessionCheckTimeout: TimeInterval = 15
    public static let maximumPageBytes = 3 * 1024 * 1024
    /// An empty Kagi snippet is filled from the post's own text, up to this
    /// long (the card shows a few lines of it).
    public static let snippetFromBodyLength = 320

    /// The results URL. The query gets Google mode's `site:reddit.com`,
    /// `r/name` and trailing "reddit" handling; Any Time maps to `dr=`
    /// (1 day, 2 week, 3 month, 4 year) and Exact Words to `verbatim=1`.
    /// Page N is Kagi's "More Results" batch N+1.
    public static func searchURL(_ rawQuery: String, options: GoogleSearchOptions = .init(), page: Int = 0) -> URL? {
        let query = GoogleSearch.composeQuery(rawQuery)
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://kagi.com/html/search")!
        var items = [URLQueryItem(name: "q", value: query)]
        switch options.timeRange {
        case .any: break
        case .day: items.append(URLQueryItem(name: "dr", value: "1"))
        case .week: items.append(URLQueryItem(name: "dr", value: "2"))
        case .month: items.append(URLQueryItem(name: "dr", value: "3"))
        case .year: items.append(URLQueryItem(name: "dr", value: "4"))
        }
        if options.exactWords { items.append(URLQueryItem(name: "verbatim", value: "1")) }
        if page > 0 { items.append(URLQueryItem(name: "batch", value: String(page + 1))) }
        components.queryItems = items
        // '+' would read as a space ("c++" → "c  ").
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// An account page, not a search: it answers "signed in?" without using
    /// up a search on the subscriber's plan.
    public static let sessionCheckURL = URL(string: "https://kagi.com/settings/user_details")!

    /// Kagi's autocomplete (the endpoint its own OpenSearch description
    /// names, no session needed); it answers in the OpenSearch shape Google's
    /// does, so `GoogleSearch.parseSuggestions` reads it.
    public static func suggestionsURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://kagisuggest.com/api/autosuggest")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Kagi serves the same markup to every browser; an ordinary iPhone
    /// Safari identity keeps the request looking like the subscriber's own.
    public static func userAgent(osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> String {
        let major = osVersion.majorVersion, minor = osVersion.minorVersion
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(major)_\(minor) like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/\(major).\(minor) Mobile/15E148 Safari/604.1"
    }

    /// The session rides in the `kagi_session` cookie, set by hand: the
    /// request never touches (or fills) the app's shared cookie jar.
    public static func request(for url: URL, token: String, timeout: TimeInterval = searchTimeout,
                               userAgent: String = userAgent()) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpShouldHandleCookies = false
        request.setValue("kagi_session=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        return request
    }

    /// Kagi answers a request without a valid session by redirecting it to
    /// its landing page (`/welcome`), its Cloudflare Turnstile check
    /// (`/turnstile`) or to sign-in (`/signin` → account.kagi.com), depending
    /// on the client. Redirects are followed, so the final URL tells.
    public static func isSignedOut(statusCode: Int, finalURL: URL?) -> Bool {
        if statusCode == 401 || statusCode == 403 { return true }
        let host = finalURL?.host?.lowercased() ?? ""
        let path = finalURL?.path.lowercased() ?? ""
        if host == "account.kagi.com" { return true }
        return ["/welcome", "/turnstile", "/signin", "/loginname"].contains { path.hasPrefix($0) }
    }

    public enum SessionCheck: Sendable {
        case valid
        /// Kagi sent it to sign-in.
        case rejected
        /// A network error, Kagi down, ...
        case unreachable
    }

    /// What the account-page request says about a token.
    public static func sessionCheck(statusCode: Int?, finalURL: URL?, failed: Bool) -> SessionCheck {
        if let statusCode, isSignedOut(statusCode: statusCode, finalURL: finalURL) { return .rejected }
        if !failed, let statusCode, (200..<300).contains(statusCode) { return .valid }
        return .unreachable
    }

    // MARK: Results

    /// The page's results as Reddit results: a link Apollo can't show (not
    /// Reddit, a Reddit home page, `/domain/`...) is skipped and the same
    /// thread listed twice is kept once.
    public static func results(from page: ParsedPage) -> [GoogleSearchResult] {
        var results: [GoogleSearchResult] = []
        var seen = Set<String>()
        for raw in page.results {
            guard let url = URL(string: raw.urlString), var result = GoogleSearch.result(for: url) else { continue }
            let key = result.dedupeKey
            if !key.isEmpty, seen.contains(key) { continue }
            seen.insert(key)
            result.id = key
            result.title = GoogleSearch.cleanTitle(raw.title)
            result.snippet = raw.snippet
            result.engineMeta = raw.dateText
            results.append(result)
        }
        return results
    }

    /// Puts Reddit's numbers on the results. Kagi sometimes has no snippet
    /// for a Reddit page (and titles it "Link to reddit.com"); the post's
    /// opening lines stand in.
    public static func applying(_ infos: [String: GoogleSearchRedditInfo], to results: [GoogleSearchResult]) -> [GoogleSearchResult] {
        results.map { result in
            guard let info = infos[result.id] else { return result }
            var result = result
            result.redditInfo = info
            if result.snippet.isEmpty, let body = info.body { result.snippet = snippet(fromBody: body) }
            return result
        }
    }

    /// A post's opening words as plain text, cut at a word boundary.
    public static func snippet(fromBody markdown: String, limit: Int = snippetFromBodyLength) -> String {
        let plain = GoogleSearch.plainText(fromMarkdown: markdown)
        var snippet = ""
        for word in plain.components(separatedBy: .whitespacesAndNewlines) where !word.isEmpty {
            if snippet.utf16.count + word.utf16.count + 1 > limit { break }
            if !snippet.isEmpty { snippet += " " }
            snippet += word
        }
        return snippet
    }

    // MARK: Session Link

    /// Accepts what the user pastes: the whole Session Link
    /// (`https://kagi.com/search?token=…`, with or without other query
    /// items) or just the token. Returns the bare token, or nil when `input`
    /// is neither.
    public static func normalizeSessionToken(_ input: String?) -> String? {
        let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        var token = trimmed
        if trimmed.contains("://") || trimmed.hasPrefix("kagi.com/") || trimmed.contains("token=") {
            // The Session Link. Anything without a token parameter isn't one.
            let link = trimmed.contains("://") ? trimmed : "https://" + trimmed
            guard let items = URLComponents(string: link)?.queryItems,
                  let found = items.last(where: { $0.name == "token" && !($0.value ?? "").isEmpty })?.value else { return nil }
            token = found
        }

        // Kagi's tokens are URL-safe base64-ish text.
        guard (16...512).contains(token.utf16.count),
              token.unicodeScalars.allSatisfy({ tokenCharacters.contains($0) }) else { return nil }
        return token
    }

    private static let tokenCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~-")

    // MARK: HTML helpers

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let entityReference = regex(#"&(#[0-9]{1,7}|#x[0-9a-f]{1,6}|[a-z][a-z0-9]{1,15});"#)
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "hellip": "\u{2026}", "mdash": "\u{2014}", "ndash": "\u{2013}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "middot": "\u{00B7}", "bull": "\u{2022}", "rsaquo": "\u{203A}", "lsaquo": "\u{2039}",
        "raquo": "\u{00BB}", "laquo": "\u{00AB}", "copy": "\u{00A9}", "reg": "\u{00AE}",
        "trade": "\u{2122}", "times": "\u{00D7}", "deg": "\u{00B0}", "eacute": "\u{00E9}",
    ]

    /// Decodes HTML character references (named, `&#NNN;` and `&#xHH;`);
    /// anything it doesn't know stays as written.
    public static func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        let ns = string as NSString
        var out = ""
        var cursor = 0
        for match in entityReference.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = NSMaxRange(match.range)
            let body = ns.substring(with: match.range(at: 1))
            var replacement: String?
            if body.hasPrefix("#") {
                let hex = body.hasPrefix("#x") || body.hasPrefix("#X")
                if let value = UInt32(body.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), value > 0,
                   let scalar = Unicode.Scalar(value) {
                    replacement = String(Character(scalar))
                }
            } else {
                replacement = namedEntities[body.lowercased()]
            }
            out += replacement ?? ns.substring(with: match.range)
        }
        out += ns.substring(from: cursor)
        return out
    }

    private static let htmlTag = regex(#"<[^>]*>"#)
    private static let whitespaceRun = regex(#"[\s\u00A0]+"#)

    /// Tags → spaces, entities decoded, whitespace (incl. NBSP) collapsed.
    private static func plainText(_ html: String) -> String {
        var text = htmlTag.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: " ")
        text = decodeHTMLEntities(text)
        text = whitespaceRun.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let attributeRegexes: [String: NSRegularExpression] = Dictionary(
        uniqueKeysWithValues: ["class", "href", "title"].map {
            ($0, regex(#"(?:^|\s)"# + $0 + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#))
        })

    private static func attribute(_ attributes: String, _ name: String) -> String? {
        guard let regex = attributeRegexes[name] else { return nil }
        let ns = attributes as NSString
        guard let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let value = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
        guard value.location != NSNotFound else { return nil }
        return decodeHTMLEntities(ns.substring(with: value))
    }

    /// Whether a class attribute value lists `className` as one of its classes.
    private static func hasClass(_ attributes: String, _ className: String) -> Bool {
        guard let classes = attribute(attributes, "class"), !classes.isEmpty else { return false }
        return classes.components(separatedBy: .whitespaces).contains(className)
    }

    private static let divTag = regex(#"<(/?)div\b[^>]*>"#)
    private static let divOpen = regex(#"<div\b([^>]*)>"#)

    /// The `</div>` that closes the `<div ...>` opening at `start`, counting
    /// nested divs. `limit` bounds the scan; nil if unbalanced.
    private static func closingDiv(in html: String, from start: Int, limit: Int) -> NSRange? {
        var depth = 0
        var closing: NSRange?
        divTag.enumerateMatches(in: html, range: NSRange(location: start, length: limit - start)) { match, _, stop in
            guard let match else { return }
            depth += match.range(at: 1).length > 0 ? -1 : 1
            if depth == 0 {
                closing = match.range
                stop.pointee = true
            }
        }
        return closing
    }

    /// The inner HTML of the first `<div>` in `range` carrying `className`.
    private static func innerHTMLOfDiv(in html: String, range: NSRange, className: String) -> String? {
        let ns = html as NSString
        var inner: String?
        divOpen.enumerateMatches(in: html, range: range) { match, _, stop in
            guard let match, hasClass(ns.substring(with: match.range(at: 1)), className) else { return }
            stop.pointee = true
            let closing = closingDiv(in: html, from: match.range.location, limit: NSMaxRange(range))
            let innerStart = NSMaxRange(match.range)
            // Unbalanced (a block cut short by the next one): take what's there.
            let innerEnd = closing?.location ?? NSMaxRange(range)
            if innerEnd > innerStart { inner = ns.substring(with: NSRange(location: innerStart, length: innerEnd - innerStart)) }
        }
        return inner
    }

    // MARK: Result blocks

    /// A result block's opening tag: `<div class="… _0_SRI …">`, or the older
    /// grouped sub-result `<div class="… __srgi …">` (still read, in case
    /// Kagi brings it back).
    private static func resultBlockStarts(in html: String) -> [Int] {
        let ns = html as NSString
        var starts: [Int] = []
        divOpen.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let attributes = ns.substring(with: match.range(at: 1))
            guard attributes.contains("_0_SRI") || attributes.contains("__srgi") else { return }   // cheap pre-check
            if hasClass(attributes, "_0_SRI") || hasClass(attributes, "__srgi") { starts.append(match.range.location) }
        }
        return starts
    }

    private static let anchor = regex(#"<a\b([^>]*)>(.*?)</a\s*>"#)

    /// The title link: `<a class="__sri_title_link …" href>`, or the first
    /// `<a href>` inside a `__srgi-title` element.
    private static func titleLink(in html: String, block: NSRange) -> (href: String, title: String)? {
        let ns = html as NSString
        let groupedTitle = ns.range(of: "__srgi-title", options: [], range: block)
        var found: NSTextCheckingResult?
        anchor.enumerateMatches(in: html, range: block) { match, _, stop in
            guard let match else { return }
            let attributes = ns.substring(with: match.range(at: 1))
            let isTitleLink = hasClass(attributes, "__sri_title_link")
            let isGroupedLink = groupedTitle.location != NSNotFound && match.range.location > groupedTitle.location
            if isTitleLink || isGroupedLink {
                found = match
                stop.pointee = true
            }
        }
        guard let found else { return nil }
        let attributes = ns.substring(with: found.range(at: 1))
        let href = (attribute(attributes, "href") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var title = plainText(ns.substring(with: found.range(at: 2)))
        if title.isEmpty { title = (attribute(attributes, "title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !href.isEmpty, !title.isEmpty else { return nil }
        return (href, title)
    }

    private static let timeSpan = regex(#"<span\b[^>]*class\s*=\s*"[^"]*__sri-time[^"]*"[^>]*>(.*?)</span\s*>"#)
    private static let summarizeLink = regex(#"<a\b[^>]*class\s*=\s*"[^"]*summarize-link[^"]*"[^>]*>.*?</a\s*>"#)

    /// Snippet + date from the `__sri-desc` block (the date is a span inside
    /// it, and so is Kagi's "Summarize" link; neither is snippet text).
    private static func description(in html: String, block: NSRange) -> (snippet: String, date: String?) {
        guard let inner = innerHTMLOfDiv(in: html, range: block, className: "__sri-desc"), !inner.isEmpty else { return ("", nil) }
        let ns = inner as NSString
        var date: String?
        if let time = timeSpan.firstMatch(in: inner, range: NSRange(location: 0, length: ns.length)) {
            let text = plainText(ns.substring(with: time.range(at: 1)))
            if !text.isEmpty { date = text }
        }
        var text = timeSpan.stringByReplacingMatches(in: inner, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        text = summarizeLink.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
        return (plainText(text), date)
    }

    // MARK: Page

    private static func looksSignedOut(_ html: String) -> Bool {
        // A signed-in results page always has its results container, even
        // when it holds nothing ("We haven't found anything ... Based on your
        // current filters"). Kagi's marketing line ("Welcome to Kagi ... a
        // paid search engine that gives power back to the user") is in EVERY
        // page's meta description, so it proves nothing.
        if html.contains("_0_main-search-results") { return false }
        // Cloudflare Turnstile interstitial (what kagi.com shows a client
        // without a valid session) and Kagi's account sign-in form.
        if html.range(of: "turnstile", options: .caseInsensitive) != nil { return true }
        return html.contains("action=\"/loginname") || html.contains("action=\"/signin")
    }

    private static let externalLink = regex(#"href\s*=\s*"https?://(?![a-z0-9.-]*kagi\.com[/"])[^"]+""#)

    public static func parseResults(html: String) -> ParsedPage {
        var page = ParsedPage()
        guard !html.isEmpty else {
            page.kind = .unreadable
            return page
        }
        let length = (html as NSString).length
        let starts = resultBlockStarts(in: html)
        for (index, start) in starts.enumerated() {
            let next = index + 1 < starts.count ? starts[index + 1] : length
            // A block holding nested blocks (a result group) stops at its
            // first child: each child is read as its own block.
            let stop = closingDiv(in: html, from: start, limit: length).map { min(NSMaxRange($0), next) } ?? next
            let block = NSRange(location: start, length: stop - start)
            guard let link = titleLink(in: html, block: block) else { continue }
            var result = ParsedResult()
            result.urlString = link.href
            result.title = link.title
            let described = description(in: html, block: block)
            result.snippet = described.snippet
            result.dateText = described.date
            page.results.append(result)
        }
        page.hasMore = html.contains("id=\"load_more_results\"")

        if page.results.isEmpty {
            if looksSignedOut(html) {
                page.kind = .signedOut
            } else if !starts.isEmpty
                        || externalLink.numberOfMatches(in: html, range: NSRange(location: 0, length: length)) >= 5 {
                // Result blocks with no readable title link, or a page full
                // of links but no known result block: the markup has moved.
                page.kind = .unreadable
            }
        }
        return page
    }
}

// MARK: - Network

extension KagiSearch {
    /// Ephemeral and cookie-free: the session is the hand-set header, and a
    /// redirect to Kagi's sign-in keeps it.
    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    /// One results page (~175 KB of server-rendered HTML, usually back in
    /// well under a second). Redirects are followed: `response.url` is where
    /// Kagi ended up, which is how a rejected token shows (`isSignedOut`).
    public static func fetchPage(_ url: URL, token: String) async throws -> (data: Data, response: HTTPURLResponse) {
        let session = makeSession(timeout: searchTimeout)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request(for: url, token: token))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    /// Asks Kagi whether `token` signs in with one request to an account page.
    public static func checkSession(token: String) async -> (result: SessionCheck, error: Error?) {
        let session = makeSession(timeout: sessionCheckTimeout)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request(for: sessionCheckURL, token: token, timeout: sessionCheckTimeout))
            let http = response as? HTTPURLResponse
            return (sessionCheck(statusCode: http?.statusCode, finalURL: http?.url, failed: false), nil)
        } catch {
            return (.unreachable, error)
        }
    }
}
