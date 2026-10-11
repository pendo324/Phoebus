import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Second archive for deleted comments: Reveddit's thread lookup
/// (`https://api.reveddit.com/short/thread-comments/`), asked only when
/// Arctic Shift has no copy of a deleted comment in the thread.
/// Phoebus-only fallback (not in Apollo or Reborn).
public enum RevedditClient {
    public enum ClientError: Error, Sendable {
        case invalidResponse
    }

    /// Recovered comments for a thread, keyed by fullname. `linkID` is the
    /// bare post id; the comment count and creation time let Reveddit size
    /// its lookup, as its own site sends them.
    public static func fetchThreadComments(linkID: String, numComments: Int? = nil, postCreatedUTC: Date? = nil,
                                           session: URLSession = .shared) async throws -> [String: ArchivedComment] {
        let bare = linkID.hasPrefix("t3_") ? String(linkID.dropFirst(3)) : linkID
        guard !bare.isEmpty else { return [:] }
        var components = URLComponents(string: "https://api.reveddit.com/short/thread-comments/")!
        var items = [URLQueryItem(name: "link_id", value: bare)]
        if let numComments, numComments > 0 { items.append(URLQueryItem(name: "num_comments", value: String(numComments))) }
        if let postCreatedUTC { items.append(URLQueryItem(name: "post_created_utc", value: String(Int(postCreatedUTC.timeIntervalSince1970)))) }
        components.queryItems = items
        guard let url = components.url else { return [:] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        // Reveddit only answers requests that come from its own site.
        request.setValue("https://www.reveddit.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.reveddit.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClientError.invalidResponse
        }
        return try parseThreadComments(data)
    }

    /// The response is an object keyed by bare comment id, each value a
    /// comment record (`id`, `body`, `author`, `score`).
    public static func parseThreadComments(_ data: Data) throws -> [String: ArchivedComment] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.invalidResponse
        }
        var comments: [String: ArchivedComment] = [:]
        for (key, value) in root {
            guard var record = value as? [String: Any] else { continue }
            if record["id"] == nil { record["id"] = key }
            if let comment = ArcticShiftClient.archivedComment(from: record) {
                comments[comment.fullname] = comment
            }
        }
        return comments
    }
}

/// How the two archives combine for Deleted Comments: Arctic Shift first,
/// Reveddit only for the deleted comments Arctic Shift lacks.
public enum DeletedCommentsFallback {
    /// Fullnames of `deleted` comments with no copy in `archive`, in order.
    public static func missing(deleted: [String], archive: [String: ArchivedComment]) -> [String] {
        deleted.filter { archive[$0] == nil }
    }

    /// `primary` plus whatever `fallback` adds; `primary` wins on overlap.
    public static func merged(primary: [String: ArchivedComment], fallback: [String: ArchivedComment]) -> [String: ArchivedComment] {
        primary.merging(fallback) { current, _ in current }
    }
}
