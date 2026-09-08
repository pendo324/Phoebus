import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// Parsed OpenGraph metadata for a rich link preview card (Reborn "Rich
/// Link Previews"). Parsing is pure so it is testable without a network
/// fetch; the card and the `URLSession` fetch live in PhoebusUI.
public struct OpenGraphMetadata: Sendable, Equatable {
    public var title: String?
    public var description: String?
    public var imageURLString: String?
    public var siteName: String?
    /// `og:video`/`og:video:url` meta tag, used by `SportsClipHost` to
    /// resolve a sports-clip page's playable video URL.
    public var videoURLString: String?
    /// `og:image:width` / `og:image:height`, when the page gives them.
    public var imageWidth: Double?
    public var imageHeight: Double?

    public init(title: String?, description: String?, imageURLString: String?, siteName: String?, videoURLString: String? = nil,
                imageWidth: Double? = nil, imageHeight: Double? = nil) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.title = title
        self.description = description
        self.imageURLString = imageURLString
        self.siteName = siteName
        self.videoURLString = videoURLString
    }

    public var isEmpty: Bool {
        title == nil && description == nil && imageURLString == nil && siteName == nil
    }
}

public enum OpenGraphParser {
    /// Extracts `og:*` / `twitter:*` meta tags from raw HTML with a
    /// lightweight regex scan rather than a DOM parser. Falls back from
    /// `og:*` to `twitter:*` for sites that only populate Twitter Card tags.
    public static func parse(html: String) -> OpenGraphMetadata {
        OpenGraphMetadata(
            title: metaContent(html: html, keys: ["og:title", "twitter:title"]),
            description: metaContent(html: html, keys: ["og:description", "twitter:description", "description"]),
            imageURLString: metaContent(html: html, keys: ["og:image", "twitter:image"]).map(upgradingToHTTPS),
            siteName: metaContent(html: html, keys: ["og:site_name"]),
            videoURLString: metaContent(html: html, keys: ["og:video:url", "og:video"]),
            imageWidth: metaContent(html: html, keys: ["og:image:width"]).flatMap(Double.init),
            imageHeight: metaContent(html: html, keys: ["og:image:height"]).flatMap(Double.init)
        )
    }

    /// App Transport Security blocks plain-http images, and sites that
    /// still publish an `http://` og:image almost always serve it over
    /// https too.
    static func upgradingToHTTPS(_ urlString: String) -> String {
        urlString.lowercased().hasPrefix("http://") ? "https://" + urlString.dropFirst(7) : urlString
    }

    private static func metaContent(html: String, keys: [String]) -> String? {
        for key in keys {
            if let value = firstMatch(html: html, key: key) {
                return value
            }
        }
        return nil
    }

    /// Matches a `<meta ... property="key" ... content="value" ...>` or
    /// `<meta ... name="key" ... content="value" ...>` tag regardless of
    /// attribute order (both orderings appear in the wild), and decodes
    /// common HTML entities in the extracted value.
    private static func firstMatch(html: String, key: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            #"<meta[^>]*(?:property|name)=["']\#(escapedKey)["'][^>]*content=["']([^"']*)["']"#,
            #"<meta[^>]*content=["']([^"']*)["'][^>]*(?:property|name)=["']\#(escapedKey)["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let contentRange = Range(match.range(at: 1), in: html) {
                let raw = String(html[contentRange])
                let decoded = decodeHTMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                return decoded.isEmpty ? nil : decoded
            }
        }
        return nil
    }

    /// Decodes the small set of HTML entities that actually show up in
    /// OpenGraph title/description text (full entity decoding needs an
    /// HTML parser; this covers the common cases without one).
    public static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "),
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric references (&#x27; &#8217;), which some sites send even
        // double-escaped, so after &amp; above.
        guard result.contains("&#"),
              let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") else { return result }
        let ns = result as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let body = ns.substring(with: match.range(at: 1))
            let value = body.hasPrefix("x") || body.hasPrefix("X")
                ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            if let value, let scalar = Unicode.Scalar(value) {
                out.unicodeScalars.append(scalar)
            } else {
                out += ns.substring(with: match.range)
            }
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}

/// Fetches a page and parses its OpenGraph metadata, decoding with the
/// page's declared charset (HTTP header, then HTML `<meta charset>`)
/// before falling back to UTF-8, so legacy charsets (EUC-KR, Shift_JIS,
/// GB18030, Big5) don't come out as mojibake.
public enum OpenGraphClient {
    public enum ClientError: Error, Sendable {
        case invalidResponse
    }

    public static func fetchMetadata(for url: URL, session: URLSession = .shared) async throws -> OpenGraphMetadata {
        // A browser user agent: many news sites answer the default
        // CFNetwork one with a bot wall instead of the article.
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(BrowserUserAgent.mobileSafari, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidResponse
        }
        let html = decodeHTML(data: data, headerEncoding: httpResponse.textEncodingName)
        return OpenGraphParser.parse(html: html)
    }

    /// Decodes raw page bytes to a `String`, resolving the character
    /// encoding from (in priority order) the HTTP `Content-Type`
    /// charset, an HTML `<meta charset>`/`http-equiv` declaration, or
    /// UTF-8 as the final fallback.
    public static func decodeHTML(data: Data, headerEncoding: String?) -> String {
        if let headerEncoding, let encoding = encoding(fromIANACharset: headerEncoding),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }
        // The charset declaration itself is always ASCII-safe, so a
        // provisional UTF-8/Latin-1 decode is sufficient just to find it.
        if let probe = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
           let metaCharset = metaCharset(fromHTML: probe),
           let encoding = encoding(fromIANACharset: metaCharset),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Extracts a charset name from `<meta charset="...">` or
    /// `<meta http-equiv="Content-Type" content="...;charset=...">`.
    public static func metaCharset(fromHTML html: String) -> String? {
        let headSlice = String(html.prefix(4096))
        if let regex = try? NSRegularExpression(pattern: #"<meta[^>]*charset=["']?([A-Za-z0-9_-]+)"#, options: .caseInsensitive) {
            let range = NSRange(headSlice.startIndex..., in: headSlice)
            if let match = regex.firstMatch(in: headSlice, range: range),
               let charsetRange = Range(match.range(at: 1), in: headSlice) {
                return String(headSlice[charsetRange])
            }
        }
        return nil
    }

    /// Maps an IANA charset name to a `String.Encoding`: the legacy CJK
    /// encodings plus common Western ones; nil (UTF-8 fallback) for anything
    /// unrecognized. The CJK ones need
    /// `CFStringConvertEncodingToNSStringEncoding`, unavailable on Linux,
    /// where they resolve to nil.
    public static func encoding(fromIANACharset name: String) -> String.Encoding? {
        switch name.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1": return .isoLatin1
        case "shift_jis", "shift-jis", "sjis": return .shiftJIS
        #if canImport(CoreFoundation)
        case "euc-kr":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
        case "gb18030":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        case "gbk", "gb2312":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_CN.rawValue)))
        case "big5":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        #endif
        default: return nil
        }
    }
}
