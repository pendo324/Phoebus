import Foundation

/// Reborn's "Post Filters": device-wide content filters beyond Apollo's
/// native Filters & Blocks screen. Unlike the flat, global `ContentFilter`,
/// these can scope keywords to one subreddit, filter by flair, and match
/// subreddit-name substrings.
///
/// Three kinds:
///
///  1. **Per-subreddit keywords** (`PostFilterSubreddits` -> `keywords`):
///     hide posts in that subreddit whose title **or link URL** contains
///     any term (case-insensitive substring).
///  2. **Per-subreddit flairs** (`PostFilterSubreddits` -> `flairs`):
///     hide posts whose flair label equals any entry. Exact match on the
///     normalized visible label, so "Spoiler" does not hide "Not a Spoiler".
///  3. **Subreddit-name substrings** (`PostFilterNameSubstrings`): hide any
///     post whose subreddit name contains one of these, e.g. "circlejerk"
///     hides r/carscirclejerk.
///
/// Crossposts are tested against their parent too, so a crosspost from a
/// filtered subreddit (or carrying the parent's title/flair) is also hidden.
public struct PostFilterRules: Codable, Sendable, Equatable {
    /// Per-subreddit rules, keyed by lowercased subreddit name.
    public struct SubredditRules: Codable, Sendable, Equatable {
        public var keywords: [String]
        public var flairs: [String]

        public init(keywords: [String] = [], flairs: [String] = []) {
            self.keywords = keywords
            self.flairs = flairs
        }

        /// Keywords plus flairs.
        public var ruleCount: Int { keywords.count + flairs.count }
    }

    public var subreddits: [String: SubredditRules]
    public var nameSubstrings: [String]

    public init(subreddits: [String: SubredditRules] = [:], nameSubstrings: [String] = []) {
        self.subreddits = subreddits
        self.nameSubstrings = nameSubstrings
    }

    public static let empty = PostFilterRules()

    /// Whether anything is configured at all. The common case is no rules,
    /// so callers check this before touching a post.
    public var isEmpty: Bool { subreddits.isEmpty && nameSubstrings.isEmpty }

    /// The visible flair label with `:emoji:` snoomoji tokens removed,
    /// whitespace collapsed, trimmed and lowercased, so an exact comparison
    /// matches what the user sees on the chip.
    public static func normalizedFlair(_ label: String?) -> String {
        guard let label else { return "" }
        let withoutEmoji = label.replacingOccurrences(
            of: ":[A-Za-z0-9_-]+:", with: " ", options: .regularExpression
        )
        let collapsed = withoutEmoji.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// "Filter Subreddits by Name": whether a subreddit's name contains one
    /// of the words, for feeds and search suggestions alike.
    public func hidesSubredditName(_ name: String) -> Bool {
        let key = name.lowercased()
        return nameSubstrings.contains { !$0.isEmpty && key.contains($0.lowercased()) }
    }

    /// Whether a post in `subreddit` with this `title`/`url`/`flair`
    /// should be hidden. Crosspost parents are handled by the caller
    /// passing the parent's values in a second call.
    public func hides(subreddit: String, title: String, url: String?, flair: String?) -> Bool {
        guard !isEmpty, !subreddit.isEmpty else { return false }
        let subKey = subreddit.lowercased()

        // 1) Subreddit-name substring match, applies to ANY subreddit.
        for fragment in nameSubstrings where !fragment.isEmpty {
            if subKey.contains(fragment.lowercased()) { return true }
        }

        // 2) Per-subreddit keyword / flair rules.
        guard let rules = subreddits[subKey] else { return false }

        if !rules.keywords.isEmpty {
            let titleLower = title.lowercased()
            let urlLower = (url ?? "").lowercased()
            for term in rules.keywords where !term.isEmpty {
                let t = term.lowercased()
                if titleLower.contains(t) || urlLower.contains(t) { return true }
            }
        }

        if !rules.flairs.isEmpty {
            let flairLower = Self.normalizedFlair(flair)
            if !flairLower.isEmpty {
                // Exact (visible) label match.
                for f in rules.flairs where f.lowercased() == flairLower { return true }
            }
        }
        return false
    }
}

/// Persists `PostFilterRules` under Reborn's two-key layout.
public enum PostFilterStore {
    private static let subredditsKey = "com.pendo324.Phoebus.postFilterSubreddits"
    private static let nameSubstringsKey = "com.pendo324.Phoebus.postFilterNameSubstrings"

    public static let storage = CustomSettingsSource<PostFilterRules>(
        key: subredditsKey, load: { load(defaults: $0) }, save: { write($0, defaults: $1) })

    public static func load(defaults: UserDefaults = .standard) -> PostFilterRules {
        var rules = PostFilterRules()
        if let data = defaults.data(forKey: subredditsKey),
           let decoded = try? JSONDecoder().decode([String: PostFilterRules.SubredditRules].self, from: data) {
            rules.subreddits = decoded
        }
        rules.nameSubstrings = defaults.stringArray(forKey: nameSubstringsKey) ?? []
        return rules
    }

    public static func save(_ rules: PostFilterRules, defaults: UserDefaults = .standard) {
        storage.save(rules, to: defaults)
    }

    private static func write(_ rules: PostFilterRules, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(rules.subreddits) {
            defaults.set(data, forKey: subredditsKey)
        }
        defaults.set(rules.nameSubstrings, forKey: nameSubstringsKey)
    }
}
