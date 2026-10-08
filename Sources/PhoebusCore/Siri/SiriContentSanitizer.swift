import Foundation

/// Reborn "Siri & Spotlight" (#1299): what leaves a Reddit response for the
/// index. Only an explicit allowlist of public content keys is forwarded,
/// never the original response, credentials, private messages or arbitrary
/// server dictionaries.
public enum SiriContentSanitizer {
    static let listingKeys = [
        "name", "title", "subreddit", "author", "selftext", "permalink", "created_utc", "over_18", "over18",
        "hidden", "subreddit_type", "removed_by_category", "display_name", "public_description",
        "user_is_subscriber", "score", "num_comments", "domain",
    ]
    static let commentKeys = [
        "name", "link_id", "subreddit", "author", "body", "score", "depth", "created_utc", "is_submitter",
    ]
    /// A burst of loaded comments reaches the service in chunks of this size.
    static let commentChunk = 500
    /// At most this many comments of one response are forwarded.
    static let commentsPerResponse = 2000

    /// A listing's t3 and t5 rows, ready for `SiriContentCatalog.ingest`.
    /// Nil for an oversized listing.
    public static func listingPayload(_ children: [RedditThing<AnyListingChild>]) -> Data? {
        guard children.count <= SiriContentLimits.rowsPerPayload else { return nil }
        let rows = children.compactMap { child -> [String: Any]? in
            guard child.kind == "t3" || child.kind == "t5" else { return nil }
            return row(child.data.raw, kind: child.kind, keys: listingKeys)
        }
        return payload(rows)
    }

    /// The catalogue ids of the communities in a listing.
    public static func communityIDs(_ children: [RedditThing<AnyListingChild>]) -> Set<String> {
        Set(children.compactMap { child in
            guard child.kind == "t5", case .string(let name)? = child.data.raw["display_name"] else { return nil }
            return SiriContentRecord.identifier(["kind": "t5", "display_name": name])
        })
    }

    /// The post and comments a `/comments/<id>` response carries
    /// (`[postListing, commentListing]`), as one post row and chunks of
    /// comment rows.
    public static func commentsResponse(_ data: Data) -> (post: Data?, comments: [Data]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any], root.count == 2 else { return (nil, []) }
        func children(_ listing: Any) -> [[String: Any]] {
            ((listing as? [String: Any])?["data"] as? [String: Any])?["children"] as? [[String: Any]] ?? []
        }
        let post = children(root[0]).first { $0["kind"] as? String == "t3" }
            .flatMap { ($0["data"] as? [String: Any]).flatMap { row($0, kind: "t3", keys: listingKeys) } }
            .flatMap { payload([$0]) }
        return (post, commentChunks(children(root[1])))
    }

    /// Comment rows from `/api/morechildren` things.
    public static func moreChildren(_ things: [JSONValue]) -> [Data] {
        commentChunks(things.compactMap { $0.plain as? [String: Any] })
    }

    private static func commentChunks(_ children: [[String: Any]]) -> [Data] {
        var rows: [[String: Any]] = []
        func walk(_ children: [[String: Any]]) {
            for child in children where rows.count < commentsPerResponse {
                guard child["kind"] as? String == "t1", let data = child["data"] as? [String: Any] else { continue }
                if let comment = row(data, kind: nil, keys: commentKeys) {
                    rows.append(comment.merging(["order": rows.count]) { $1 })
                }
                // Replies are a nested listing, or "" when there are none.
                if let replies = (data["replies"] as? [String: Any])?["data"] as? [String: Any],
                   let nested = replies["children"] as? [[String: Any]] {
                    walk(nested)
                }
            }
        }
        walk(children)
        return stride(from: 0, to: rows.count, by: commentChunk).compactMap {
            payload(Array(rows[$0..<min($0 + commentChunk, rows.count)]))
        }
    }

    /// Booleans are told apart by key: a JSON `1` and `true` look alike once
    /// bridged to NSNumber.
    private static let boolKeys: Set<String> = ["over_18", "over18", "hidden", "user_is_subscriber", "is_submitter"]

    private static func row(_ source: [String: Any], kind: String?, keys: [String]) -> [String: Any]? {
        var record: [String: Any] = kind.map { ["kind": $0] } ?? [:]
        for key in keys {
            if boolKeys.contains(key) {
                if let value = source[key] as? Bool { record[key] = value }
            } else if let value = source[key] as? String {
                record[key] = String(value.prefix(key == "selftext" || key == "body" ? 2048 : 512))
            } else if let value = SiriContentRecord.number(source[key]) {
                record[key] = value
            }
        }
        return record
    }

    private static func row(_ source: [String: JSONValue], kind: String, keys: [String]) -> [String: Any]? {
        row(source.mapValues(\.plain), kind: kind, keys: keys)
    }

    private static func payload(_ rows: [[String: Any]]) -> Data? {
        guard let data = try? JSONSerialization.data(withJSONObject: rows),
              data.count <= SiriContentLimits.payloadBytes else { return nil }
        return data
    }
}
