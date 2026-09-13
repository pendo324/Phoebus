import Foundation

/// The Search tab's engine, picked from the search field's magnifier and
/// remembered, with no setting (Reborn #1260, `UDKeySearchEngine`:
/// 0 = Reddit, Apollo's own search; 1 = Google).
public enum SearchEngine: Int, Sendable, CaseIterable {
    case reddit = 0
    case google = 1

    public static let key = "SearchEngine"

    public static var current: SearchEngine {
        get { SearchEngine(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .reddit }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    public var title: String { self == .reddit ? "Reddit" : "Google" }
    /// The menu rows' subtitles.
    public var subtitle: String { self == .reddit ? "Posts, subreddits and users" : "Reddit threads, found with Google" }
}

/// Google mode's filters, set from the chips above the results
/// (`UDKeyGoogleSearchTimeRange`, `UDKeyGoogleSearchExactWords`).
public struct GoogleSearchOptions: Equatable, Sendable {
    public enum TimeRange: Int, CaseIterable, Sendable {
        case any = 0, day, week, month, year

        public var title: String {
            switch self {
            case .any: return "Any Time"
            case .day: return "Past 24 Hours"
            case .week: return "Past Week"
            case .month: return "Past Month"
            case .year: return "Past Year"
            }
        }

        var tbs: String? {
            switch self {
            case .any: return nil
            case .day: return "qdr:d"
            case .week: return "qdr:w"
            case .month: return "qdr:m"
            case .year: return "qdr:y"
            }
        }
    }

    public var timeRange: TimeRange
    /// Google's "Verbatim" mode (`tbs=li:1`): no synonyms, no spelling
    /// rewrites.
    public var exactWords: Bool

    public init(timeRange: TimeRange = .any, exactWords: Bool = false) {
        self.timeRange = timeRange
        self.exactWords = exactWords
    }

    public static let timeRangeKey = "GoogleSearchTimeRange"
    public static let exactWordsKey = "GoogleSearchExactWords"

    public static func load() -> GoogleSearchOptions {
        GoogleSearchOptions(timeRange: TimeRange(rawValue: UserDefaults.standard.integer(forKey: timeRangeKey)) ?? .any,
                            exactWords: UserDefaults.standard.bool(forKey: exactWordsKey))
    }

    public func save() {
        UserDefaults.standard.set(timeRange.rawValue, forKey: Self.timeRangeKey)
        UserDefaults.standard.set(exactWords, forKey: Self.exactWordsKey)
    }
}

/// One Reddit result from Google.
public struct GoogleSearchResult: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case post, comment, subreddit, user, other }

    public var kind: Kind = .post
    /// Canonical `https://www.reddit.com/...`, nil until the Google link
    /// has been followed.
    public var url: URL?
    /// Google's own (encrypted `/goto`) link, followed only when the user
    /// acts on the result.
    public var googleLinkURL: URL?
    public var subreddit: String?
    public var username: String?
    public var postID: String?
    public var commentID: String?
    public var title = ""
    /// Plain snippet; the runs Google bolded (the query terms) are in
    /// `snippetBoldRanges` (UTF-16 offsets).
    public var snippet = ""
    public var snippetBoldRanges: [NSRange] = []
    /// Google's forum line ("30+ comments · 2 weeks ago").
    public var googleMeta: String?

    /// From Reddit (`/api/info`), after Read More; nil until then.
    public var redditInfo: GoogleSearchRedditInfo?

    public init() {}

    /// Fixed when the card is made (its first dedupe key), so following
    /// its link later doesn't change its identity in a list.
    public var id = ""

    /// Drops the same thread reached through www/old/np hosts, slugs and
    /// query strings, or listed again on a later page.
    public var dedupeKey: String {
        if let postID, !postID.isEmpty { return "t3_\(postID.lowercased())/\(commentID?.lowercased() ?? "")" }
        if let url {
            var path = url.path.lowercased()
            while path.hasSuffix("/") { path.removeLast() }
            return path
        }
        return "google:\(subreddit?.lowercased() ?? "")|\(title.lowercased())|\(googleMeta?.lowercased() ?? "")|\(snippet.lowercased())"
    }
}

