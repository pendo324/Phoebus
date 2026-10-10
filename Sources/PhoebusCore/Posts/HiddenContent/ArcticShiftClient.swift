import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Archive lookup for Reborn's "Deleted Comments" feature: a public,
/// unauthenticated community archive of Reddit comments
/// (`https://arctic-shift.photon-reddit.com/api/comments/tree`), used to
/// recover the body text of comments Reddit's API serves as
/// `[deleted]`/`[removed]`.
///
/// Request tuning (`start_depth=50`, `start_breadth=500`, `limit=5000`,
/// `md2html=true`) follows Reborn. Only "fetch a link's whole comment tree
/// and index it by fullname" is implemented; the archive is called directly
/// from `CommentTreeStore`, with no request interception, cooldown or
/// in-flight coalescing.
public enum ArcticShiftClient {
    public enum ClientError: Error, Sendable {
        case invalidResponse
        case appThrottled
    }

    static let baseURL = "https://arctic-shift.photon-reddit.com"

    /// Fetches every archived comment for `linkFullname` (e.g.
    /// `"t3_abc123"`), keyed by comment fullname (`"t1_xyz789"`).
    /// Returns an empty dictionary (not an error) when the archive has
    /// nothing for this link; a transient failure is thrown.
    public static func fetchArchivedComments(linkFullname: String, session: URLSession = .shared) async throws -> [String: ArchivedComment] {
        guard !linkFullname.isEmpty else { return [:] }
        var components = URLComponents(string: baseURL + "/api/comments/tree")!
        components.queryItems = [
            URLQueryItem(name: "link_id", value: linkFullname),
            URLQueryItem(name: "limit", value: "5000"),
            // Arctic folds subtrees beyond these thresholds into
            // bodyless "kind: more" stubs, dropping deep/wide threads'
            // tail comments entirely at the defaults - raised here to
            // match.
            URLQueryItem(name: "start_depth", value: "50"),
            URLQueryItem(name: "start_breadth", value: "500"),
            // Have Arctic render markdown -> HTML server-side, as Reborn does; not
            // consumed yet by the plain-text recovered body.
            URLQueryItem(name: "md2html", value: "true"),
        ]
        guard let url = components.url else { return [:] }
        let children = try await dataRows(from: url, session: session)

        var comments: [String: ArchivedComment] = [:]
        flatten(children: children, into: &comments)
        return comments
    }

