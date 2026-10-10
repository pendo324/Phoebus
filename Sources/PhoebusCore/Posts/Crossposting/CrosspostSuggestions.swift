import Foundation

/// Destination suggestions for the crosspost composer before anything is
/// typed: recently visited subreddits, then Reddit's crosspostable list.
/// Not an Apollo or Reborn feature (inspired by Continuum's crosspost screen).
public struct CrosspostSuggestions: Equatable, Sendable {
    public var recentlyVisited: [String]
    public var suggested: [String]

    public init(recentlyVisited: [String] = [], suggested: [String] = []) {
        self.recentlyVisited = recentlyVisited
        self.suggested = suggested
    }

    public var isEmpty: Bool { recentlyVisited.isEmpty && suggested.isEmpty }

    /// Recently visited names first, then crosspostable ones not already
    /// listed, case-insensitively, without the source subreddit or any
    /// user profile (`u_<name>`).
    public static func make(recentlyVisited: [RecentlyVisitedEntry], crosspostable: [String],
                            source: String) -> CrosspostSuggestions {
        var seen: Set<String> = [source.lowercased()]
        func keep(_ name: String) -> Bool {
            let lowered = name.lowercased()
            guard !lowered.isEmpty, !lowered.hasPrefix("u_"),
                  RecentlyVisitedStore.isRecordableSubreddit(name) else { return false }
            return seen.insert(lowered).inserted
        }
        let recent = recentlyVisited.filter { $0.kind == .subreddit }.map(\.name).filter(keep)
        let suggested = crosspostable.filter(keep)
        return CrosspostSuggestions(recentlyVisited: recent, suggested: suggested)
    }

    /// Parses `GET /api/crosspostable_subreddits`: a JSON array of subreddit
    /// names. Anything else (Reddit answers signed-out requests with a
    /// `USER_REQUIRED` error object) yields an empty list.
    public static func parseCrosspostable(_ data: Data) -> [String] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return array.compactMap { item -> String? in
            if let name = item as? String { return name }
            if let object = item as? [String: Any] {
                return (object["display_name"] ?? object["name"]) as? String
            }
            return nil
        }
        .map { $0.hasPrefix("r/") ? String($0.dropFirst(2)) : $0 }
    }
}

/// Crosspostable lists already fetched this launch, per account and
/// source subreddit, so reopening the composer doesn't refetch.
actor CrosspostableSubredditsCache {
    private var lists: [String: [String]] = [:]

    func list(for key: String) -> [String]? { lists[key] }

    func store(_ list: [String], for key: String) { lists[key] = list }
}
