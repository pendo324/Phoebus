import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where "Random Subreddit" and "Trending Subreddits" pull their
/// subreddit name from. Matches Apollo-Reborn's "Custom Subreddit
/// Sources" setting — by default Random and Trending read Reborn's
/// hosted lists, but a user can point either at their own URL
/// returning subreddit names for a custom pool. Reddit's own
/// endpoints remain a fallback when a source can't be reached.
public struct CustomSubredditSourceSettings: Codable, Sendable, Equatable {
    /// Custom URL for Random Subreddit. `nil` means Reborn's default.
    public var randomSourceURL: String?
    /// Custom URL for Trending Subreddits. `nil` means Reborn's default.
    public var trendingSourceURL: String?
    /// Custom URL for Random NSFW Subreddit (`RandNsfwSubredditsSource`),
    /// a setting distinct from `randomSourceURL`. No default: the row asks
    /// the user to configure one.
    public var randomNSFWSourceURL: String?
    /// `showRandNSFWInSearch`: gates the `randomNSFWSourceURL` field above
    /// (shown greyed-out while off). Off by default, as in Apollo.
    public var showRandNSFWInSearch: Bool

    public static let `default` = CustomSubredditSourceSettings(randomSourceURL: nil, trendingSourceURL: nil, randomNSFWSourceURL: nil, showRandNSFWInSearch: false)

    /// Apollo-Reborn's default sources; an empty field means these.
    public static let defaultRandomSourceURL = "https://jeffreyca.github.io/subreddits/popular.txt"
    public static let defaultTrendingSourceURL = "https://jeffreyca.github.io/subreddits/trending-subriff-blended.txt"

    public var effectiveRandomSourceURL: String { Self.nonEmpty(randomSourceURL) ?? Self.defaultRandomSourceURL }
    public var effectiveTrendingSourceURL: String { Self.nonEmpty(trendingSourceURL) ?? Self.defaultTrendingSourceURL }
    /// Random NSFW has no default; `nil` means the user must set one.
    public var effectiveRandomNSFWSourceURL: String? { Self.nonEmpty(randomNSFWSourceURL) }

    private static func nonEmpty(_ url: String?) -> String? {
        guard let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public init(randomSourceURL: String?, trendingSourceURL: String?, randomNSFWSourceURL: String?, showRandNSFWInSearch: Bool = false) {
        self.randomSourceURL = randomSourceURL
        self.trendingSourceURL = trendingSourceURL
        self.randomNSFWSourceURL = randomNSFWSourceURL
        self.showRandNSFWInSearch = showRandNSFWInSearch
    }

    /// Custom decode so settings persisted before `showRandNSFWInSearch`
    /// existed still decode successfully (defaulting to `false`)
    /// instead of falling back to `.default` and silently discarding a
    /// user's already-saved custom source URLs.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        randomSourceURL = try container.decodeIfPresent(String.self, forKey: .randomSourceURL)
        trendingSourceURL = try container.decodeIfPresent(String.self, forKey: .trendingSourceURL)
        randomNSFWSourceURL = try container.decodeIfPresent(String.self, forKey: .randomNSFWSourceURL)
        showRandNSFWInSearch = try container.decodeIfPresent(Bool.self, forKey: .showRandNSFWInSearch) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case randomSourceURL, trendingSourceURL, randomNSFWSourceURL, showRandNSFWInSearch
    }
}

public enum CustomSubredditSourceStore {
    public static let storage = SettingsStore<CustomSubredditSourceSettings>(
        key: "com.pendo324.Phoebus.customSubredditSources") { .default }

    public static func load() -> CustomSubredditSourceSettings { storage.load() }

    public static func save(_ settings: CustomSubredditSourceSettings) { storage.save(settings) }
}

/// Fetches a subreddit name from a custom source URL — a plain
/// `GET` expected to return either a bare JSON array of strings
/// (`["aww", "cats", "pics"]`) or `{"subreddits": [...]}`, from which
/// one entry is picked at random. No API key or Reddit auth involved,
/// matching Apollo-Reborn's description of this as an arbitrary
/// external URL.
public enum CustomSubredditSourceClient {
    public enum ClientError: Error, Sendable {
        case invalidResponse
        case emptyList
    }

    public static func fetchRandomSubredditName(from urlString: String, session: URLSession = .shared) async throws -> String {
        guard let picked = try await fetchNames(from: urlString, session: session).randomElement() else {
            throw ClientError.emptyList
        }
        return picked
    }

    /// `limit` distinct names picked at random, as Reborn's trending row
    /// does; the whole list, in order, when `limit` is 0 or covers it.
    public static func sample(_ names: [String], limit: Int) -> [String] {
        var unique: [String] = []
        var seen = Set<String>()
        for name in names where seen.insert(name.lowercased()).inserted { unique.append(name) }
        guard limit > 0, limit < unique.count else { return unique }
        return Array(unique.shuffled().prefix(limit))
    }

    /// Every name in a user-typed source URL; an unparseable URL throws
    /// instead of crashing.
    public static func fetchNames(from urlString: String, session: URLSession = .shared) async throws -> [String] {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ClientError.invalidResponse
        }
        let (data, _) = try await session.data(from: url)
        return try parseNames(from: data)
    }

    /// Parses a bare JSON array of names, a `{"subreddits": [...]}`
    /// wrapper, or Reborn's plain-text format, one name per line. A leading
    /// `r/` is tolerated. Anything that isn't a valid community name (dates,
    /// headings, prose) is dropped: routing one opens a listing that never
    /// loads (Reborn #1272). Split out so it's testable without network
    /// access.
    public static func parseNames(from data: Data) throws -> [String] {
        if let names = try? JSONDecoder().decode([String].self, from: data) {
            return names.map(clean).filter(isValidName)
        }
        struct Wrapped: Decodable { let subreddits: [String] }
        if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data) {
            return wrapped.subreddits.map(clean).filter(isValidName)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw ClientError.invalidResponse }
        let names = text.split(whereSeparator: \.isNewline).map { clean(String($0)) }.filter(isValidName)
        guard !names.isEmpty else { throw ClientError.invalidResponse }
        return names
    }

    /// Reddit community names: 3-21 ASCII letters, digits or underscores,
    /// with a few grandfathered 2-letter ones like r/de.
    public static func isValidName(_ name: String) -> Bool {
        (2...21).contains(name.count)
            && name.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }
    }

    private static func clean(_ name: String) -> String {
        stripPrefix(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func stripPrefix(_ name: String) -> String {
        name.hasPrefix("r/") ? String(name.dropFirst(2)) : name
    }
}