    /// Recovers specific comments by id (`api/comments/ids`), keyed by
    /// fullname. Takes bare ids or `t1_` fullnames; a comment the archive
    /// has no usable copy of is simply absent. Phoebus-only (not in Reborn).
    public static func fetchArchivedComments(ids: [String], session: URLSession = .shared) async throws -> [String: ArchivedComment] {
        let bare = ids.map { $0.hasPrefix("t1_") ? String($0.dropFirst(3)) : $0 }.filter { !$0.isEmpty }
        var comments: [String: ArchivedComment] = [:]
        // The limit is the URL's length rather than an item count.
        for start in stride(from: 0, to: bare.count, by: idsPerRequest) {
            let chunk = bare[start..<min(start + idsPerRequest, bare.count)]
            var components = URLComponents(string: baseURL + "/api/comments/ids")!
            components.queryItems = [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))]
            guard let url = components.url else { continue }
            let rows = try await dataRows(from: url, session: session)
            comments.merge(parseCommentRows(rows)) { current, _ in current }
        }
        return comments
    }

    /// One comment by id or fullname, or nil when the archive has none.
    public static func fetchArchivedComment(id: String, session: URLSession = .shared) async throws -> ArchivedComment? {
        let fullname = id.hasPrefix("t1_") ? id : "t1_\(id)"
        return try await fetchArchivedComments(ids: [fullname], session: session)[fullname]
    }

    /// The archived copy of a removed post (`api/posts/ids`), or nil when
    /// the archive has nothing usable. Answers (found or not) are cached
    /// for the session, so reopening a post costs no request.
    public static func fetchArchivedPost(id: String, session: URLSession = .shared) async throws -> ArchivedPost? {
        let bare = id.hasPrefix("t3_") ? String(id.dropFirst(3)) : id
        guard !bare.isEmpty else { return nil }
        if let hit = ArchivedPostCache.shared.value(for: bare) { return hit.post }
        var components = URLComponents(string: baseURL + "/api/posts/ids")!
        components.queryItems = [URLQueryItem(name: "ids", value: bare)]
        guard let url = components.url else { return nil }
        let rows = try await dataRows(from: url, session: session)
        let post = rows.lazy.compactMap { ArchivedPost(archive: $0, postID: bare) }.first
        ArchivedPostCache.shared.store(post, for: bare)
        return post
    }

    static let idsPerRequest = 250

    /// Parses an `api/comments/ids` response body into recovered comments
    /// keyed by fullname. Throws on an error envelope rather than reading
    /// it as "nothing archived".
    public static func parseComments(_ data: Data) throws -> [String: ArchivedComment] {
        parseCommentRows(try dataRows(from: data))
    }

    /// Parses an `api/posts/ids` response body; nil when the archive has
    /// no usable copy of `postID`.
    public static func parsePost(_ data: Data, postID: String) throws -> ArchivedPost? {
        try dataRows(from: data).lazy.compactMap { ArchivedPost(archive: $0, postID: postID) }.first
    }

    private static func dataRows(from url: URL, session: URLSession) async throws -> [[String: Any]] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClientError.invalidResponse
        }
        return try dataRows(from: data)
    }

    private static func dataRows(from data: Data) throws -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.invalidResponse
        }
        // Arctic's app-level-throttle detection: a 200 response can
        // still carry `{"data":null,"error":"..."}` when Arctic's own
        // rate limit kicks in - that must not be cached/treated as
        // "genuinely empty".
        if let error = root["error"], !(error is NSNull) {
            throw ClientError.appThrottled
        }
        guard let rows = root["data"] as? [[String: Any]] else {
            throw ClientError.invalidResponse
        }
        return rows
    }

    private static func parseCommentRows(_ rows: [[String: Any]]) -> [String: ArchivedComment] {
        var comments: [String: ArchivedComment] = [:]
        for row in rows {
            if let comment = archivedComment(from: row) { comments[comment.fullname] = comment }
        }
        return comments
    }

    /// Recurses into each comment's own nested `replies.data.children`,
    /// same shape as a normal Reddit comments-listing response.
    private static func flatten(children: [[String: Any]], into comments: inout [String: ArchivedComment]) {
        for child in children {
            guard let kind = child["kind"] as? String, kind == "t1",
                  let data = child["data"] as? [String: Any] else { continue }

            if let comment = archivedComment(from: data) {
                comments[comment.fullname] = comment
            }

            if let replies = data["replies"] as? [String: Any],
               let repliesData = replies["data"] as? [String: Any],
               let replyChildren = repliesData["children"] as? [[String: Any]] {
                flatten(children: replyChildren, into: &comments)
            }
        }
    }

    /// Nil for a record whose body is itself a placeholder: the archive
    /// only saw the comment after Reddit scrubbed it.
    static func archivedComment(from data: [String: Any]) -> ArchivedComment? {
        guard let fullname = fullname(from: data), let body = data["body"] as? String, !body.isEmpty,
              !DeletedCommentsClassifier.bodyLooksDeletedOrRemoved(body) else { return nil }
        let author = (data["author"] as? String).flatMap { RemovedPostClassifier.isPlaceholder($0) ? nil : $0 }
        let score = (data["score"] as? NSNumber)?.intValue
        return ArchivedComment(fullname: fullname, author: author, body: body, score: score, reason: reason(for: data))
    }

    /// Arctic's comment objects carry a `name` field (`"t1_xyz"`), same as
    /// Reddit's API.
    private static func fullname(from data: [String: Any]) -> String? {
        if let name = data["name"] as? String, !name.isEmpty { return name }
        if let id = data["id"] as? String, !id.isEmpty { return "t1_\(id)" }
        return nil
    }

    /// Arctic tags some removals with `_meta.removal_type`; anything
    /// mentioning "delete" is user-initiated, everything else defaults
    /// to moderator-removed.
    private static func reason(for data: [String: Any]) -> DeletedCommentReason {
        if let meta = data["_meta"] as? [String: Any],
           let removalType = (meta["removal_type"] as? String)?.lowercased(),
           removalType.contains("delete") {
            return .userDeleted
        }
        return .moderatorRemoved
    }
}
