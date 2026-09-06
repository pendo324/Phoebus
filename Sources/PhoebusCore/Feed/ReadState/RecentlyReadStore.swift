import Foundation

/// Reborn's "Recently Read Posts": a Profile-tab list of posts you've
/// opened recently, newest first. Reddit's API has no "recently viewed"
/// endpoint, and `ReadPostStore`'s flat read/unread `Set` has no order or
/// row data, so this keeps its own small local history of lightweight post
/// snapshots captured when a post is opened.
public struct RecentlyReadEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { fullname }
    public var fullname: String
    public var title: String
    public var subreddit: String
    public var author: String
    public var permalink: String
    public var viewedAt: Date
    public var isNSFW: Bool
    public var thumbnailURL: String?

    public init(fullname: String, title: String, subreddit: String, author: String, permalink: String, viewedAt: Date = Date(), isNSFW: Bool = false, thumbnailURL: String? = nil) {
        self.fullname = fullname
        self.title = title
        self.subreddit = subreddit
        self.author = author
        self.permalink = permalink
        self.viewedAt = viewedAt
        self.isNSFW = isNSFW
        self.thumbnailURL = thumbnailURL
    }

    /// Custom decode so entries persisted without `isNSFW`/`thumbnailURL`
    /// still decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullname = try container.decode(String.self, forKey: .fullname)
        title = try container.decode(String.self, forKey: .title)
        subreddit = try container.decode(String.self, forKey: .subreddit)
        author = try container.decode(String.self, forKey: .author)
        permalink = try container.decode(String.self, forKey: .permalink)
        viewedAt = try container.decode(Date.self, forKey: .viewedAt)
        isNSFW = try container.decodeIfPresent(Bool.self, forKey: .isNSFW) ?? false
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
    }
}

/// Reborn's `FilterNSFWRecentlyRead` / `ShowRecentlyReadThumbnails` settings.
public struct RecentlyReadSettings: Codable, Sendable, Equatable {
    public var filterNSFW: Bool
    public var showThumbnails: Bool
    /// Reborn "Recently Read Posts Limit" (`sReadPostMaxCount`): caps how many
    /// entries `RecentlyReadStore` remembers. `nil`/0 means unlimited.
    public var maxCount: Int?

    public static let `default` = RecentlyReadSettings(filterNSFW: false, showThumbnails: true, maxCount: nil)

    public init(filterNSFW: Bool, showThumbnails: Bool, maxCount: Int? = nil) {
        self.filterNSFW = filterNSFW
        self.showThumbnails = showThumbnails
        self.maxCount = maxCount
    }

    /// Custom decode so settings persisted before `maxCount` existed
    /// still decode successfully.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filterNSFW = try container.decode(Bool.self, forKey: .filterNSFW)
        showThumbnails = try container.decode(Bool.self, forKey: .showThumbnails)
        maxCount = try container.decodeIfPresent(Int.self, forKey: .maxCount)
    }
}

public enum RecentlyReadSettingsStore {
    private static let key = "com.pendo324.Phoebus.recentlyReadSettings"

    public static let storage = SettingsStore<RecentlyReadSettings>(key: key) { RecentlyReadSettings.default }

    public static func load() -> RecentlyReadSettings { storage.load() }

    public static func save(_ settings: RecentlyReadSettings) { storage.save(settings) }
}

public enum RecentlyReadStore {
    private static let key = "com.pendo324.Phoebus.recentlyReadPosts"

    public static func load() -> [RecentlyReadEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([RecentlyReadEntry].self, from: data) else {
            return []
        }
        return entries
    }

    /// Records a post as opened, moving it to the front if it was
    /// already present (so re-reading a post refreshes its position),
    /// and trims to `maxTracked` newest entries.
    public static func recordView(fullname: String, title: String, subreddit: String, author: String, permalink: String, isNSFW: Bool = false, thumbnailURL: String? = nil) {
        var entries = load().filter { $0.fullname != fullname }
        entries.insert(RecentlyReadEntry(fullname: fullname, title: title, subreddit: subreddit, author: author, permalink: permalink, isNSFW: isNSFW, thumbnailURL: thumbnailURL), at: 0)
        // "Recently Read Posts Limit": no cap when empty, as Reborn's.
        if let limit = RecentlyReadSettingsStore.load().maxCount, limit > 0, entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        save(entries)
    }

    /// Applies a newly set limit straight away rather than on the next read.
    public static func trim(to limit: Int?) {
        guard let limit, limit > 0 else { return }
        let entries = load()
        if entries.count > limit { save(Array(entries.prefix(limit))) }
    }

    public static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ entries: [RecentlyReadEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension RecentlyReadSettings: StoredSettingsModel {
    public static var store: SettingsStore<RecentlyReadSettings> { RecentlyReadSettingsStore.storage }
}
