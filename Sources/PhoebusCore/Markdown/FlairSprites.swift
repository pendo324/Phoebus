import Foundation

/// Old-reddit CSS sprite flairs (Reborn #1215). Subreddits like r/nintendo
/// keep their flairs in the old-reddit stylesheet: each template has a
/// `flair_css_class` whose picture is a region of one sprite sheet. The
/// flair API returns those templates with no text or image, so the picker
/// reads the stylesheet and crops the sheet itself.
public enum FlairSprites {
    /// One flair's picture: a rectangle of `sheetURL`, in the sheet's
    /// points (CSS pixels).
    public struct Region: Equatable, Sendable {
        public var sheetURL: URL
        public var rect: CGRect
        /// The base rule had a `border-radius` (r/nintendo's are circles).
        public var isRound: Bool
    }

    /// Parses the common single-sheet pattern into `css_class -> Region`.
    /// `images` is the stylesheet's uploaded-image list (`name -> url`), which
    /// the CSS refers to as `%%name%%`.
    ///
    /// Returns an empty map for layouts Reborn also refuses (more than one
    /// flair sheet, or no plain `.flair` base rule with a size), so the picker
    /// falls back to names only.
    public static func parse(css: String, images: [String: String]) -> [String: Region] {
        guard !css.isEmpty else { return [:] }
        let ns = css as NSString
        let rules = ruleRegex.matches(in: css, range: NSRange(location: 0, length: ns.length)).map {
            (selector: ns.substring(with: $0.range(at: 1)), body: ns.substring(with: $0.range(at: 2)))
        }

        // Base rule: a bare `.flair` (not `.flair-x`, not `.flair[attr]`)
        // with a background image and a size.
        var sheet: URL?
        var baseSize = CGSize.zero
        var round = false
        var flairSheets = Set<URL>()
        for rule in rules {
            let body = rule.body
            guard body.contains("background-image"), !body.contains("background-position"),
                  rule.selector.range(of: #"\.flair(?![\w\[-])"#, options: .regularExpression) != nil else { continue }
            var resolved: URL?
            if let name = firstGroup(body, #"background-image\s*:\s*url\(\s*["']?%%([^%]+)%%"#),
               let url = images[name] {
                resolved = secureURL(url)
            } else if let direct = firstGroup(body, #"background-image\s*:\s*url\(\s*["']?(https?://[^"')]+)"#) {
                resolved = secureURL(direct)
            }
            guard let resolved else { continue }
            flairSheets.insert(resolved)
            if sheet == nil,
               let w = firstGroup(body, #"width\s*:\s*([0-9.]+)px"#).flatMap(Double.init), w > 0,
               let h = firstGroup(body, #"height\s*:\s*([0-9.]+)px"#).flatMap(Double.init), h > 0 {
                sheet = resolved
                baseSize = CGSize(width: w, height: h)
                round = body.contains("border-radius")
            }
        }
        guard let sheet, flairSheets.count == 1 else { return [:] }

        var map: [String: Region] = [:]
        for rule in rules {
            let body = rule.body as NSString
            guard let position = positionRegex.firstMatch(in: rule.body, range: NSRange(location: 0, length: body.length)),
                  let bx = Double(body.substring(with: position.range(at: 1))),
                  let by = Double(body.substring(with: position.range(at: 2))) else { continue }
            var size = baseSize
            if let w = firstGroup(rule.body, #"width\s*:\s*([0-9.]+)px"#).flatMap(Double.init), w > 0 { size.width = w }
            if let h = firstGroup(rule.body, #"height\s*:\s*([0-9.]+)px"#).flatMap(Double.init), h > 0 { size.height = h }
            let selector = rule.selector as NSString
            for match in classRegex.matches(in: rule.selector, range: NSRange(location: 0, length: selector.length)) {
                let cssClass = selector.substring(with: match.range(at: 1))
                guard map[cssClass] == nil else { continue }
                map[cssClass] = Region(sheetURL: sheet,
                                       rect: CGRect(origin: CGPoint(x: -bx, y: -by), size: size),
                                       isRound: round)
            }
        }
        return map
    }

    /// The stylesheet endpoint's `images` array as `name -> url`.
    public static func imageMap(_ images: [[String: Any]]) -> [String: String] {
        var map: [String: String] = [:]
        for image in images {
            if let name = image["name"] as? String, let url = image["url"] as? String { map[name] = url }
        }
        return map
    }

    /// Reddit lists some sheets as `http://b.thumbs.redditmedia.com`, which
    /// App Transport Security blocks; the same host serves https.
    static func secureURL(_ string: String) -> URL? {
        var s = string
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }
        if s.hasPrefix("//") { s = "https:" + s }
        return URL(string: s)
    }

    private static let ruleRegex = try! NSRegularExpression(pattern: #"([^{}]*)\{([^{}]*)\}"#)
    private static let classRegex = try! NSRegularExpression(pattern: #"\.flair-([A-Za-z0-9_-]+)"#)
    private static let positionRegex = try! NSRegularExpression(
        pattern: #"background-position\s*:\s*(-?[0-9.]+)(?:px)?\s+(-?[0-9.]+)(?:px)?"#)

    private static func firstGroup(_ string: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: match.range(at: 1))
    }
}
