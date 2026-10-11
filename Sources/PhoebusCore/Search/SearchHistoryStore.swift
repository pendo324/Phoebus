import Foundation

/// A query run from the Search tab or a feed's search field. Phoebus
/// addition: neither Apollo nor Reborn keeps search history.
public struct RecentSearch: Codable, Sendable, Hashable, Identifiable {
    /// A post search reruns; a user entry, whose query is the username
    /// opened from the Users section, opens that profile.
    public enum Kind: String, Codable, Sendable {
        case posts, user
    }

    public var query: String
    /// The subreddit searched, or empty for all of Reddit.
    public var subreddit: String
    /// `SearchEngine.rawValue`; Google, Kagi and Reddit Answers searches
    /// are always site-wide.
    public var engine: Int
    public var kind: Kind
    public var searchedAt: Date

    public init(query: String, subreddit: String = "", engine: SearchEngine = .reddit, kind: Kind = .posts,
                searchedAt: Date = Date()) {
        self.query = query
        self.subreddit = subreddit
        self.engine = engine.rawValue
        self.kind = kind
        self.searchedAt = searchedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        subreddit = try container.decode(String.self, forKey: .subreddit)
        engine = try container.decode(Int.self, forKey: .engine)
        kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? .posts
        searchedAt = try container.decode(Date.self, forKey: .searchedAt)
    }

    enum CodingKeys: String, CodingKey {
        case query, subreddit, engine, kind, searchedAt
    }

    public var id: String {
        kind == .posts
            ? SearchHistoryStore.identity(query, subreddit, String(engine))
            : SearchHistoryStore.identity(query, subreddit, String(engine), kind.rawValue)
    }
    public var searchEngine: SearchEngine { SearchEngine(rawValue: engine) ?? .reddit }
}

/// A pinned post search: query, scope, sort and (for Top and Comments)
/// time range.
public struct SavedSearch: Codable, Sendable, Hashable, Identifiable {
    public var query: String
    /// The subreddit searched, or empty for all of Reddit.
    public var subreddit: String
    public var sort: String
    /// Reddit's `t`, kept only for the sorts that take one.
    public var time: String?
    public var savedAt: Date

    public init(query: String, subreddit: String = "", sort: String = "relevance", time: String? = nil, savedAt: Date = Date()) {
        self.query = query
        self.subreddit = subreddit
        self.sort = sort
        self.time = SavedSearch.sortsWithTime.contains(sort) ? time : nil
        self.savedAt = savedAt
    }

    /// Post search sorts that Reddit filters by `t`.
    public static let sortsWithTime: Set<String> = ["top", "comments"]

    public var id: String { SearchHistoryStore.identity(query, subreddit, sort, time ?? "") }
}

/// One account's recent and saved searches.
public struct SearchHistoryLists: Codable, Sendable, Equatable {
    public var recent: [RecentSearch]
    public var saved: [SavedSearch]

    public init(recent: [RecentSearch] = [], saved: [SavedSearch] = []) {
        self.recent = recent
        self.saved = saved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recent = try container.decodeIfPresent([RecentSearch].self, forKey: .recent) ?? []
        saved = try container.decodeIfPresent([SavedSearch].self, forKey: .saved) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case recent, saved
    }

    /// Recent searches in one scope, newest first. Google, Kagi and Reddit
    /// Answers searches only appear in the site-wide scope.
    public func recent(subreddit: String) -> [RecentSearch] {
        recent.filter { $0.subreddit.caseInsensitiveCompare(subreddit) == .orderedSame }
    }

    public func isSaved(_ search: SavedSearch) -> Bool {
        saved.contains { $0.id == search.id }
    }
}

/// "Save Search History". Phoebus addition, so there is no Apollo key.
public struct SearchHistorySettings: Codable, Sendable, Equatable {
    public var saveHistory: Bool

    public static let `default` = SearchHistorySettings(saveHistory: true)

    public init(saveHistory: Bool) {
        self.saveHistory = saveHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        saveHistory = try container.decode(.saveHistory, default: d, \.saveHistory)
    }

