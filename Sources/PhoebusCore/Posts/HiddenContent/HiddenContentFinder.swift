import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reborn's "Hidden & Deleted" profile archive feature (#1137, building
/// on #633 "Hidden Content Recovery").
///
/// Diffs a user's Arctic Shift archive against their LIVE `/submitted` or
/// `/comments` listing. Anything the archive has that the live listing no
/// longer shows is a candidate, which `/api/info` then classifies as Hidden
/// (still intact live, just missing from the listing), Removed (a
/// moderator, AutoMod or admin took it down) or Deleted (the author did).
///
/// The network orchestration is split from the pure parsing and
/// classification so the latter can be exercised by the smoke test without
/// a network.
public enum HiddenContentFinder {
    // Upstream constants.
    static let pageSize = 100
    static let liveListingCap = 1000   // 10 pages
    static let arcticCap = 500         // 5 pages
    static let infoBatchSize = 100     // Reddit /api/info limit
    static let requestTimeout: TimeInterval = 15
    static let cacheTTL: TimeInterval = 3600

    public enum Kind: Int, Sendable, CaseIterable {
        case post = 0
        case comment

        var liveListing: String { self == .post ? "submitted" : "comments" }
        var fullNamePrefix: String { self == .post ? "t3_" : "t1_" }
        var arcticSearchPath: String { self == .post ? "/api/posts/search" : "/api/comments/search" }
        var bodyKey: String { self == .post ? "selftext" : "body" }
    }

    /// The reason category for a hidden/deleted item.
    public enum Reason: Int, Sendable {
        case hidden = 0, deleted, removed

        /// Pill label text.
        public var pillText: String {
            switch self {
            case .deleted: return "DELETED"
            case .removed: return "REMOVED"
            case .hidden: return "HIDDEN"
            }
        }
    }

    public struct Item: Identifiable, Sendable, Hashable {
        public var fullName: String
        public var kind: Kind
        public var reason: Reason
        /// "Moderator" / "AutoMod" / "Reddit Admins" for Removed,
        /// "Author" for Deleted, nil for Hidden or unknown.
        public var removalDetail: String?
        public var author: String?
        public var score: Int?
        public var title: String?
        public var body: String?
        public var parentPostTitle: String?
        public var subreddit: String?
        public var permalink: String?
        public var createdDate: Date?
        public var mediaURLs: [URL]
        public var previewURL: URL?
        /// Width / height of the first media item; 0 when unknown.
        public var previewAspectRatio: Double
        public var id: String { fullName }
    }

    public enum FetchError: LocalizedError, Sendable {
        case noUsername
        case liveListingFailed
        case archiveFailed

        /// Upstream's verbatim messages.
        public var errorDescription: String? {
            switch self {
            case .noUsername: return "No username to look up."
            case .liveListingFailed: return "Couldn't verify this account's current posts/comments (network or session error). Try again."
            case .archiveFailed: return "Couldn't search the archive for older posts/comments (network error). Try again."
            }
        }
    }

    // MARK: - Pure helpers

    /// Removal-category mapping. Unknown categories fall back to
    /// a capitalised name rather than nil, so a new Reddit category
    /// still reads "Removed by <X>".
    public static func removalDetail(forCategory category: String) -> String? {
        switch category {
        case "moderator": return "Moderator"
        case "automod_filtered": return "AutoMod"
        case "reddit": return "Reddit Admins"
        default: return category.isEmpty ? nil : category.capitalized
        }
    }

    /// Reason-resolution rule. The archive copy is checked first
    /// (it is free and already fetched), then the live `/api/info`
    /// object, or nil if the item no longer resolves.
    public static func resolveReason(archive: [String: Any], kind: Kind, live: [String: Any]?) -> (Reason, String?) {
        let author = "Author"
        if let category = archive["removed_by_category"] as? String, !category.isEmpty {
            if category == "deleted" { return (.deleted, author) }
            return (.removed, removalDetail(forCategory: category))
        }
        guard let live else { return (.deleted, author) }
        if (live["author"] as? String) == "[deleted]" { return (.deleted, author) }
        switch live[kind.bodyKey] as? String {
        case "[removed]": return (.removed, nil)
        case "[deleted]": return (.deleted, author)
        default: return (.hidden, nil)
        }
    }

    public static func fullName(of raw: [String: Any], kind: Kind) -> String? {
        if let name = raw["name"] as? String, !name.isEmpty { return name }
        if let id = raw["id"] as? String, !id.isEmpty { return kind.fullNamePrefix + id }
        return nil
    }

    static func createdUTC(_ raw: [String: Any]) -> Double? {
        if let number = raw["created_utc"] as? NSNumber { return number.doubleValue }
        if let string = raw["created_utc"] as? String, let value = Double(string) { return value }
        return nil
    }

