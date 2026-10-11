import Foundation

/// Phoebus's "Post Rules" (not in Apollo or Reborn): hide feed posts outside
/// a score, comment or award range, show only NSFW or spoiler posts, or test
/// the title against a regular expression, each rule scoped to every feed or
/// to chosen ones. Keywords, subreddits, domains and flairs stay with the
/// existing filters; these add what they can't express.
///
/// Bounds are inclusive and `nil` means unbounded. A rule hides a post that
/// fails any of its conditions; several rules hide a post if any one does.
public struct PostRule: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var minScore: Int?
    public var maxScore: Int?
    public var minComments: Int?
    public var maxComments: Int?
    public var minAwards: Int?
    public var maxAwards: Int?
    /// "NSFW Only" / "Spoiler Only": with both on, a post that is either is kept.
    public var onlyNSFW: Bool
    public var onlySpoiler: Bool
    /// Hide posts whose title matches (case-insensitive). Empty or invalid: ignored.
    public var titleExcludesRegex: String
    /// Show only posts whose title matches (case-insensitive). Empty or invalid: ignored.
    public var titleRequiresRegex: String
    /// `PostRuleFeed` tokens; empty applies to every feed.
    public var feeds: [String]

    public init(id: UUID = UUID(), name: String = "", isEnabled: Bool = true,
                minScore: Int? = nil, maxScore: Int? = nil,
                minComments: Int? = nil, maxComments: Int? = nil,
                minAwards: Int? = nil, maxAwards: Int? = nil,
                onlyNSFW: Bool = false, onlySpoiler: Bool = false,
                titleExcludesRegex: String = "", titleRequiresRegex: String = "",
                feeds: [String] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.minScore = minScore
        self.maxScore = maxScore
        self.minComments = minComments
        self.maxComments = maxComments
        self.minAwards = minAwards
        self.maxAwards = maxAwards
        self.onlyNSFW = onlyNSFW
        self.onlySpoiler = onlySpoiler
        self.titleExcludesRegex = titleExcludesRegex
        self.titleRequiresRegex = titleRequiresRegex
        self.feeds = feeds
    }

    enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, minScore, maxScore, minComments, maxComments, minAwards, maxAwards
        case onlyNSFW, onlySpoiler, titleExcludesRegex, titleRequiresRegex, feeds
    }

    /// Every field is optional, so a hand-written or older rule still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        minScore = try? c.decodeIfPresent(Int.self, forKey: .minScore)
        maxScore = try? c.decodeIfPresent(Int.self, forKey: .maxScore)
        minComments = try? c.decodeIfPresent(Int.self, forKey: .minComments)
        maxComments = try? c.decodeIfPresent(Int.self, forKey: .maxComments)
        minAwards = try? c.decodeIfPresent(Int.self, forKey: .minAwards)
        maxAwards = try? c.decodeIfPresent(Int.self, forKey: .maxAwards)
        onlyNSFW = (try? c.decodeIfPresent(Bool.self, forKey: .onlyNSFW)) ?? false
        onlySpoiler = (try? c.decodeIfPresent(Bool.self, forKey: .onlySpoiler)) ?? false
        titleExcludesRegex = (try? c.decodeIfPresent(String.self, forKey: .titleExcludesRegex)) ?? ""
        titleRequiresRegex = (try? c.decodeIfPresent(String.self, forKey: .titleRequiresRegex)) ?? ""
        feeds = (try? c.decodeIfPresent([String].self, forKey: .feeds)) ?? []
    }

    /// The compiled title pattern, or nil when empty or invalid (the condition is then ignored).
    public static func titleRegex(_ pattern: String) -> NSRegularExpression? {
        guard !pattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// For the editor: empty counts as valid (no condition).
    public static func isValidTitleRegex(_ pattern: String) -> Bool {
        pattern.isEmpty || titleRegex(pattern) != nil
    }

    /// A typed bound: digits (and a leading minus where allowed); empty or
    /// unparseable is no bound.
    public static func parseBound(_ text: String, allowsNegative: Bool) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let negative = allowsNegative && trimmed.hasPrefix("-")
        guard let magnitude = Int(trimmed.filter(\.isNumber)) else { return nil }
        return negative ? -magnitude : magnitude
    }

    /// A minimum above its maximum, which hides every post the rule covers.
    public var hasInvertedRange: Bool {
        [(minScore, maxScore), (minComments, maxComments), (minAwards, maxAwards)].contains { pair in
            guard let low = pair.0, let high = pair.1 else { return false }
            return low > high
        }
    }

    /// Whether this rule is on and scoped to `feed`.
    public func applies(to feed: PostRuleFeed) -> Bool {
        guard isEnabled else { return false }
        if feeds.isEmpty { return true }
        return feeds.contains { PostRuleFeed(token: $0) == feed }
    }

    /// The rule's one-line summary for the list row.
    public var summary: String {
        var parts: [String] = []
        func range(_ label: String, _ low: Int?, _ high: Int?) {
            switch (low, high) {
            case let (low?, high?): parts.append("\(label) \(low)–\(high)")
            case let (low?, nil): parts.append("\(label) ≥ \(low)")
            case let (nil, high?): parts.append("\(label) ≤ \(high)")
            case (nil, nil): break
            }
        }
        range("Score", minScore, maxScore)
        range("Comments", minComments, maxComments)
        range("Awards", minAwards, maxAwards)
        if onlyNSFW { parts.append("NSFW only") }
        if onlySpoiler { parts.append("Spoiler only") }
        if !titleExcludesRegex.isEmpty { parts.append("Hide /\(titleExcludesRegex)/") }
        if !titleRequiresRegex.isEmpty { parts.append("Only /\(titleRequiresRegex)/") }
        return parts.isEmpty ? "No conditions" : parts.joined(separator: " · ")
    }

    /// A rule with its title patterns compiled once per page.
    struct Compiled {
        let rule: PostRule
        let excludes: NSRegularExpression?
        let requires: NSRegularExpression?

        init(_ rule: PostRule) {
            self.rule = rule
            excludes = PostRule.titleRegex(rule.titleExcludesRegex)
            requires = PostRule.titleRegex(rule.titleRequiresRegex)
        }

        func hides(_ post: RedditPost) -> Bool {
            func outside(_ value: Int, _ low: Int?, _ high: Int?) -> Bool {
                if let low, value < low { return true }
                if let high, value > high { return true }
                return false
            }
            if outside(post.score, rule.minScore, rule.maxScore) { return true }
            if outside(post.numComments, rule.minComments, rule.maxComments) { return true }
            if outside(post.totalAwardsReceived ?? 0, rule.minAwards, rule.maxAwards) { return true }
            if rule.onlyNSFW || rule.onlySpoiler {
                let kept = (rule.onlyNSFW && post.over18) || (rule.onlySpoiler && post.spoiler)
                if !kept { return true }
            }
            let title = post.title
            let whole = NSRange(title.startIndex..., in: title)
            if let excludes, excludes.firstMatch(in: title, range: whole) != nil { return true }
            if let requires, requires.firstMatch(in: title, range: whole) == nil { return true }
            return false
        }
    }
}