    enum CodingKeys: String, CodingKey {
        case saveHistory
    }
}

public enum SearchHistorySettingsStore {
    public static let storage = SettingsStore<SearchHistorySettings>(
        key: "com.pendo324.Phoebus.searchHistorySettings") { .default }

    public static func load() -> SearchHistorySettings { storage.load() }
}

extension SearchHistorySettings: StoredSettingsModel {
    public static var store: SettingsStore<SearchHistorySettings> { SearchHistorySettingsStore.storage }
}

/// Recent and saved searches, kept per account (signed out uses the
/// empty key) so a switch never shows another account's queries.
public enum SearchHistoryStore {
    /// Lowercased username → that account's lists.
    public static let storage = SettingsStore<[String: SearchHistoryLists]>(
        key: "com.pendo324.Phoebus.searchHistory") { [:] }

    public static let recentLimit = 30

    private static var account: String {
        FavoriteSubredditsAccountContext.currentUsernameProvider()?.lowercased() ?? ""
    }

    static func identity(_ parts: String...) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.joined(separator: "\u{1F}")
    }

    /// The active account's lists out of a loaded (or `@Setting`) value.
    public static func lists(in all: [String: SearchHistoryLists]) -> SearchHistoryLists {
        all[account] ?? SearchHistoryLists()
    }

    public static func lists() -> SearchHistoryLists { lists(in: storage.load()) }

    /// Puts `entry` first, dropping an earlier copy of the same query,
    /// scope and engine (case-insensitively), and keeps the newest `limit`.
    public static func inserting(_ entry: RecentSearch, into list: [RecentSearch],
                                 limit: Int = recentLimit) -> [RecentSearch] {
        var updated = list.filter { $0.id != entry.id }
        updated.insert(entry, at: 0)
        return Array(updated.prefix(limit))
    }

    /// Records a search unless "Save Search History" is off.
    public static func record(query: String, subreddit: String = "", engine: SearchEngine = .reddit,
                              at date: Date = Date()) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, SearchHistorySettingsStore.load().saveHistory else { return }
        let entry = RecentSearch(query: trimmed, subreddit: engine == .reddit ? subreddit : "",
                                 engine: engine, searchedAt: date)
        update { $0.recent = inserting(entry, into: $0.recent) }
    }

    /// Records a profile opened from the Search tab's Users section.
    public static func record(user name: String, at date: Date = Date()) {
        guard !name.isEmpty, SearchHistorySettingsStore.load().saveHistory else { return }
        let entry = RecentSearch(query: name, kind: .user, searchedAt: date)
        update { $0.recent = inserting(entry, into: $0.recent) }
    }

    public static func remove(_ entry: RecentSearch) {
        update { $0.recent.removeAll { $0.id == entry.id } }
    }

    /// Clears the active account's recent searches in one scope.
    public static func clearRecent(subreddit: String) {
        update { lists in
            lists.recent.removeAll { $0.subreddit.caseInsensitiveCompare(subreddit) == .orderedSame }
        }
    }

    /// Settings' "Clear Search History": every account's recent searches.
    /// Saved searches are kept; they are removed one at a time.
    public static func clearAllRecent() {
        var all = storage.load()
        for key in all.keys { all[key]?.recent = [] }
        storage.save(all.filter { !$0.value.recent.isEmpty || !$0.value.saved.isEmpty })
    }

    public static func save(_ search: SavedSearch) {
        update { lists in
            guard !lists.isSaved(search) else { return }
            lists.saved.insert(search, at: 0)
        }
    }

    public static func unsave(_ search: SavedSearch) {
        update { $0.saved.removeAll { $0.id == search.id } }
    }

    public static func isSaved(_ search: SavedSearch) -> Bool { lists().isSaved(search) }

    private static func update(_ change: (inout SearchHistoryLists) -> Void) {
        let key = account
        var all = storage.load()
        var lists = all[key] ?? SearchHistoryLists()
        change(&lists)
        all[key] = lists
        storage.save(all)
    }
}
