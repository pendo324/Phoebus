import Foundation

/// Readers for Reddit's Shreddit award partials. These are server-rendered
/// HTML fragments Reddit can reshape at any time, so each reader keeps only
/// what it recognises and returns nothing rather than a guess.
public enum AwardHTML {
    // MARK: Thread fragment

    /// What a comment-tree fragment says about awards.
    public struct Fragment: Sendable, Equatable {
        /// Fullname to badge, for the things that have awards.
        public var badges: [String: AwardBadge]
        /// Every post or comment the fragment lists, awarded or not, so a
        /// thing missing from `badges` is known to have none.
        public var listed: Set<String>

        public init(badges: [String: AwardBadge] = [:], listed: Set<String> = []) {
            self.badges = badges
            self.listed = listed
        }
    }

    /// The awards of the posts and comments in a comment-tree fragment: the
    /// `<award-button>` of each thing (featured award id, its icon and the
    /// total) and the `<shreddit-comment>` `has-paid-award` flag. Things
    /// without awards, or whose count doesn't read as a positive number, get
    /// no badge.
    public static func fragment(_ html: String) -> Fragment {
        var paidByThing: [String: Bool] = [:]
        var countByThing: [String: Int] = [:]
        var listed = Set<String>()
        for attributes in tags(named: "shreddit-comment", in: html) {
            guard let id = attributes["thingid"], !id.isEmpty else { continue }
            listed.insert(id)
            paidByThing[id] = attributes["has-paid-award"] != nil
            if let count = attributes["award-count"].flatMap(integer), count > 0 { countByThing[id] = count }
        }
        var result: [String: AwardBadge] = [:]
        for attributes in tags(named: "award-button", in: html) {
            guard let id = attributes["thing-id"], !id.isEmpty else { continue }
            listed.insert(id)
            guard let count = attributes["count"].flatMap(integer), count > 0 else { continue }
            let awardID = attributes["award-id"].flatMap { $0.isEmpty ? nil : $0 }
            result[id] = AwardBadge(
                thingID: id, count: count, awardID: awardID,
                iconURL: attributes["icon-url"].flatMap(secureURL),
                hasPaidAward: paidByThing[id] ?? awardID.map { !$0.hasPrefix("award_free_") } ?? false)
        }
        // A counted comment whose button gave no icon still has awards.
        for (id, count) in countByThing where result[id] == nil {
            result[id] = AwardBadge(thingID: id, count: count, awardID: nil, iconURL: nil,
                                    hasPaidAward: paidByThing[id] ?? false)
        }
        return Fragment(badges: result, listed: listed)
    }

    public static func badges(inFragment html: String) -> [String: AwardBadge] { fragment(html).badges }

    // MARK: Leaderboard