/// The feed a Post Rule is scoped to, stored as a short token so a rule
/// reads plainly in JSON: `home`, `popular`, `all`, `r/<name>`, `m/<name>`.
public enum PostRuleFeed: Hashable, Sendable {
    case home
    case popular
    case all
    case subreddit(String)
    /// Matched by the multireddit's name, the last component of its path.
    case multireddit(String)

    /// The feed a `FeedScreen` shows.
    public init(subreddit: String, multiredditPath: String?) {
        if let multiredditPath {
            let name = multiredditPath.split(separator: "/").last.map(String.init) ?? multiredditPath
            self = .multireddit(name.lowercased())
            return
        }
        switch subreddit.lowercased() {
        case "", "frontpage": self = .home
        case "popular": self = .popular
        case "all": self = .all
        case let name: self = .subreddit(name)
        }
    }

    public init?(token: String) {
        let lowered = token.trimmingCharacters(in: .whitespaces).lowercased()
        switch lowered {
        case "home": self = .home
        case "popular": self = .popular
        case "all": self = .all
        default:
            if lowered.hasPrefix("r/"), lowered.count > 2 {
                self = .subreddit(String(lowered.dropFirst(2)))
            } else if lowered.hasPrefix("m/"), lowered.count > 2 {
                self = .multireddit(String(lowered.dropFirst(2)))
            } else {
                return nil
            }
        }
    }

    public var token: String {
        switch self {
        case .home: return "home"
        case .popular: return "popular"
        case .all: return "all"
        case .subreddit(let name): return "r/\(name)"
        case .multireddit(let name): return "m/\(name)"
        }
    }

    public var displayName: String {
        switch self {
        case .home: return "Home"
        case .popular: return "Popular"
        case .all: return "All"
        case .subreddit(let name): return "r/\(name)"
        case .multireddit(let name): return "m/\(name)"
        }
    }
}

/// Persists Post Rules (UserDefaults-backed, on this device; backed up with
/// the settings domain).
public enum PostRuleStore {
    public static let storage = SettingsStore<[PostRule]>(key: "com.pendo324.Phoebus.postRules") { [] }

    public static func load() -> [PostRule] { storage.load() }

    /// Hides posts that any rule scoped to `feed` hides. Stickied posts and
    /// the signed-in user's own posts are exempt, so a score floor never
    /// hides a subreddit's announcements or what you just posted.
    public static func apply(_ posts: [RedditPost], rules: [PostRule], feed: PostRuleFeed,
                             username: String?) -> [RedditPost] {
        let active = rules.filter { $0.applies(to: feed) }.map(PostRule.Compiled.init)
        guard !active.isEmpty else { return posts }
        return posts.filter { post in
            if post.stickied { return true }
            if let username, !username.isEmpty,
               post.author.caseInsensitiveCompare(username) == .orderedSame { return true }
            return !active.contains { $0.hides(post) }
        }
    }
}