/// The pure parts of Reborn's Google search: the query Google is sent, the
/// results URL, what a Reddit URL is, and reading the extractor's output.
public enum GoogleSearch {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let subredditToken = regex(#"(?<![\w/:.])/?r/([A-Za-z0-9][A-Za-z0-9_]{1,20})(?![\w/])"#)
    private static let siteOperator = regex(#"(^|\s)-?site:\S+"#)
    private static let trailingReddit = regex(#"\s+(on\s+)?reddit\s*$"#)
    private static let spaces = regex(#"\s{2,}"#)

    /// The query actually sent: `site:reddit.com` unless the user wrote a
    /// `site:`; `r/name` tokens become `site:reddit.com/r/name` (several
    /// OR-ed); a habitual trailing "reddit" is dropped. Quotes, `-`
    /// exclusions, `OR` and the rest pass through.
    public static func composeQuery(_ rawQuery: String) -> String {
        var query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "" }
        // Smart Punctuation's curly quotes; Google's phrase operator wants
        // plain ones.
        for curly in ["\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{2033}"] {
            query = query.replacingOccurrences(of: curly, with: "\"")
        }
        let userSite = siteOperator.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) != nil
        var subreddits: [String] = []
        if !userSite {
            let ns = query as NSString
            var seen = Set<String>()
            let stripped = NSMutableString(string: query)
            for match in subredditToken.matches(in: query, range: NSRange(location: 0, length: ns.length)).reversed() {
                let name = ns.substring(with: match.range(at: 1))
                if !seen.contains(name.lowercased()) {
                    seen.insert(name.lowercased())
                    subreddits.insert(name, at: 0)
                }
                stripped.replaceCharacters(in: match.range, with: " ")
            }
            query = stripped as String
        }
        let withoutReddit = trailingReddit.stringByReplacingMatches(
            in: query, range: NSRange(query.startIndex..., in: query), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !userSite, !withoutReddit.isEmpty { query = withoutReddit }
        query = spaces.stringByReplacingMatches(in: query, range: NSRange(query.startIndex..., in: query), withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if userSite { return query }
        let site: String
        switch subreddits.count {
        case 0: site = "site:reddit.com"
        case 1: site = "site:reddit.com/r/\(subreddits[0])"
        default: site = "(" + subreddits.map { "site:reddit.com/r/\($0)" }.joined(separator: " OR ") + ")"
        }
        return query.isEmpty ? site : "\(query) \(site)"
    }

    /// Google's UI language, from the device's first language (the forum
    /// line is shown verbatim, so it should read in the user's language).
    public static func languageCode(preferred: String = Locale.preferredLanguages.first ?? "en") -> String {
        let parts = preferred.split(separator: "-").map(String.init)
        let language = parts.first?.lowercased() ?? "en"
        if language == "zh", parts.count > 1 {
            let region = parts.last!.uppercased()
            return preferred.contains("Hant") || region == "TW" || region == "HK" ? "zh-TW" : "zh-CN"
        }
        return language.isEmpty ? "en" : language
    }

    /// The results page for `rawQuery`: `udm=14` is Google's plain Web
    /// view (no AI Overview, no carousels), `tbs` carries the chips.
    public static func searchURL(_ rawQuery: String, options: GoogleSearchOptions = .init(), page: Int = 0,
                                 language: String = languageCode()) -> URL? {
        let query = composeQuery(rawQuery)
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")!
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "hl", value: language),
                     URLQueryItem(name: "udm", value: "14")]
        let tbs = [options.timeRange.tbs, options.exactWords ? "li:1" : nil].compactMap { $0 }
        if !tbs.isEmpty { items.append(URLQueryItem(name: "tbs", value: tbs.joined(separator: ","))) }
        if page > 0 { items.append(URLQueryItem(name: "start", value: String(page * 10))) }
        components.queryItems = items
        // '+' would read as a space ("c++" → "c  ").
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    private static func isBase36(_ s: String) -> Bool {
        (2...13).contains(s.count) && s.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    private static func isName(_ s: String) -> Bool {
        (2...30).contains(s.count)
            && s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") }
    }

    private static func applyThreadTail(_ result: inout GoogleSearchResult, _ segments: [String], _ index: Int) {
        guard index + 1 < segments.count, isBase36(segments[index + 1]) else { return }
        result.postID = segments[index + 1].lowercased()
        result.kind = .post
        // After the slug, or after "comment" in /comments/<id>/comment/<cid>.
        if index + 3 < segments.count, isBase36(segments[index + 3]) {
            result.commentID = segments[index + 3].lowercased()
            result.kind = .comment
        }
    }

    /// What a Reddit URL from Google is, with its canonical www URL; nil
    /// for other sites and Reddit pages with no native screen (Answers,
    /// the media viewer, search, submit…).
    public static func result(for url: URL) -> GoogleSearchResult? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let reddit = host == "reddit.com" || host.hasSuffix(".reddit.com")
        let shortener = host == "redd.it"
        guard reddit || shortener else { return nil }
        let segments = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        var result = GoogleSearchResult()
        result.kind = .other
        if shortener {
            guard segments.count == 1, isBase36(segments[0]) else { return nil }
            result.postID = segments[0].lowercased()
            result.kind = .post
            result.url = URL(string: "https://www.reddit.com/comments/\(result.postID!)")
            return result
        }
        guard let first = segments.first?.lowercased() else { return nil }
        var canonicalPath: String?
        if first == "r", segments.count >= 2, isName(segments[1]) {
            result.subreddit = segments[1]
            let third = segments.count >= 3 ? segments[2].lowercased() : nil
            if segments.count >= 4, third == "comments" {
                applyThreadTail(&result, segments, 2)
                guard result.postID != nil else { return nil }
            } else if third == "s" {
                result.kind = .other
            } else if segments.count == 2 || (segments.count == 3 && ["hot", "new", "top", "rising", "about"].contains(third!)) {
                result.kind = .subreddit
                canonicalPath = "/r/\(segments[1])/"
            } else if third == "wiki" {
                result.kind = .other
            } else {
                return nil
            }
        } else if first == "user" || first == "u", segments.count >= 2, isName(segments[1]) {
            result.username = segments[1]
            let third = segments.count >= 3 ? segments[2].lowercased() : nil
            if segments.count >= 4, third == "comments" {
                applyThreadTail(&result, segments, 2)
                guard result.postID != nil else { return nil }
            } else if segments.count == 2 || (segments.count == 3 && ["submitted", "comments", "overview"].contains(third!)) {
                result.kind = .user
                canonicalPath = "/user/\(segments[1])/"
            } else {
                return nil
            }
        } else if first == "comments", segments.count >= 2 {
            applyThreadTail(&result, segments, 0)
            guard result.postID != nil else { return nil }
        } else if first == "gallery", segments.count >= 2, isBase36(segments[1]) {
            result.postID = segments[1].lowercased()
            result.kind = .post
            canonicalPath = "/comments/\(result.postID!)"
        } else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.reddit.com"
        components.path = canonicalPath ?? (url.path.isEmpty ? "/" : url.path)
        result.url = components.url
        return result.url == nil ? nil : result
    }

    private static let titleSuffix = regex(#"\s*(?::|-|–|—|\|)\s*(?:r/[A-Za-z0-9_]+|reddit(?:\.com)?)\s*$"#)
    private static let titlePrefix = regex(#"^r/[A-Za-z0-9_]+\s*[-–—:|]\s*"#)

    /// "Title : r/PTCGP", "Title - Reddit", "r/PTCGP - Title" → "Title".
    public static func cleanTitle(_ title: String) -> String {
        var clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<2 {
            let next = titleSuffix.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
            if next == clean || next.isEmpty { break }
            clean = next
        }
        let unprefixed = titlePrefix.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
        if !unprefixed.isEmpty { clean = unprefixed }
        return clean.isEmpty ? title : clean
    }

    private static let snippetPrefix = regex(#"^r/[A-Za-z0-9_]+\s*[-–—·:]\s*"#)
    private static let snippetReadMore = regex(#"\s*(?:Read more|More)\s*$"#)

    /// The extractor's snippet, bold runs wrapped in U+0001…U+0002, to
    /// plain text plus bold ranges, whitespace collapsed, Google's leading
    /// "r/sub - " and trailing "Read more" dropped. Adjacent runs merge.
    public static func parseMarkedSnippet(_ marked: String) -> (text: String, bold: [NSRange]) {
        var text = ""
        var ranges: [NSRange] = []
        var boldStart: Int?
        var pendingSpace = false
        var length: Int { (text as NSString).length }
        for scalar in marked.unicodeScalars {
            if scalar == "\u{1}" {
                if pendingSpace, !text.isEmpty { text += " "; pendingSpace = false }
                boldStart = length
                continue
            }
            if scalar == "\u{2}" {
                if let start = boldStart, length > start {
                    var range = NSRange(location: start, length: length - start)
                    if let last = ranges.last, NSMaxRange(last) + 1 >= range.location, NSMaxRange(last) <= range.location {
                        range = NSUnionRange(last, range)
                        ranges.removeLast()
                    }
                    ranges.append(range)
                }
                boldStart = nil
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "\u{A0}" {
                if !text.isEmpty { pendingSpace = true }
                continue
            }
            if pendingSpace { text += " "; pendingSpace = false }
            text.unicodeScalars.append(scalar)
        }
        let ns = text as NSString
        let cut = snippetPrefix.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
        var end = snippetReadMore.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.range.location ?? ns.length
        if end < cut { end = cut }
        let result = ns.substring(with: NSRange(location: cut, length: end - cut))
        let shifted = ranges.compactMap { range -> NSRange? in
            guard NSMaxRange(range) > cut, range.location < end else { return nil }
            let start = max(range.location, cut) - cut
            let stop = min(NSMaxRange(range), end) - cut
            return stop > start ? NSRange(location: start, length: stop - start) : nil
        }
        return (result, shifted)
    }

    private static let subredditInLine = regex(#"(?:^|[\s·:|/-])r/([A-Za-z0-9][A-Za-z0-9_]{1,20})\b"#)

    /// "Reddit · r/PTCGP" (Google's breadcrumb) or "Title : r/PTCGP" → "PTCGP".
    public static func subreddit(fromLines lines: [String], title: String) -> String? {
        for line in lines + [title] {
            let ns = line as NSString
            if let match = subredditInLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    /// Google's forum line: a short line with a digit and a "·"
    /// ("30+ comments · 2 weeks ago"), else the first line with a digit.
    /// Language-neutral on purpose: digits and "·" survive localization.
    public static func meta(fromLines lines: [String], title: String) -> String? {
        var fallback: String?
        for line in lines where line.count >= 3 {
            let lower = line.lowercased()
            if lower.hasPrefix("reddit") || lower.hasPrefix("r/") || lower.hasPrefix("http")
                || lower.contains("reddit.com") || line == title { continue }
            guard line.rangeOfCharacter(from: .decimalDigits) != nil else { continue }
            if line.contains("·") || line.contains("•") { return line }
            if fallback == nil { fallback = line }
        }
        return fallback
    }

    /// The extractor's raw results to de-duplicated Reddit results.
    public static func results(fromRaw raw: [[String: Any]]) -> [GoogleSearchResult] {
        var results: [GoogleSearchResult] = []
        var seen = Set<String>()
        for item in raw {
            let title = item["title"] as? String ?? ""
            let lines = (item["anchorLines"] as? [String] ?? []) + (item["lines"] as? [String] ?? [])
            var result: GoogleSearchResult
            if let direct = (item["url"] as? String).flatMap(URL.init(string:)) {
                guard let classified = Self.result(for: direct) else { continue }
                result = classified
            } else if let go = (item["go"] as? String).flatMap(URL.init(string:)) {
                result = GoogleSearchResult()
                result.kind = .post
                result.googleLinkURL = go
                result.subreddit = subreddit(fromLines: lines, title: title)
            } else {
                continue
            }
            result.title = cleanTitle(title)
            let key = result.dedupeKey
            if seen.contains(key) { continue }
            seen.insert(key)
            result.id = key
            let parsed = parseMarkedSnippet(item["snippet"] as? String ?? "")
            result.snippet = parsed.text
            result.snippetBoldRanges = parsed.bold
            result.googleMeta = meta(fromLines: lines, title: result.title)
            results.append(result)
        }
        return results
    }

    /// Copies a followed link's destination onto `result`. False when it
    /// isn't a Reddit page with a native screen.
    public static func apply(_ destination: URL, to result: inout GoogleSearchResult) -> Bool {
        guard let classified = Self.result(for: destination) else { return false }
        result.url = classified.url
        result.kind = classified.kind
        if let subreddit = classified.subreddit { result.subreddit = subreddit }
        if let username = classified.username { result.username = username }
        result.postID = classified.postID
        result.commentID = classified.commentID
        return true
    }

    /// Google's suggestions (`client=firefox`: `["q", ["s1", "s2", …]]`).
    public static func suggestionsURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
        components.queryItems = [URLQueryItem(name: "client", value: "firefox"),
                                 URLQueryItem(name: "hl", value: languageCode()),
                                 URLQueryItem(name: "q", value: query)]
        return components.url
    }

    public static func parseSuggestions(_ data: Data) -> [String] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any], array.count > 1,
              let list = array[1] as? [String] else { return [] }
        return list
    }

    /// Timing: a page gets 25 s (5 min while the
    /// user answers Google's check), polled every 0.35 s; an empty page
    /// is re-read 4 times before it counts as "no results", and a page
    /// still loading is taken once its result count held for 6 polls.
    public static let pageTimeout: TimeInterval = 25
    public static let verificationTimeout: TimeInterval = 300
    public static let pollInterval: TimeInterval = 0.35
    public static let emptyPollsToSettle = 4
    public static let stablePollsToAccept = 6
    /// "Google is taking longer than usual." shows after this long.
    public static let slowNoticeDelay: TimeInterval = 8

    /// Reads the rendered results page, by structure rather than class
    /// names (obfuscated, rotating) or text (localized): a result is an
    /// `<a href>` holding a heading that points at Reddit directly, via
    /// `google.com/url?q=`, or via the opaque `/goto` link; its block is
    /// the highest ancestor holding no other result; the snippet is the
    /// longest text element in it outside the title; the lines around it
    /// carry Google's forum line. Bold runs are wrapped in U+0001…U+0002.
    /// Ported from Reborn's extractor script.
    public static let extractorJS = #"""
    (function(){var out={href:location.href,ready:document.readyState,results:[]};function T(el){return el?(el.innerText||el.textContent||'').replace(/\s+/g,' ').trim():'';}try{var host=location.hostname,path=location.pathname;if(/^\/sorry(\/|$)/.test(path)){out.challenge='captcha';return JSON.stringify(out);}if(/(^|\.)consent\.(google|youtube)\./.test(host)){out.challenge='consent';return JSON.stringify(out);}if(document.querySelector('form[action*="consent.google"],iframe[src*="consent.google"]')){out.challenge='consent';}if(document.querySelector('#captcha-form,iframe[src*="recaptcha"],div.g-recaptcha')){out.challenge='captcha';return JSON.stringify(out);}var rso=document.getElementById('rso'),search=document.getElementById('search');out.container=!!(rso||search);var root=rso||search||document.getElementById('main')||document.body;if(!root)return JSON.stringify(out);function unwrap(h){if(!h)return null;var u;try{u=new URL(h,location.href);}catch(e){return null;}if(/(^|\.)google\.[a-z.]+$/.test(u.hostname)){if(u.pathname==='/goto')return {go:u.href};if(u.pathname==='/url'||u.pathname==='/interstitial'){var q=u.searchParams.get('q')||u.searchParams.get('url');if(!q)return null;if(/^https?:/.test(q)){try{return {url:new URL(q).href};}catch(e){return null;}}return {go:u.href};}return null;}return {url:u.href};}function isReddit(h){try{var x=new URL(h).hostname.toLowerCase();return x==='reddit.com'||/\.reddit\.com$/.test(x)||x==='redd.it';}catch(e){return false;}}var HSEL='h3,[role="heading"]';function titleAnchors(scope){var list=[],as=scope.querySelectorAll('a[href]');for(var i=0;i<as.length;i++){var h=as[i].querySelector(HSEL);if(h&&T(h).length)list.push(as[i]);}return list;}function marked(el){var s='';(function walk(n,b){for(var c=n.firstChild;c;c=c.nextSibling){if(c.nodeType===3){s+=b?'\u0001'+c.nodeValue+'\u0002':c.nodeValue;continue;}if(c.nodeType!==1)continue;var tag=c.tagName;if(tag==='SCRIPT'||tag==='STYLE'||tag==='A'||tag==='svg'||tag==='SVG'||tag==='IMG'||tag==='G-IMG')continue;var cs=getComputedStyle(c);if(cs.display==='none'||cs.visibility==='hidden')continue;var bold=b||tag==='EM'||tag==='B'||tag==='STRONG'||parseInt(cs.fontWeight,10)>=600;if(tag==='BR'||cs.display==='block'||cs.display==='flex')s+=' ';walk(c,bold);}})(el,false);return s;}var anchors=titleAnchors(root);out.anchorCount=anchors.length;out.containerLinks=(rso||search)?(rso||search).querySelectorAll('a[href]').length:0;var cur=parseInt(new URL(location.href).searchParams.get('start')||'0',10);out.next=false;var sl=document.querySelectorAll('a[href*="start="]');for(var n=0;n<sl.length;n++){try{var st=parseInt(new URL(sl[n].getAttribute('href'),location.href).searchParams.get('start')||'0',10);if(st>cur){out.next=true;break;}}catch(e){}}for(var i=0;i<anchors.length;i++){var a=anchors[i];var link=unwrap(a.getAttribute('href'));if(!link||(link.url&&!isReddit(link.url)))continue;var heading=a.querySelector(HSEL);var title=T(heading);var block=a;for(var p=a.parentElement;p&&p!==root&&p!==document.body;p=p.parentElement){if(titleAnchors(p).length>1)break;block=p;}var best=null,bestLen=0,els=block.querySelectorAll('div,span');for(var j=0;j<els.length;j++){var el=els[j];if(a.contains(el)||el.contains(a))continue;var t=T(el);if(t.length<25)continue;var dominated=false;for(var c=el.firstElementChild;c;c=c.nextElementSibling){if(T(c).length>=t.length*0.9){dominated=true;break;}}if(dominated)continue;if(t.length>bestLen){best=el;bestLen=t.length;}}var snippet=best?marked(best):'';var lines=[];var leafs=block.querySelectorAll('div,span');for(var k=0;k<leafs.length;k++){var lf=leafs[k];if(a.contains(lf)||(best&&(best.contains(lf)||lf.contains(best)))||lf.contains(a))continue;if(lf.querySelector('div,span'))continue;var lt=T(lf);if(!lt||lt.length>80)continue;if(lines.indexOf(lt)<0)lines.push(lt);}var inAnchor=[];var al=a.querySelectorAll('div,span,cite');for(var m=0;m<al.length;m++){var x=al[m];if(x.querySelector('div,span,cite'))continue;var xt=T(x);if(xt&&xt!==title&&inAnchor.indexOf(xt)<0)inAnchor.push(xt);}out.results.push({url:link.url||null,go:link.go||null,title:title,snippet:snippet,lines:lines,anchorLines:inAnchor});}}catch(e){out.error=String(e&&e.message||e);}return JSON.stringify(out);})()
    """#
}

/// What Read More shows from Reddit's own data.
public struct GoogleSearchRedditInfo: Equatable, Sendable {
    public enum Media: Sendable { case none, image, gallery, video, link }

    public var title: String?
    public var author: String?
    /// Selftext or comment body, markdown source; nil when removed/deleted.
    public var body: String?
    public var removedOrDeleted = false
    public var score = 0
    public var commentCount = 0
    public var created: Date?
    public var over18 = false
    public var spoiler = false
    public var media: Media = .none
    public var linkDomain: String?
    public var subreddit: String?

    public init() {}

    /// Reddit-hosted media is labeled by kind; only a real external site
    /// shows its domain.
    static func media(for post: [String: Any]) -> Media {
        if post["is_self"] as? Bool == true { return .none }
        if post["is_gallery"] as? Bool == true { return .gallery }
        let domain = (post["domain"] as? String ?? "").lowercased()
        let hint = post["post_hint"] as? String ?? ""
        if post["is_video"] as? Bool == true || domain == "v.redd.it" || hint == "hosted:video" || hint == "rich:video" { return .video }
        if domain == "i.redd.it" || hint == "image" { return .image }
        if domain.isEmpty || domain.hasPrefix("self.") || domain == "reddit.com" || domain.hasSuffix(".reddit.com")
            || domain.hasSuffix("redd.it") { return .none }
        return .link
    }

    /// Reads one result's post (and comment) out of an `/api/info` listing.
    public static func parse(_ data: Data, postID: String?, commentID: String?) -> GoogleSearchRedditInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let children = (root["data"] as? [String: Any])?["children"] as? [[String: Any]] else { return nil }
        var post: [String: Any]?, comment: [String: Any]?
        for child in children {
            guard let thing = child["data"] as? [String: Any], let id = (thing["id"] as? String)?.lowercased() else { continue }
            if child["kind"] as? String == "t3", id == postID?.lowercased() { post = thing }
            if child["kind"] as? String == "t1", id == commentID?.lowercased() { comment = thing }
        }
        guard post != nil || comment != nil else { return nil }
        var info = GoogleSearchRedditInfo()
        if let post {
            info.title = post["title"] as? String
            info.commentCount = post["num_comments"] as? Int ?? 0
            info.subreddit = post["subreddit"] as? String
            info.over18 = post["over_18"] as? Bool ?? false
            info.spoiler = post["spoiler"] as? Bool ?? false
            info.media = media(for: post)
            if info.media == .link, var domain = (post["domain"] as? String)?.lowercased() {
                if domain.hasPrefix("www.") { domain.removeFirst(4) }
                info.linkDomain = domain
            }
        }
        let primary = comment ?? post ?? [:]
        info.author = primary["author"] as? String
        info.score = primary["score"] as? Int ?? 0
        if let created = primary["created_utc"] as? Double, created > 0 { info.created = Date(timeIntervalSince1970: created) }
        var body = comment != nil ? comment?["body"] as? String : post?["selftext"] as? String
        if body == "[removed]" || body == "[deleted]" { info.removedOrDeleted = true; body = nil }
        info.body = body?.isEmpty == true ? nil : body
        return info
    }

    /// 999, 1.2k, 15k, 1.3m.
    public static func compactCount(_ value: Int) -> String {
        let magnitude = abs(Double(value))
        guard magnitude >= 1000 else { return String(value) }
        let divisor = magnitude >= 1_000_000 ? 1_000_000.0 : 1000.0
        var number = String(format: "%.1f", Double(value) / divisor)
        if number.hasSuffix(".0") { number.removeLast(2) }
        return number + (divisor == 1_000_000 ? "m" : "k")
    }

    /// Apollo's compact ages: 45m, 15h, 3d, 2mo, 1y.
    public static func compactAge(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        if s < 86400 * 30 { return "\(Int(s / 86400))d" }
        if s < 86400 * 365 { return "\(Int(s / (86400 * 30)))mo" }
        return "\(Int(s / (86400 * 365)))y"
    }
}

public extension GoogleSearch {
    /// Markdown source to readable plain text for Read More.
    static func plainText(fromMarkdown markdown: String) -> String {
        guard !markdown.isEmpty else { return "" }
        let rules: [(String, String)] = [
            (#"\\([^\w\s])"#, "$1"),
            (#"(?m)^```.*$"#, ""),
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"<(https?://[^>]+)>"#, "$1"),
            (#">!(.*?)!<"#, "$1"),
            (#"(?m)^\s{0,3}#{1,6}\s*"#, ""),
            (#"(?m)^\s*(?:&gt;|>)\s?"#, ""),
            (#"(?m)^\s*[-*+]\s+"#, "• "),
            (#"(\*\*|__)(.+?)\1"#, "$2"),
            (#"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, "$1"),
            (#"~~(.+?)~~"#, "$1"),
            (#"`([^`]*)`"#, "$1"),
            (#"\^\(([^)]*)\)"#, "$1"),
            (#"(?m)^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$"#, ""),
            (#"(?m)^\s*(\*\s*){3,}$|^\s*(-\s*){3,}$"#, ""),
            (#"&nbsp;|&#x200B;"#, " "),
            (#"\n{3,}"#, "\n\n"),
        ]
        var text = markdown
        for (pattern, template) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
        text = text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
