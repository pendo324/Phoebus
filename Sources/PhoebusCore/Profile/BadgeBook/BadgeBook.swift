import Foundation

/// Apollo-Reborn's Badge Book, Achievements half: Reddit's own badge system
/// (79 definitions across 5 categories, bundled from Reddit's public catalog
/// data). The Trophy Case half is covered by the Trophies API.
///
/// Reborn scrapes per-user earned state from Reddit's profile page; here earned
/// state is a local approximation from public API data (karma, account age,
/// etc).
public struct AchievementDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var bio: String
    public var category: String
    /// Reddit-hosted icon URL for this achievement (i.redd.it CDN, not a
    /// bundled asset).
    public var imageURL: String?

    public init(id: String, title: String, bio: String, category: String, imageURL: String? = nil) {
        self.id = id
        self.title = title
        self.bio = bio
        self.category = category
        self.imageURL = imageURL
    }
}

public enum AchievementCatalog {
    /// The full 79-achievement catalog and its 5 categories, loaded
    /// from the bundled `RealAchievements.json` resource.
    public static let categories: [String] = loadCatalog().categories
    public static let all: [AchievementDefinition] = loadCatalog().achievements

    public static func achievements(inCategory category: String) -> [AchievementDefinition] {
        all.filter { $0.category == category }
    }

    private struct CatalogFile: Codable {
        let categories: [String]
        let achievements: [AchievementDefinition]
    }

    private static func loadCatalog() -> (categories: [String], achievements: [AchievementDefinition]) {
        guard let url = Bundle.module.url(forResource: "RealAchievements", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CatalogFile.self, from: data) else {
            return ([], [])
        }
        return (file.categories, file.achievements)
    }
}

/// Locally-computable badges for account-state signals (verified email,
/// account age, gold) approximated from the public `/user/<name>/about`
/// endpoint. Badges needing Reddit-side computation (karma percentiles,
/// moderation, streaks) are shown without an earned/locked determination.
public struct BadgeDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    /// SF Symbol name for the badge icon; Apollo's badge artwork is not bundled.
    public var symbolName: String
    public var criteria: BadgeCriteria

    public init(id: String, name: String, description: String, symbolName: String, criteria: BadgeCriteria) {
        self.id = id
        self.name = name
        self.description = description
        self.symbolName = symbolName
        self.criteria = criteria
    }
}

/// The evaluable conditions a badge can require: a small closed set of
/// pure, deterministic checks over `RedditUser` data.
public enum BadgeCriteria: Codable, Sendable, Equatable {
    case commentKarmaAtLeast(Int)
    case linkKarmaAtLeast(Int)
    case totalKarmaAtLeast(Int)
    case accountAgeYearsAtLeast(Int)
    case hasVerifiedEmail
    case isGold
    case trophyCountAtLeast(Int)
    /// Earned for having any real Reddit trophy named with this
    /// substring (case-insensitive), e.g. a "One-Year Club" trophy also
    /// counts toward this Badge Book's own "Veteran" badge.
    case hasTrophyNamed(String)
}

/// Pure evaluation input, separated from `RedditUser`/`[RedditTrophy]`
/// so the engine is trivially testable with hand-built fixtures.
public struct BadgeEvaluationContext: Sendable {
    public var commentKarma: Int
    public var linkKarma: Int
    public var accountCreated: Date
    public var hasVerifiedEmail: Bool
    public var isGold: Bool
    public var trophyNames: [String]
    public var now: Date

    public init(commentKarma: Int, linkKarma: Int, accountCreated: Date, hasVerifiedEmail: Bool, isGold: Bool, trophyNames: [String], now: Date = Date()) {
        self.commentKarma = commentKarma
        self.linkKarma = linkKarma
        self.accountCreated = accountCreated
        self.hasVerifiedEmail = hasVerifiedEmail
        self.isGold = isGold
        self.trophyNames = trophyNames
        self.now = now
    }

    public static func from(user: RedditUser, trophies: [RedditTrophy]) -> BadgeEvaluationContext {
        BadgeEvaluationContext(
            commentKarma: user.commentKarma,
            linkKarma: user.linkKarma,
            accountCreated: user.created,
            hasVerifiedEmail: user.hasVerifiedEmail,
            isGold: user.isGold,
            trophyNames: trophies.map(\.name)
        )
    }

    var accountAgeYears: Int {
        let components = Calendar(identifier: .gregorian).dateComponents([.year], from: accountCreated, to: now)
        return max(0, components.year ?? 0)
    }
}

