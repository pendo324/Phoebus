import Foundation

/// Generic Reddit "Thing" wrapper: every Reddit API object is returned as
/// {kind, data}.
public struct RedditThing<T: Decodable & Sendable>: Decodable, Sendable {
    public let kind: String
    public let data: T
}

/// A Reddit listing (paginated collection).
public struct RedditListing: Decodable, Sendable {
    public struct ListingData: Decodable, Sendable {
        public let after: String?
        public let before: String?
        public let dist: Int?
        public let children: [RedditThing<AnyListingChild>]

        enum CodingKeys: String, CodingKey {
            case after, before, dist, children
        }

        /// Tolerates a listing whose `children` key is absent.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            after = try container.decodeIfPresent(String.self, forKey: .after)
            before = try container.decodeIfPresent(String.self, forKey: .before)
            dist = try container.decodeIfPresent(Int.self, forKey: .dist)
            children = try container.decodeIfPresent([RedditThing<AnyListingChild>].self, forKey: .children) ?? []
        }

        init(empty: Bool) {
            after = nil
            before = nil
            dist = nil
            children = []
        }
    }
    public let kind: String
    public let data: ListingData

    enum CodingKeys: String, CodingKey {
        case kind, data
    }

    /// Decodes Reddit's empty-listing response, a bare `{}`, as an empty
    /// listing rather than throwing. `/subreddits/mine/subscriber.json` on the
    /// www (cookie) surface answers HTTP 200 with `{}` when it has no listing
    /// to give, and Reddit uses the same shape elsewhere on that surface.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "Listing"
        data = try container.decodeIfPresent(ListingData.self, forKey: .data) ?? ListingData(empty: true)
    }
}

/// Listings can mix kinds (t1 = comment, t3 = link, more). Decode
/// permissively and let call sites branch on `kind`.
public struct AnyListingChild: Decodable, Sendable {
    public let raw: [String: JSONValue]
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = try container.decode([String: JSONValue].self)
    }
}

/// Minimal dynamic JSON value for permissive decoding of heterogeneous
/// Reddit listing payloads. `Encodable` as well as `Decodable` because the
/// settings backup stores a whole `UserDefaults` domain as `JSONValue`
/// (`SettingsDomainSnapshot`), which has to be written back out as JSON.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Converts back to a plain Foundation type for JSONSerialization
    /// round-tripping — bridges permissive decoding to strongly-typed
    /// model decoding.
    public var plain: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .object(let o): return o.mapValues { $0.plain }
        case .array(let a): return a.map { $0.plain }
        case .null: return NSNull()
        }
    }
}

/// Removes duplicate things from one saved-items response (Reborn #1005).
///
/// Reddit can return the same thing twice in a single response, and the
/// saved array is replaced wholesale on pull-to-refresh, so the duplicate
/// would show as a repeated row.
///
///  - keep the FIRST occurrence, and the server's order
///  - items with NO stable identity are RETAINED, not dropped
public enum SavedItemsDeduplicator {
    /// Deduplicates by each item's identity: its fullname when present,
    /// otherwise `kind`+`id`.
    public static func deduplicate<T>(_ items: [T], identity: (T) -> String?) -> [T] {
        guard items.count > 1 else { return items }
        var seen = Set<String>()
        var result: [T] = []
        result.reserveCapacity(items.count)
        for item in items {
            guard let key = identity(item), !key.isEmpty else {
                // No stable identity: retained rather than dropped.
                result.append(item)
                continue
            }
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }
}

extension RedditListing {
    /// The children decoded as `T`, skipping any that don't decode (one odd
    /// post doesn't lose the page).
    public func decodedChildren<T: Decodable>(_ type: T.Type, kind: String? = nil) -> [T] {
        data.children.compactMap { child in
            if let kind, child.kind != kind { return nil }
            guard let bytes = try? JSONSerialization.data(withJSONObject: JSONValue.object(child.data.raw).plain) else { return nil }
            return try? JSONDecoder.reddit.decode(T.self, from: bytes)
        }
    }

    public func posts() -> [RedditPost] { decodedChildren(RedditPost.self, kind: "t3") }

    // Background variants for screens, which run on the main actor:
    // decoding a full page there would block scrolling.

    public static func decodedInBackground(from data: Data) async throws -> RedditListing {
        try await Task.detached(priority: .userInitiated) {
            try JSONDecoder.reddit.decode(RedditListing.self, from: data)
        }.value
    }

    public func childrenInBackground<T: Decodable & Sendable>(_ type: T.Type, kind: String? = nil) async -> [T] {
        await Task.detached(priority: .userInitiated) { self.decodedChildren(type, kind: kind) }.value
    }

    public func postsInBackground() async -> [RedditPost] {
        await childrenInBackground(RedditPost.self, kind: "t3")
    }

    public func profileItemsInBackground() async -> [ProfileItem] {
        await Task.detached(priority: .userInitiated) { self.profileItems() }.value
    }
}

/// One row of a user listing (Overview, Saved and the rest): a post or
/// a comment, kept in Reddit's order.
public enum ProfileItem: Identifiable, Sendable {
    case post(RedditPost)
    case comment(RedditComment)

    public var id: String {
        switch self {
        case .post(let post): return post.name
        case .comment(let comment): return comment.name
        }
    }
}

extension RedditListing {
    public func profileItems() -> [ProfileItem] {
        data.children.compactMap { child -> ProfileItem? in
            guard let bytes = try? JSONSerialization.data(withJSONObject: JSONValue.object(child.data.raw).plain) else { return nil }
            switch child.kind {
            case "t3": return (try? JSONDecoder.reddit.decode(RedditPost.self, from: bytes)).map(ProfileItem.post)
            case "t1": return (try? JSONDecoder.reddit.decode(RedditComment.self, from: bytes)).map(ProfileItem.comment)
            default: return nil
            }
        }
    }

    /// Items not already in `existing`, for appending a next page (Reddit
    /// can repeat an item across a page boundary, or within one: #1005).
    public static func appending(_ page: [ProfileItem], to existing: [ProfileItem]) -> [ProfileItem] {
        var seen = Set(existing.map(\.id))
        var result = existing
        for item in page where seen.insert(item.id).inserted { result.append(item) }
        return result
    }
}
