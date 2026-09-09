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

    /// Fetches every archived comment for `linkFullname` (e.g.
    /// `"t3_abc123"`), keyed by comment fullname (`"t1_xyz789"`).
    /// Returns an empty dictionary (not an error) when the archive has
    /// nothing for this link; a transient failure is thrown.
    public static func fetchArchivedComments(linkFullname: String, session: URLSession = .shared) async throws -> [String: ArchivedComment] {
        guard !linkFullname.isEmpty else { return [:] }
        var components = URLComponents(string: "https://arctic-shift.photon-reddit.com/api/comments/tree")!
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
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClientError.invalidResponse
        }
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
        guard let children = root["data"] as? [[String: Any]] else {
            throw ClientError.invalidResponse
        }

        var comments: [String: ArchivedComment] = [:]
        flatten(children: children, into: &comments)
        return comments
    }

    /// Recurses into each comment's own nested `replies.data.children`,
    /// same shape as a normal Reddit comments-listing response.
    private static func flatten(children: [[String: Any]], into comments: inout [String: ArchivedComment]) {
        for child in children {
            guard let kind = child["kind"] as? String, kind == "t1",
                  let data = child["data"] as? [String: Any] else { continue }

            if let fullname = fullname(from: data), let body = data["body"] as? String, !body.isEmpty,
               !DeletedCommentsClassifier.bodyLooksDeletedOrRemoved(body) {
                let author = data["author"] as? String
                let score = (data["score"] as? NSNumber)?.intValue
                comments[fullname] = ArchivedComment(fullname: fullname, author: author, body: body, score: score, reason: reason(for: data))
            }

            if let replies = data["replies"] as? [String: Any],
               let repliesData = replies["data"] as? [String: Any],
               let replyChildren = repliesData["children"] as? [[String: Any]] {
                flatten(children: replyChildren, into: &comments)
            }
        }
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