public struct EarnedBadge: Identifiable, Sendable, Equatable {
    public var id: String { definition.id }
    public let definition: BadgeDefinition
    public let isEarned: Bool
}

public enum BadgeBookEngine {
    /// Evaluates every catalog badge against the given context,
    /// returning both earned and unearned badges (in catalog order)
    /// so the UI can render locked/unlocked states rather than only
    /// showing what's already earned.
    public static func evaluate(catalog: [BadgeDefinition] = BadgeCatalog.all, context: BadgeEvaluationContext) -> [EarnedBadge] {
        catalog.map { EarnedBadge(definition: $0, isEarned: isEarned($0.criteria, context: context)) }
    }

    static func isEarned(_ criteria: BadgeCriteria, context: BadgeEvaluationContext) -> Bool {
        switch criteria {
        case .commentKarmaAtLeast(let threshold):
            return context.commentKarma >= threshold
        case .linkKarmaAtLeast(let threshold):
            return context.linkKarma >= threshold
        case .totalKarmaAtLeast(let threshold):
            return (context.commentKarma + context.linkKarma) >= threshold
        case .accountAgeYearsAtLeast(let years):
            return context.accountAgeYears >= years
        case .hasVerifiedEmail:
            return context.hasVerifiedEmail
        case .isGold:
            return context.isGold
        case .trophyCountAtLeast(let count):
            return context.trophyNames.count >= count
        case .hasTrophyNamed(let substring):
            return context.trophyNames.contains { $0.range(of: substring, options: .caseInsensitive) != nil }
        }
    }
}

/// A locally-computable subset of account-milestone signals, separate from
/// `AchievementCatalog` since these names and thresholds are original.
public enum BadgeCatalog {
    public static let all: [BadgeDefinition] = [
        BadgeDefinition(id: "verified_email", name: "Verified", description: "Verified your email address.", symbolName: "checkmark.seal.fill", criteria: .hasVerifiedEmail),
        BadgeDefinition(id: "gold_member", name: "Gilded", description: "Have Reddit Premium.", symbolName: "star.circle.fill", criteria: .isGold),
        BadgeDefinition(id: "karma_100", name: "Getting Started", description: "Reach 100 total karma.", symbolName: "arrow.up.circle", criteria: .totalKarmaAtLeast(100)),
        BadgeDefinition(id: "karma_1000", name: "Contributor", description: "Reach 1,000 total karma.", symbolName: "arrow.up.circle.fill", criteria: .totalKarmaAtLeast(1000)),
        BadgeDefinition(id: "karma_10000", name: "Prolific", description: "Reach 10,000 total karma.", symbolName: "flame.fill", criteria: .totalKarmaAtLeast(10000)),
        BadgeDefinition(id: "karma_100000", name: "Legendary", description: "Reach 100,000 total karma.", symbolName: "crown.fill", criteria: .totalKarmaAtLeast(100000)),
        BadgeDefinition(id: "comment_karma_1000", name: "Conversationalist", description: "Reach 1,000 comment karma.", symbolName: "bubble.left.and.bubble.right.fill", criteria: .commentKarmaAtLeast(1000)),
        BadgeDefinition(id: "link_karma_1000", name: "Curator", description: "Reach 1,000 post karma.", symbolName: "doc.text.fill", criteria: .linkKarmaAtLeast(1000)),
        BadgeDefinition(id: "account_age_1", name: "One Year In", description: "Account is at least a year old.", symbolName: "1.circle.fill", criteria: .accountAgeYearsAtLeast(1)),
        BadgeDefinition(id: "account_age_5", name: "Old Guard", description: "Account is at least 5 years old.", symbolName: "5.circle.fill", criteria: .accountAgeYearsAtLeast(5)),
        BadgeDefinition(id: "account_age_10", name: "Reddit Veteran", description: "Account is at least 10 years old.", symbolName: "10.circle.fill", criteria: .accountAgeYearsAtLeast(10)),
        BadgeDefinition(id: "trophy_collector", name: "Trophy Collector", description: "Have earned at least 3 Reddit trophies.", symbolName: "trophy.fill", criteria: .trophyCountAtLeast(3)),
        BadgeDefinition(id: "veteran_trophy", name: "Club Member", description: "Have a Reddit \"Year Club\" trophy.", symbolName: "medal.fill", criteria: .hasTrophyNamed("Year Club")),
    ]
}