    /// Builds an item from an archive dict: gallery `media_metadata`
    /// in `gallery_data` order first, then a direct image link, then
    /// the `preview` source, with the thumbnail as the last-resort
    /// preview.
    public static func item(fromArchive raw: [String: Any], kind: Kind, reason: Reason, removalDetail: String?) -> Item? {
        guard let name = fullName(of: raw, kind: kind) else { return nil }
        var mediaURLs: [URL] = []
        var aspect: Double = 0

        func capture(_ source: [String: Any]?) {
            guard aspect == 0, let source,
                  let w = (source["x"] as? NSNumber)?.doubleValue ?? (source["width"] as? NSNumber)?.doubleValue,
                  let h = (source["y"] as? NSNumber)?.doubleValue ?? (source["height"] as? NSNumber)?.doubleValue,
                  w > 0, h > 0 else { return }
            aspect = w / h
        }
        func append(_ value: Any?, _ source: [String: Any]?) {
            guard let string = value as? String,
                  let url = URL(string: string.replacingOccurrences(of: "&amp;", with: "&")),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  !mediaURLs.contains(url) else { return }
            if mediaURLs.isEmpty { capture(source) }
            mediaURLs.append(url)
        }

        let metadata = raw["media_metadata"] as? [String: Any]
        var keys: [String] = ((raw["gallery_data"] as? [String: Any])?["items"] as? [[String: Any]] ?? [])
            .compactMap { $0["media_id"] as? String }
        if keys.isEmpty, let metadata { keys = metadata.keys.sorted() }
        for key in keys {
            let source = (metadata?[key] as? [String: Any])?["s"] as? [String: Any]
            append(source?["gif"] ?? source?["u"], source)
        }
        if mediaURLs.isEmpty {
            let direct = (raw["url_overridden_by_dest"] as? String) ?? (raw["url"] as? String)
            if let direct, let ext = URL(string: direct)?.pathExtension.lowercased(),
               ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) {
                append(direct, nil)
            }
        }
        if let image = ((raw["preview"] as? [String: Any])?["images"] as? [[String: Any]])?.first {
            let source = image["source"] as? [String: Any]
            if mediaURLs.isEmpty { append(source?["url"], source) } else { capture(source) }
        }
        var preview = mediaURLs.first
        if preview == nil, let thumb = raw["thumbnail"] as? String, let url = URL(string: thumb),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            preview = url
        }
        let permalink = (raw["permalink"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Item(
            fullName: name, kind: kind, reason: reason, removalDetail: removalDetail,
            author: raw["author"] as? String,
            score: (raw["score"] as? NSNumber)?.intValue,
            title: raw["title"] as? String,
            body: raw[kind.bodyKey] as? String,
            parentPostTitle: raw["link_title"] as? String,
            subreddit: raw["subreddit"] as? String,
            permalink: permalink,
            createdDate: createdUTC(raw).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
            mediaURLs: mediaURLs, previewURL: preview, previewAspectRatio: aspect)
    }

    /// The candidate filter: archived items missing from the live
    /// listing, de-duplicated by fullname (Arctic's `before` cursor
    /// can repeat items that share a created second). When the live
    /// listing stopped early, anything older than the oldest live item
    /// seen was never checked and would otherwise read as a false
    /// HIDDEN, so it is dropped.
    public static func candidates(archive: [[String: Any]], kind: Kind, liveFullNames: Set<String>,
                                  liveIncomplete: Bool, liveOldestCreatedUTC: Double?) -> [[String: Any]] {
        var seen = Set<String>()
        var result: [[String: Any]] = []
        for raw in archive {
            guard let name = fullName(of: raw, kind: kind), !liveFullNames.contains(name), !seen.contains(name) else { continue }
            if liveIncomplete, let oldest = liveOldestCreatedUTC, let created = createdUTC(raw), created < oldest { continue }
            seen.insert(name)
            result.append(raw)
        }
        return result
    }

    // MARK: - Cache

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (Date, [Item])] = [:]

    static func cached(_ key: String) -> [Item]? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        guard let (at, items) = cache[key], Date().timeIntervalSince(at) <= cacheTTL else { return nil }
        return items
    }

    static func store(_ key: String, _ items: [Item]) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        cache[key] = (Date(), items)
    }

    // MARK: - Fetch

    /// A Reddit GET that returns the raw JSON body (authenticated via
    /// the app's own client, so either transport works).
    public typealias RedditGET = @Sendable (_ path: String, _ parameters: [String: String]) async throws -> Data

    /// Fetches and classifies, reporting the same three bounded
    /// phases upstream does: 0-0.35 live listing, 0.35-0.75 archive,
    /// 0.75-1 classification.
    public static func fetch(username: String, kind: Kind, forceRefresh: Bool,
                             redditGET: RedditGET,
                             session: URLSession = .shared,
                             progress: @escaping @Sendable (Double, String) -> Void = { _, _ in }) async throws -> [Item] {
        progress(0, "Checking current content")
        guard !username.isEmpty else { throw FetchError.noUsername }
        let cacheKey = "\(username.lowercased()):\(kind.rawValue)"
        if !forceRefresh, let hit = cached(cacheKey) {
            progress(1, "Ready")
            return hit
        }

        // Live listing. A page-1 failure is fatal: an empty
        // live set would misclassify everything as hidden or deleted.
        var liveNames = Set<String>()
        var liveOldest: Double?
        var liveIncomplete = false
        var after: String?
        repeat {
            var params = ["limit": String(pageSize)]
            if let after { params["after"] = after }
            let data: Data
            do {
                data = try await redditGET("/user/\(username)/\(kind.liveListing)", params)
            } catch {
                if liveNames.isEmpty && after == nil { throw FetchError.liveListingFailed }
                liveIncomplete = true
                break
            }
            let listing = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [String: Any]
            let children = (listing?["children"] as? [[String: Any]]) ?? []
            for child in children {
                guard let d = child["data"] as? [String: Any] else { continue }
                if let name = d["name"] as? String, !name.isEmpty { liveNames.insert(name) }
                if let c = createdUTC(d), liveOldest.map({ c < $0 }) ?? true { liveOldest = c }
            }
            progress(0.35 * min(1, Double(liveNames.count) / Double(liveListingCap)), "Checking current content")
            let next = listing?["after"] as? String
            after = (next?.isEmpty == false && !children.isEmpty) ? next : nil
        } while after != nil && liveNames.count < liveListingCap

        // Arctic Shift author search, newest first, paged
        // by `before` = oldest created_utc seen.
        progress(0.35, "Searching the archive")
        var archive: [[String: Any]] = []
        var before: Double?
        var archiveIncomplete = false
        while archive.count < arcticCap {
            var components = URLComponents(string: "https://arctic-shift.photon-reddit.com" + kind.arcticSearchPath)!
            var items = [
                URLQueryItem(name: "author", value: username),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "md2html", value: "false"),
            ]
            if let before { items.append(URLQueryItem(name: "before", value: String(Int(before)))) }
            components.queryItems = items
            guard let url = components.url else { break }
            var request = URLRequest(url: url)
            request.timeoutInterval = requestTimeout
            let page: [[String: Any]]
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rows = root["data"] as? [[String: Any]] else { throw FetchError.archiveFailed }
                page = rows
            } catch {
                if before == nil { throw FetchError.archiveFailed }
                archiveIncomplete = true
                break
            }
            var oldest = before
            for row in page {
                archive.append(row)
                if let c = createdUTC(row), oldest.map({ c < $0 }) ?? true { oldest = c }
            }
            progress(0.35 + 0.40 * min(1, Double(archive.count) / Double(arcticCap)), "Searching the archive")
            guard page.count >= pageSize, let oldest, oldest != before else { break }
            before = oldest
        }

        let complete = !liveIncomplete && !archiveIncomplete
        let picked = candidates(archive: archive, kind: kind, liveFullNames: liveNames,
                                liveIncomplete: liveIncomplete, liveOldestCreatedUTC: liveOldest)
        if picked.isEmpty {
            if complete { store(cacheKey, []) }
            progress(1, "Ready")
            return []
        }

        // Classification, batched through /api/info. Parent
        // posts ride along for comments so each row gets its context
        // title without one request per cell.
        progress(0.75, "Checking archived items")
        var lookup: [String] = []
        var lookupSeen = Set<String>()
        for raw in picked {
            if let n = fullName(of: raw, kind: kind), lookupSeen.insert(n).inserted { lookup.append(n) }
        }
        if kind == .comment {
            for raw in picked {
                if let link = raw["link_id"] as? String, link.hasPrefix("t3_"), lookupSeen.insert(link).inserted { lookup.append(link) }
            }
        }
        var live: [String: [String: Any]] = [:]
        var unresolvable = Set<String>()
        let chunks = stride(from: 0, to: lookup.count, by: infoBatchSize).map { Array(lookup[$0..<min($0 + infoBatchSize, lookup.count)]) }
        for (index, chunk) in chunks.enumerated() {
            do {
                let data = try await redditGET("/api/info", ["id": chunk.joined(separator: ",")])
                let listing = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [String: Any]
                for child in (listing?["children"] as? [[String: Any]]) ?? [] {
                    if let d = child["data"] as? [String: Any], let n = d["name"] as? String { live[n] = d }
                }
            } catch {
                // A failed chunk is dropped rather than guessed at.
                unresolvable.formUnion(chunk)
            }
            progress(0.75 + 0.24 * Double(index + 1) / Double(chunks.count), "Checking archived items")
        }

        var results: [Item] = []
        for raw in picked {
            guard let name = fullName(of: raw, kind: kind), !unresolvable.contains(name) else { continue }
            let (reason, detail) = resolveReason(archive: raw, kind: kind, live: live[name])
            guard var item = item(fromArchive: raw, kind: kind, reason: reason, removalDetail: detail) else { continue }
            if (item.parentPostTitle ?? "").isEmpty, let link = raw["link_id"] as? String,
               let title = live[link]?["title"] as? String {
                item.parentPostTitle = title
            }
            results.append(item)
        }
        results.sort { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
        if complete && unresolvable.isEmpty { store(cacheKey, results) }
        progress(1, "Ready")
        return results
    }
}
