import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches a linked article and extracts its prose for a Link / Post & link
/// summary (Reborn's article fetch): JSON-LD `articleBody` or the
/// `<article>`/`<main>` paragraphs, whichever is longer, then a strip-all pass,
/// then the meta description. A thin page falls back to its AMP version, then
/// to a crawler fetch. Text is cached per post for the session.
public enum AIArticleExtractor {
    static let maxArticleChars = 3000
    static let maxBytes = 3 * 1024 * 1024
    static let timeout: TimeInterval = 15

    static let browserUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    /// Only as a last resort: some single-page sites serve crawlers a rendered page.
    static let crawlerUA = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

    nonisolated(unsafe) private static var cache: [String: String] = [:]
    private static let cacheLock = NSLock()

    public static func cachedText(for key: String) -> String? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache[key]
    }

    private static func store(_ text: String, for key: String) {
        cacheLock.lock(); cache[key] = text; cacheLock.unlock()
    }

    public static func clearCache() {
        cacheLock.lock(); cache.removeAll(); cacheLock.unlock()
    }

    /// The article's prose (at least 200 characters), or nil when the page has
    /// none worth summarizing.
    public static func articleText(urlString: String, cacheKey: String,
                                   session: URLSession = .shared) async -> String? {
        if let cached = cachedText(for: cacheKey) { return cached }
        guard let url = URL(string: urlString) else { return nil }
        let first = await fetchAndExtract(url, userAgent: browserUA, session: session)
        var best = first.text ?? ""
        if best.count < 200 {
            // A transport failure won't be helped by refetching.
            if first.html == nil && first.transportFailed { return nil }
            if let html = first.html, let amp = ampURL(in: html, base: url), amp != url {
                let ampResult = await fetchAndExtract(amp, userAgent: browserUA, session: session)
                if let text = ampResult.text, text.count > best.count { best = text }
            }
            if best.count < 200 {
                let bot = await fetchAndExtract(url, userAgent: crawlerUA, session: session)
                if let text = bot.text, text.count > best.count { best = text }
            }
        }
        guard best.count >= 200 else {
            ApolloAILog.record("article: no readable text at \(url.host ?? urlString)")
            return nil
        }
        ApolloAILog.record("article: \(best.count) chars from \(url.host ?? urlString)")
        store(best, for: cacheKey)
        return best
    }

    private static func fetchAndExtract(_ url: URL, userAgent: String,
                                        session: URLSession) async -> (text: String?, html: String?, transportFailed: Bool) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await session.data(for: request) else { return (nil, nil, true) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              !data.isEmpty, data.count <= maxBytes else { return (nil, nil, false) }
        let html = decode(data, encodingName: http.textEncodingName)
        return (html.flatMap(extractText), html, false)
    }

    /// Charset-aware: a page read in the wrong encoding is mojibake to the model.
    static func decode(_ data: Data, encodingName: String?) -> String? {
        #if canImport(Darwin)
        if let name = encodingName {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId,
               let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) {
                return text
            }
        }
        #endif
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Extraction

    public static func extractText(_ html: String) -> String? {
        guard !html.isEmpty else { return nil }
        let jsonld = jsonLDText(html) ?? ""
        let capped = String(html.prefix(600_000))
        let stripped = replacing(#"<(script|style|noscript|template|svg|head|nav|header|footer|aside|form|figure)\b[^>]*>.*?</\1>"#,
                                 in: capped, with: " ", dotAll: true)
        let scope = mainRegion(stripped)

        var prose = ""
        for paragraph in matches(#"<p\b[^>]*>(.*?)</p>"#, in: scope, group: 1, dotAll: true) {
            let text = decodeEntities(replacing("<[^>]+>", in: paragraph, with: " "))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 40 { prose += text + "\n" }
            if prose.count >= maxArticleChars { break }
        }
        var text = jsonld.count > prose.count ? jsonld : prose
        if text.count < 200 {
            let all = decodeEntities(replacing("<[^>]+>", in: scope, with: " "))
            if all.count > text.count { text = all }
        }
        if text.count < 200, let meta = metaDescription(html), meta.count > text.count { text = meta }
        text = replacing(#"\s+"#, in: text, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maxArticleChars))
    }

    /// The page's `<article>`, else `<main>`, else the whole page.
    static func mainRegion(_ html: String) -> String {
        for tag in ["article", "main"] {
            guard let open = html.range(of: "<\(tag)\\b[^>]*>", options: [.regularExpression, .caseInsensitive]) else { continue }
            let rest = html[open.upperBound...]
            let end = rest.range(of: "</\(tag)>", options: [.caseInsensitive, .backwards])?.lowerBound ?? rest.endIndex
            if end > open.upperBound { return String(html[open.upperBound..<end]) }
        }
        return html
    }

    /// The longest `articleBody` across the page's JSON-LD blocks, else the
    /// longest `description`.
    static func jsonLDText(_ html: String) -> String? {
        var bestBody = "", bestDescription = ""
        for block in matches(#"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#,
                             in: html, group: 1, dotAll: true) {
            var json = block
            for marker in ["<!--", "-->", "//<![CDATA[", "<![CDATA[", "]]>"] {
                json = json.replacingOccurrences(of: marker, with: " ")
            }
            guard let data = json.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else { continue }
            var stack: [Any] = [root]
            var guardCount = 0
            while let node = stack.popLast(), guardCount < 4000 {
                guardCount += 1
                if let array = node as? [Any] {
                    stack.append(contentsOf: array)
                } else if let dict = node as? [String: Any] {
                    if let body = dict["articleBody"] as? String, body.count > bestBody.count { bestBody = body }
                    if let desc = dict["description"] as? String, desc.count > bestDescription.count { bestDescription = desc }
                    if let graph = dict["@graph"] { stack.append(graph) }
                    if let main = dict["mainEntity"] { stack.append(main) }
                }
            }
        }
        let chosen = bestBody.count >= 200 || bestBody.count >= bestDescription.count ? bestBody : bestDescription
        guard !chosen.isEmpty else { return nil }
        return decodeEntities(replacing("<[^>]+>", in: chosen, with: " "))
    }

    static func metaDescription(_ html: String) -> String? {
        for key in ["og:description", "twitter:description", "description"] {
            if let value = metaContent(html, key: key) { return value }
        }
        return nil
    }

    static func metaContent(_ html: String, key: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            #"<meta[^>]*\b(?:property|name)\s*=\s*["']"# + k + #"["'][^>]*\bcontent\s*=\s*(["'])(.*?)\1"#,
            #"<meta[^>]*\bcontent\s*=\s*(["'])(.*?)\1[^>]*\b(?:property|name)\s*=\s*["']"# + k + #"["']"#,
        ]
        let scan = String(html.prefix(200_000))
        for pattern in patterns {
            if let value = matches(pattern, in: scan, group: 2, dotAll: false, first: true).first {
                let decoded = decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    static func ampURL(in html: String, base: URL) -> URL? {
        let patterns = [
            #"<link[^>]*\brel\s*=\s*["']amphtml["'][^>]*\bhref\s*=\s*(["'])(.+?)\1"#,
            #"<link[^>]*\bhref\s*=\s*(["'])(.+?)\1[^>]*\brel\s*=\s*["']amphtml["']"#,
        ]
        let scan = String(html.prefix(200_000))
        for pattern in patterns {
            if let href = matches(pattern, in: scan, group: 2, dotAll: false, first: true).first {
                return URL(string: decodeEntities(href), relativeTo: base)?.absoluteURL
            }
        }
        return nil
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var s = text
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
                     "&ndash;": "\u{2013}", "&mdash;": "\u{2014}", "&hellip;": "\u{2026}"]
        for (entity, value) in named { s = s.replacingOccurrences(of: entity, with: value) }
        if let regex = try? NSRegularExpression(pattern: #"&#(\d{2,7});"#) {
            for match in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                guard let whole = Range(match.range, in: s), let digits = Range(match.range(at: 1), in: s),
                      let code = UInt32(s[digits]), code > 31, let scalar = Unicode.Scalar(code) else { continue }
                s.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return s.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Regex helpers

    private static func replacing(_ pattern: String, in text: String, with template: String, dotAll: Bool = false) -> String {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func matches(_ pattern: String, in text: String, group: Int, dotAll: Bool, first: Bool = false) -> [String] {
        var options: NSRegularExpression.Options = [.caseInsensitive]
        if dotAll { options.insert(.dotMatchesLineSeparators) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let found = first ? regex.firstMatch(in: text, range: range).map { [$0] } ?? [] : regex.matches(in: text, range: range)
        return found.compactMap { Range($0.range(at: group), in: text).map { String(text[$0]) } }
    }
}
