import Foundation

/// Reborn "Siri & Spotlight" (#1299): one post or subscribed community the
/// Spotlight/Siri index may hold. Core Spotlight is a projection of these
/// records, not the only copy of a post's searchable text.
public struct SiriContentRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case post, subreddit }
    public let id: String
    public let kind: Kind
    public let title: String
    public let subreddit: String
    public let author: String
    public let text: String
    public let createdAt: Date
    public var observedAt: Date
    /// Reddit path of the post or community, built from validated names
    /// only: `/r/<sub>/comments/<id>/` or `/r/<sub>/`.
    public let route: String
    public let fullName: String?
    /// Community display title (Reddit's t5 `title`, e.g. "Boutique Blu-ray").
    /// Siri transcribes spoken names as words, so this is the natural alias for
    /// a joined `display_name`. Optional so older catalogue snapshots decode.
    public var displayTitle: String? = nil
    /// Post-only listing metadata Siri can answer from ("how many comments").
    public var score: Int? = nil
    public var commentCount: Int? = nil
    /// Outbound link host for link posts (e.g. "theverge.com"); nil for self posts.
    public var linkDomain: String? = nil

    /// Public HTTPS equivalent of a validated route, for sharing.
    public static func webURL(forRoute route: String) -> URL {
        let path = route.hasPrefix("/r/") ? route : "/"
        return URL(string: "https://www.reddit.com" + path) ?? URL(string: "https://www.reddit.com/")!
    }

    public var webURL: URL { Self.webURL(forRoute: route) }

    /// Where opening this record goes inside the app.
    public var navigationTarget: RedditURLTarget {
        guard kind == .post, let name = fullName?.lowercased(), name.hasPrefix("t3_") else { return .subreddit(subreddit) }
        return .post(subreddit: subreddit, id: String(name.dropFirst(3)))
    }

    public static func identifier(_ json: [String: Any]) -> String? {
        if json["kind"] as? String == "t3", let name = json["name"] as? String,
           name.hasPrefix("t3_"), validName(String(name.dropFirst(3))) {
            return "reddit:post:\(name.lowercased())"
        }
        if json["kind"] as? String == "t5", let name = json["display_name"] as? String, validName(name) {
            return "reddit:subreddit:\(name.lowercased())"
        }
        return nil
    }

    /// Hostname only; self posts ("self.apple") and anything malformed are dropped.
    private static func linkDomain(_ value: String?) -> String? {
        guard let value = value?.lowercased(), !value.hasPrefix("self."), (1...253).contains(value.count),
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" })
        else { return nil }
        return value
    }

    public static func validName(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.unicodeScalars.allSatisfy {
            (65...90).contains($0.value) || (97...122).contains($0.value) ||
            (48...57).contains($0.value) || $0.value == 95
        }
    }

    /// A JSON number as a Double, whichever way the platform's
    /// JSONSerialization hands it back.
    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }

    /// Eligibility and normalisation of one Reddit listing row (a post or a
    /// community). Nil when it must not be indexed.
    public static func parse(_ json: [String: Any], now: Date) -> Self? {
        // Reddit uses different NSFW keys for post (t3) and community (t5)
        // records. Require the appropriate flag; missing is not equivalent to safe.
        let isPost = json["kind"] as? String == "t3"
        guard let id = identifier(json), json["subreddit_type"] as? String == "public",
              let over18 = json[isPost ? "over_18" : "over18"] as? Bool, !over18 else { return nil }
        let subreddit = json[isPost ? "subreddit" : "display_name"] as? String ?? ""
        guard validName(subreddit) else { return nil }
        let title = json["title"] as? String ?? ""
        let text = json[isPost ? "selftext" : "public_description"] as? String ?? ""
        let author = isPost ? json["author"] as? String ?? "" : ""
        if isPost {
            guard let hidden = json["hidden"] as? Bool, !hidden,
                  !title.isEmpty, author != "[deleted]", text != "[removed]", text != "[deleted]",
                  (json["removed_by_category"] as? String ?? "").isEmpty else { return nil }
        } else {
            // Search suggestions and arbitrary communities aren't subscriptions.
            guard json["user_is_subscriber"] as? Bool == true else { return nil }
        }
        // Derive the route from validated identifiers, not an untrusted
        // outbound link, so a link post can never route outside the app.
        let route: String
        if isPost {
            guard let name = json["name"] as? String else { return nil }
            route = "/r/\(subreddit)/comments/\(name.dropFirst(3))/"
        } else {
            route = "/r/\(subreddit)/"
        }
        let timestamp = number(json["created_utc"]) ?? now.timeIntervalSince1970
        guard timestamp.isFinite else { return nil }
        let communityTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(id: id, kind: isPost ? .post : .subreddit,
                    title: String((isPost ? title : "r/\(subreddit)").prefix(512)),
                    subreddit: subreddit, author: String(author.prefix(64)),
                    text: String(text.prefix(2048)), createdAt: Date(timeIntervalSince1970: timestamp),
                    observedAt: now, route: route, fullName: json["name"] as? String,
                    displayTitle: isPost || communityTitle.isEmpty ? nil : String(communityTitle.prefix(128)),
                    score: isPost ? number(json["score"]).flatMap { Int(exactly: $0) } : nil,
                    commentCount: isPost ? number(json["num_comments"]).flatMap { Int(exactly: $0) } : nil,
                    linkDomain: isPost ? linkDomain(json["domain"] as? String) : nil)
    }
}