    /// The leaderboard partial. `nil` when it has neither totals nor rows.
    public static func leaderboard(html: String) -> AwardLeaderboard? {
        // The panel, not the tab button, which carries the same slot name.
        let pageTwo = html.range(of: #"<div slot="page-2""#)
        let awardsHTML = pageTwo.map { String(html[..<$0.lowerBound]) } ?? html
        let giversHTML = pageTwo.map { String(html[$0.upperBound...]) }

        var tallies: [AwardTally] = []
        let rowEnd = "</report-award>"
        var rest = Substring(awardsHTML)
        while let end = rest.range(of: rowEnd) {
            let row = rest[..<end.lowerBound]
            rest = rest[end.upperBound...]
            if let tally = tally(inRow: String(row)) { tallies.append(tally) }
        }

        let totalAwards = total(after: "award-label", in: html)
        let totalGold = total(after: "gold-label", in: html)
        guard !tallies.isEmpty || totalAwards != nil || totalGold != nil else { return nil }
        return AwardLeaderboard(totalAwards: totalAwards, totalGold: totalGold, tallies: tallies,
                                topAwarders: giversHTML.map(topAwarders) ?? [])
    }

    /// One award row, up to its `<report-award>` tag (which names the award).
    private static func tally(inRow row: String) -> AwardTally? {
        guard let reportStart = row.range(of: "<report-award"),
              let id = tags(named: "report-award", in: row).first?["award-id"], !id.isEmpty else { return nil }
        // The first row's text also holds the totals and tabs above it.
        let body = String(row[..<reportStart.lowerBound])
            .components(separatedBy: #"<div class="flex justify-between px-sm">"#).last ?? ""

        let lottie = tags(named: "shreddit-lottie-player", in: body).first
        let image = tags(named: "img", in: body).first { !($0["alt"] ?? "").isEmpty }
        let name = lottie?["description"] ?? image?["alt"]
        let icon = (lottie?["placeholder-src"] ?? image?["src"]).flatMap(secureURL)
        guard let name = name.map(decodeEntities), !name.isEmpty,
              let count = firstCapture(body, #"<span class="text-secondary-plain">\s*([\d,.\s]+?)\s*</span>"#).flatMap(integer)
        else { return nil }
        let gold = firstCapture(body, #"<span class="flex gap-2xs[^"]*">\s*<span>\s*([\d,.\s]+?)\s*</span>"#)
            .flatMap(integer) ?? 0
        return AwardTally(id: id, name: name, count: count, gold: gold, iconURL: icon)
    }

    private static func total(after label: String, in html: String) -> Int? {
        guard let start = html.range(of: "id=\"\(label)\"") else { return nil }
        return firstCapture(String(html[start.upperBound...]), #"<span class="text-32[^"]*">\s*([\d,.\s]+?)\s*</span>"#)
            .flatMap(integer)
    }

    private static func topAwarders(in html: String) -> [AwardGiver] {
        let parts = html.components(separatedBy: #"<div class="flex justify-between px-sm">"#).dropFirst()
        return parts.compactMap { part in
            guard let gold = firstCapture(part, #"<span class="text-14 text-secondary-plain">\s*([\d,.\s]+?)\s*</span>"#)
                .flatMap(integer) else { return nil }
            if part.contains("[anonymous]") { return AwardGiver(username: nil, gold: gold) }
            guard let name = firstCapture(part, #"href="/user/([^"/]+)""#) else { return nil }
            return AwardGiver(username: decodeEntities(name), gold: gold)
        }
    }

    // MARK: Award dialog

    /// The award dialog partial. `nil` when it lists no awards.
    public static func dialog(html: String) -> AwardDialog? {
        var catalogue: [AwardCatalogueEntry] = []
        var seen = Set<String>()
        for attributes in tags(named: "button", in: html) {
            guard let id = attributes["data-award-id"], !id.isEmpty, seen.insert(id).inserted,
                  let name = attributes["data-award-name"].map(decodeEntities), !name.isEmpty,
                  let price = attributes["data-gold-price"].flatMap(integer) else { continue }
            catalogue.append(AwardCatalogueEntry(
                id: id, name: name, goldPrice: price,
                iconURL: attributes["data-static-icon-url"].flatMap(secureURL),
                isQuickGive: attributes["data-is-quick-give"] != nil))
        }
        guard !catalogue.isEmpty else { return nil }
        let balance = tags(named: "award-selection-sheet", in: html).first?["gold-balance"].flatMap(integer)
        let leaderboard = tags(named: "faceplate-partial", in: html)
            .compactMap { $0["src"] }
            .first { $0.hasPrefix("/svc/shreddit/partial/") && $0.contains("/award-leaderboard") }
            .flatMap { URL(string: "https://www.reddit.com" + $0) }
        return AwardDialog(catalogue: catalogue, goldBalance: balance, leaderboardURL: leaderboard)
    }

    // MARK: Tags

    /// The attributes of every `<name ...>` start tag in `html`, with
    /// lower-cased names and entity-decoded values. A bare attribute maps to
    /// the empty string.
    static func tags(named name: String, in html: String) -> [[String: String]] {
        let pattern = "<" + NSRegularExpression.escapedPattern(for: name)
            + #"(?=[\s/>])((?:[^>"']|"[^"]*"|'[^']*')*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let whole = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: whole).compactMap { match in
            Range(match.range(at: 1), in: html).map { attributes(in: String(html[$0])) }
        }
    }

    private static let attributeRegex = try? NSRegularExpression(
        pattern: #"([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#)

    private static func attributes(in text: String) -> [String: String] {
        guard let attributeRegex else { return [:] }
        var result: [String: String] = [:]
        for match in attributeRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let value = (2...4).lazy.compactMap { Range(match.range(at: $0), in: text) }.first
                .map { decodeEntities(String(text[$0])) } ?? ""
            let key = text[nameRange].lowercased()
            if result[key] == nil { result[key] = value }
        }
        return result
    }

    // MARK: Values

    /// "1,234" and "1.234" read as 1234; anything else is nil.
    static func integer(_ text: String) -> Int? {
        let digits = text.filter { !$0.isWhitespace && $0 != "," && $0 != "." }
        return digits.isEmpty || !digits.allSatisfy(\.isNumber) ? nil : Int(digits)
    }

    /// An https URL; Reddit's markup carries nothing else for icons.
    static func secureURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, replacement) in [("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                      ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private static func firstCapture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
