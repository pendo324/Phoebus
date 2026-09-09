import Foundation

/// Reborn's "Prefer Native Images" for comment photos.
///
/// With a Comment Link Host set AND Prefer Native Images on, a photo
/// attached to a comment goes through Reddit's own upload when the
/// subreddit is KNOWN to allow image comments, and through the link host
/// otherwise ("disallowed" and "unknown" both use the link, since a plain
/// link always posts while a native image in a gated subreddit is
/// rejected at submit time).
///
/// A native upload lands as a bare `https://i.redd.it/<asset>.<ext>` in
/// the text. On submit the comment is sent with a `richtext_json`
/// document holding `{"e":"img","id":<asset>}` blocks between text
/// paragraphs, and the markdown body keeps `![image](url)` so clients
/// that ignore RTJSON still show it.
public enum NativeCommentImages {
    /// "static" or "animated" means uploaded images are allowed. nil
    /// when the field is absent (unknown).
    public static func allowsImageComments(aboutData: [String: Any]) -> Bool? {
        guard let kinds = aboutData["allowed_media_in_comments"] as? [Any] else { return nil }
        return kinds.contains { ($0 as? String).map { ["static", "animated"].contains($0.lowercased()) } ?? false }
    }

    /// The i.redd.it URL for a native asset.
    public static func mediaURL(assetID: String, fileExtension: String) -> String {
        "https://i.redd.it/\(assetID).\(fileExtension.isEmpty ? "jpeg" : fileExtension)"
    }

    private static let urlPattern = try! NSRegularExpression(pattern: #"https://i\.redd\.it/([A-Za-z0-9]+)\.[A-Za-z0-9]+"#)

    /// `assetIDs` is the set this session uploaded natively; any other
    /// i.redd.it link is left as plain text. nil when there is nothing
    /// native.
    public static func richTextJSON(for text: String, assetIDs: Set<String>) -> String? {
        let ns = text as NSString
        let matches = urlPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .filter { assetIDs.contains(ns.substring(with: $0.range(at: 1))) }
        guard !matches.isEmpty else { return nil }
        var blocks: [[String: Any]] = []
        var cursor = 0
        func paragraph(_ range: NSRange) {
            let trimmed = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { blocks.append(["e": "par", "c": [["e": "text", "t": trimmed]]]) }
        }
        for match in matches {
            if match.range.location > cursor { paragraph(NSRange(location: cursor, length: match.range.location - cursor)) }
            blocks.append(["e": "img", "id": ns.substring(with: match.range(at: 1)), "c": ""])
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length { paragraph(NSRange(location: cursor, length: ns.length - cursor)) }
        guard let data = try? JSONSerialization.data(withJSONObject: ["document": blocks], options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The markdown fallback body: bare native URLs become `![image](url)`.
    public static func markdownBody(for text: String, assetIDs: Set<String>) -> String {
        let ns = text as NSString
        var out = text
        for match in urlPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard assetIDs.contains(ns.substring(with: match.range(at: 1))) else { continue }
            if match.range.location >= 2, ns.substring(with: NSRange(location: match.range.location - 2, length: 2)) == "](" { continue }
            let url = ns.substring(with: match.range)
            let alt = url.lowercased().hasSuffix(".gif") ? "gif" : "image"
            out = (out as NSString).replacingCharacters(in: match.range, with: "![\(alt)](\(url))")
        }
        return out
    }
}
