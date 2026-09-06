import Foundation

/// Spoken summaries for VoiceOver.
///
/// A feed row or comment is a stack of small views, so VoiceOver would stop
/// on each and read bare numbers like "13.6K" and "3h". Rows are merged into
/// one element with this label, and vote/save/reply become custom actions
/// (see `PostRow` and `CommentRow`).
public enum AccessibilitySummary {
    public static func post(title: String, subreddit: String, author: String, score: Int,
                            comments: Int, created: Date, flair: String? = nil,
                            domain: String? = nil, nsfw: Bool = false, spoiler: Bool = false,
                            stickied: Bool = false, saved: Bool = false, vote: Bool? = nil,
                            now: Date = Date()) -> String {
        var parts: [String] = []
        if stickied { parts.append("Pinned") }
        if nsfw { parts.append("NSFW") }
        if spoiler { parts.append("Spoiler") }
        parts.append(title)
        if let flair, !flair.isEmpty { parts.append(flair) }
        if let domain, !domain.isEmpty { parts.append("link to \(domain)") }
        parts.append("in \(subreddit) by \(author)")
        parts.append(points(score))
        parts.append(count(comments, "comment"))
        parts.append(age(created, now: now))
        if let vote { parts.append(vote ? "Upvoted" : "Downvoted") }
        if saved { parts.append("Saved") }
        return parts.joined(separator: ", ")
    }

    public static func comment(author: String, body: String, score: Int, scoreHidden: Bool,
                               created: Date, isOP: Bool = false, collapsed: Bool = false,
                               hiddenReplies: Int = 0, vote: Bool? = nil, now: Date = Date()) -> String {
        var parts = [isOP ? "\(author), original poster" : author]
        if !scoreHidden { parts.append(points(score)) }
        parts.append(age(created, now: now))
        if let vote { parts.append(vote ? "Upvoted" : "Downvoted") }
        if collapsed {
            parts.append(hiddenReplies > 0 ? "Collapsed, \(count(hiddenReplies, "reply", plural: "replies")) hidden" : "Collapsed")
        } else {
            parts.append(spoken(markdown: body))
        }
        return parts.joined(separator: ", ")
    }

    public static func message(author: String, subject: String, body: String, created: Date,
                               unread: Bool, isCommentReply: Bool, now: Date = Date()) -> String {
        var parts: [String] = []
        if unread { parts.append("Unread") }
        parts.append(isCommentReply ? "Reply from \(author)" : "Message from \(author)")
        parts.append(subject)
        parts.append(age(created, now: now))
        parts.append(spoken(markdown: body))
        return parts.joined(separator: ", ")
    }

    /// Reddit markdown as it should be heard: link text without its
    /// URL, no emphasis/heading/quote/list markers, no `&amp;`-style
    /// entities, paragraphs as sentence breaks. VoiceOver otherwise
    /// reads "asterisk asterisk" and every URL character.
    public static func spoken(markdown: String) -> String {
        var t = markdown
        let rules: [(String, String)] = [
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),          // [text](url) -> text
            (#"https?://\S+"#, "link"),                      // bare URLs
            (#"(?m)^\s{0,3}(#{1,6}|>+|[-*+]|\d+\.)\s+"#, ""), // headings, quotes, bullets
            (#"(\*\*|__|~~|\*|\^|`)"#, ""),               // emphasis, strike, superscript, code
            (#"&gt;!|!&lt;|>!|!<"#, ""),                      // spoiler fences
            (#"\n{2,}"#, ". "),
            (#"\s+"#, " "),
        ]
        for (pattern, template) in rules {
            t = t.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        for (entity, plain) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: entity, with: plain)
        }
        return t.replacingOccurrences(of: #"\.\s*\.\s"#, with: ". ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func points(_ n: Int) -> String { count(n, "point") }

    static func count(_ n: Int, _ noun: String, plural: String? = nil) -> String {
        "\(n) \(abs(n) == 1 ? noun : (plural ?? noun + "s"))"
    }

    /// "3 hours ago" rather than the row's "3h".
    public static func age(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(count(s / 60, "minute")) ago"
        case ..<86_400: return "\(count(s / 3600, "hour")) ago"
        case ..<(86_400 * 30): return "\(count(s / 86_400, "day")) ago"
        case ..<(86_400 * 365): return "\(count(s / (86_400 * 30), "month")) ago"
        default: return "\(count(s / (86_400 * 365), "year")) ago"
        }
    }
}
