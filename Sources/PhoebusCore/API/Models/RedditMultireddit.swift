import Foundation

/// A Reddit multireddit — a user-defined grouping of subreddits shown
/// as a combined feed.
public struct RedditMultireddit: Codable, Sendable, Identifiable, Hashable {
    public let name: String
    public let displayName: String
    public let path: String
    public let subreddits: [SubredditRef]
    public let visibility: String
    /// Reddit's `description_md` field, matching the website's
    /// `{"display_name", "description_md"}` model shape that
    /// `updateMultireddit` PUTs back.
    public let descriptionMarkdown: String?

    public var id: String { path }

    public struct SubredditRef: Codable, Sendable, Hashable {
        public let name: String

        public init(name: String) {
            self.name = name
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, path, visibility
        case displayName = "display_name"
        case subreddits
        case descriptionMarkdown = "description_md"
    }

    public init(name: String, displayName: String, path: String, subreddits: [SubredditRef], visibility: String, descriptionMarkdown: String? = nil) {
        self.name = name
        self.displayName = displayName
        self.path = path
        self.subreddits = subreddits
        self.visibility = visibility
        self.descriptionMarkdown = descriptionMarkdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        path = try container.decode(String.self, forKey: .path)
        subreddits = (try? container.decode([SubredditRef].self, forKey: .subreddits)) ?? []
        visibility = (try? container.decode(String.self, forKey: .visibility)) ?? "private"
        descriptionMarkdown = try container.decodeIfPresent(String.self, forKey: .descriptionMarkdown)
    }

    /// Reborn's multireddit-row subtitle: the `description_md` when set, else a
    /// fallback subreddit-count-style line, but blank when
    /// `hideMultiredditDescriptions` is on. A pure function so
    /// `SubredditsRootScreen` and `MultiredditListScreen` share one
    /// implementation and it is smoke-testable.
    public func subtitle(hideDescriptions: Bool, fallback: String) -> String? {
        if hideDescriptions { return nil }
        if let description = descriptionMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return description
        }
        return fallback
    }
}

/// Persists Apollo's `ExpandedMultireddits` state: which multireddits are
/// currently showing their member subreddits inline in the subreddit list.
///
/// Apollo keys it by multireddit name, not path, so two same-named multis
/// expand together.
public enum ExpandedMultiredditsStore {
    private static let key = "com.pendo324.Phoebus.expandedMultireddits"

    public static func load(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public static func save(_ names: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(names), forKey: key)
    }
}
