import Foundation

/// What an answer's source row shows for a post, comment or community, read
/// from one `/api/info` batch.
public struct RedditAnswerSourceInfo: Equatable, Sendable {
    public enum Kind: Sendable { case post, comment, subreddit }

    /// `t3_…`, `t1_…` or `t5_…`.
    public var id: String
    public var kind: Kind
    /// A post's title, a comment's opening text, a community's "r/name".
    public var title: String
    public var subreddit: String?
    public var author: String?
    public var score: Int?
    public var commentCount: Int?
    /// A comment's post id, without `t3_`.
    public var postID: String?
    public var iconURL: URL?
    public var subscribers: Int?

    /// Where tapping the row goes.
    public var target: RedditURLTarget {
        switch kind {
        case .post:
            return .post(subreddit: subreddit ?? "", id: String(id.dropFirst(3)))
        case .comment:
            guard let postID else { return .unknown(URL(string: "https://www.reddit.com/")!) }
            return .comment(subreddit: subreddit ?? "", postID: postID, commentID: String(id.dropFirst(3)))
        case .subreddit:
            return .subreddit(subreddit ?? String(title.drop(while: { $0 == "r" || $0 == "/" })))
        }
    }

    /// Reads a listing of `t3`, `t1` and `t5` things.
    public static func parse(_ data: Data) -> [String: RedditAnswerSourceInfo] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let listing = root["data"] as? [String: Any],
              let children = listing["children"] as? [[String: Any]] else { return [:] }
        var result: [String: RedditAnswerSourceInfo] = [:]
        for child in children {
            guard let kind = child["kind"] as? String, let item = child["data"] as? [String: Any],
                  let id = item["name"] as? String else { continue }
            let count: (String) -> Int? = { (item[$0] as? NSNumber)?.intValue }
            switch kind {
            case "t3":
                result[id] = RedditAnswerSourceInfo(
                    id: id, kind: .post, title: decoded(item["title"] as? String ?? ""),
                    subreddit: item["subreddit"] as? String, author: item["author"] as? String,
                    score: count("score"), commentCount: count("num_comments"))
            case "t1":
                let body = decoded(item["body"] as? String ?? "")
                let post = (item["link_id"] as? String).map { $0.hasPrefix("t3_") ? String($0.dropFirst(3)) : $0 }
                result[id] = RedditAnswerSourceInfo(
                    id: id, kind: .comment, title: excerpt(body), subreddit: item["subreddit"] as? String,
                    author: item["author"] as? String, score: count("score"), postID: post)
            case "t5":
                let name = item["display_name"] as? String ?? ""
                let icon = (item["community_icon"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (item["icon_img"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                result[id] = RedditAnswerSourceInfo(
                    id: id, kind: .subreddit, title: "r/\(name)", subreddit: name,
                    iconURL: icon.flatMap { URL(string: decoded($0)) }, subscribers: count("subscribers"))
            default:
                continue
            }
        }
        return result
    }

    private static func decoded(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func excerpt(_ body: String) -> String {
        let flat = body.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > 140 ? String(flat.prefix(140)) + "\u{2026}" : flat
    }

    public init(id: String, kind: Kind, title: String, subreddit: String? = nil, author: String? = nil,
                score: Int? = nil, commentCount: Int? = nil, postID: String? = nil,
                iconURL: URL? = nil, subscribers: Int? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subreddit = subreddit
        self.author = author
        self.score = score
        self.commentCount = commentCount
        self.postID = postID
        self.iconURL = iconURL
        self.subscribers = subscribers
    }
}
