import Foundation

/// Reborn "Siri & Spotlight" (#1299): a Reddit comment the app has already
/// loaded for a post the person opened. Never persisted, never
/// Spotlight-indexed: Apple treats per-parent child content like this as
/// context reached through its parent and onscreen annotations.
public struct SiriCommentRecord: Sendable, Equatable, Identifiable {
    public let id: String          // reddit:comment:t1_<id>
    public let postID: String      // reddit:post:t3_<id>
    public let subreddit: String
    public let author: String
    public let body: String
    public let score: Int?
    public let depth: Int
    public let isOP: Bool
    public let createdAt: Date
    public let order: Int          // The thread's order when captured

    public static func identifier(_ fullName: String?) -> String? {
        guard let name = fullName?.lowercased(), name.hasPrefix("t1_"),
              SiriContentRecord.validName(String(name.dropFirst(3))) else { return nil }
        return "reddit:comment:\(name)"
    }

    /// `json` mirrors Reddit's comment keys (`SiriContentSanitizer` builds it).
    public static func parse(_ json: [String: Any], order: Int) -> Self? {
        guard let id = identifier(json["name"] as? String),
              var link = (json["link_id"] as? String)?.lowercased() else { return nil }
        if !link.hasPrefix("t3_") { link = "t3_" + link }
        guard let postID = SiriContentRecord.identifier(["kind": "t3", "name": link]),
              let subreddit = json["subreddit"] as? String, SiriContentRecord.validName(subreddit) else { return nil }
        let author = (json["author"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Same exclusions as the rest of the integration: nothing deleted/removed.
        guard !author.isEmpty, author != "[deleted]", !body.isEmpty,
              body != "[deleted]", body != "[removed]" else { return nil }
        let timestamp = SiriContentRecord.number(json["created_utc"]) ?? 0
        return Self(id: id, postID: postID, subreddit: subreddit, author: String(author.prefix(64)),
                    body: String(body.prefix(2000)),
                    score: SiriContentRecord.number(json["score"]).flatMap { Int(exactly: $0) },
                    depth: max(0, SiriContentRecord.number(json["depth"]).flatMap { Int(exactly: $0) } ?? 0),
                    isOP: json["is_submitter"] as? Bool ?? false,
                    createdAt: Date(timeIntervalSince1970: timestamp.isFinite ? timestamp : 0), order: order)
    }

    /// The comment in its thread (never an untrusted link).
    public var route: String {
        "/r/\(subreddit)/comments/\(postID.dropFirst("reddit:post:t3_".count))/_/\(id.dropFirst("reddit:comment:t1_".count))/"
    }

    public var webURL: URL { SiriContentRecord.webURL(forRoute: route) }

    public var navigationTarget: RedditURLTarget {
        .comment(subreddit: subreddit, postID: String(postID.dropFirst("reddit:post:t3_".count)),
                 commentID: String(id.dropFirst("reddit:comment:t1_".count)))
    }
}

/// In-memory, account-scoped context for what the person is looking at right
/// now: posts they opened (even ones no listing captured, e.g. from a link) and
/// the comments loaded for them. This is what lets onscreen annotations
/// resolve for any visible post or comment without widening what gets
/// persisted or indexed. Access it from the content-service actor (or a test).
public final class SiriSessionContext {
    public let postLimit: Int
    public let threadLimit: Int
    public let commentsPerThread: Int
    public private(set) var account: String?
    private var posts: [String: SiriContentRecord] = [:]
    private var postOrder: [String] = []          // most recent last
    private var threads: [String: [String: SiriCommentRecord]] = [:]
    private var threadOrder: [String] = []        // most recent last

    public init(postLimit: Int = 50, threadLimit: Int = 5, commentsPerThread: Int = 500) {
        self.postLimit = postLimit
        self.threadLimit = threadLimit
        self.commentsPerThread = commentsPerThread
    }

    /// Any scope change (account switch, logout, opt-out) drops everything.
    public func configure(account: String?) {
        guard account != self.account else { return }
        self.account = account
        posts.removeAll(); postOrder.removeAll()
        threads.removeAll(); threadOrder.removeAll()
    }

    public func observe(post record: SiriContentRecord, account: String) {
        guard account == self.account, record.kind == .post else { return }
        posts[record.id] = record
        postOrder.removeAll { $0 == record.id }
        postOrder.append(record.id)
        while postOrder.count > postLimit { posts.removeValue(forKey: postOrder.removeFirst()) }
    }

    public func observe(comments: [SiriCommentRecord], account: String) {
        guard account == self.account else { return }
        for comment in comments {
            // Most recently loaded thread last; evict the oldest beyond the cap.
            threadOrder.removeAll { $0 == comment.postID }
            threadOrder.append(comment.postID)
            while threadOrder.count > threadLimit { threads.removeValue(forKey: threadOrder.removeFirst()) }
            var thread = threads[comment.postID] ?? [:]
            // Keep the first-seen thread position; refresh text/score in place.
            let order = thread[comment.id]?.order ?? comment.order
            guard thread[comment.id] != nil || thread.count < commentsPerThread else { continue }
            thread[comment.id] = SiriCommentRecord(id: comment.id, postID: comment.postID, subreddit: comment.subreddit,
                                                   author: comment.author, body: comment.body, score: comment.score,
                                                   depth: comment.depth, isOP: comment.isOP,
                                                   createdAt: comment.createdAt, order: order)
            threads[comment.postID] = thread
        }
    }

    public func post(_ id: String) -> SiriContentRecord? { posts[id] }

    public var postIDs: [String] { Array(posts.keys) }
    public var commentIDs: [String] { threads.values.flatMap { $0.keys } }

    public func comments(_ ids: [String]) -> [SiriCommentRecord] {
        ids.compactMap { id in threads.values.lazy.compactMap { $0[id] }.first }
    }

    /// The best `limit` comments of one post: OP replies and top-level
    /// comments first, with a mild bias toward the order the thread showed
    /// them in.
    public func comments(forPost postID: String, limit: Int) -> [SiriCommentRecord] {
        guard let thread = threads[postID], limit > 0 else { return [] }
        func rank(_ c: SiriCommentRecord) -> Int {
            min(max(c.score ?? 0, -50), 5000) + (c.isOP ? 1400 : 0) - min(c.depth, 8) * 70 - min(c.order, 100) * 3
        }
        let ranked = thread.values.sorted { rank($0) == rank($1) ? $0.order < $1.order : rank($0) > rank($1) }
        return Array(ranked.prefix(limit))
    }

    public func search(_ query: String, limit: Int) -> [SiriCommentRecord] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let matches = threads.values.flatMap(\.values).filter { c in
            let text = "\(c.body) \(c.author)".lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
        return Array(matches.sorted { ($0.score ?? 0) > ($1.score ?? 0) }.prefix(limit))
    }

    /// Hide/delete: drop the post and any comment thread belonging to it.
    public func suppress(_ ids: [String]) {
        for id in ids {
            posts.removeValue(forKey: id)
            postOrder.removeAll { $0 == id }
            threads.removeValue(forKey: id)
            threadOrder.removeAll { $0 == id }
        }
    }
}
