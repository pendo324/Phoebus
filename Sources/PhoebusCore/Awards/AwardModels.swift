import Foundation

/// What a thread row shows for its awards: Reddit's featured award icon and
/// the total count, as the Shreddit comment tree reports them for one post or
/// comment (`<award-button>`).
public struct AwardBadge: Sendable, Hashable {
    /// The post or comment fullname.
    public let thingID: String
    public var count: Int
    public var awardID: String?
    public var iconURL: URL?
    public var hasPaidAward: Bool

    public init(thingID: String, count: Int, awardID: String?, iconURL: URL?, hasPaidAward: Bool) {
        self.thingID = thingID
        self.count = count
        self.awardID = awardID
        self.iconURL = iconURL
        self.hasPaidAward = hasPaidAward
    }

    /// The badge once the user has given `award`, without refetching. The
    /// icon changes only where the answer is certain: a paid award takes over
    /// from a free one (Reddit features the paid award), and an unawarded
    /// thing shows the award it just got. Between two paid awards the winner
    /// depends on gold totals only the leaderboard has, so the icon stays.
    public func givingAward(_ award: AwardOrderResult) -> AwardBadge {
        var next = self
        next.count += 1
        let isPaid = award.goldPrice > 0
        if count == 0 || (isPaid && !hasPaidAward) {
            next.awardID = award.awardID
            next.iconURL = award.iconURL
        }
        next.hasPaidAward = hasPaidAward || isPaid
        return next
    }
}

/// One row of the award leaderboard: an award, how often it was given and the
/// gold behind it.
public struct AwardTally: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let count: Int
    /// Reddit's gold total for this award (count × price); 0 for a free award.
    public let gold: Int
    public let iconURL: URL?

    public var isFree: Bool { gold <= 0 }

    public init(id: String, name: String, count: Int, gold: Int, iconURL: URL?) {
        self.id = id
        self.name = name
        self.count = count
        self.gold = gold
        self.iconURL = iconURL
    }
}

/// A "Top Awarders" row; `username` is nil for an anonymous giver.
public struct AwardGiver: Sendable, Hashable {
    public let username: String?
    public let gold: Int

    public init(username: String?, gold: Int) {
        self.username = username
        self.gold = gold
    }
}

/// The parsed award leaderboard of one post or comment.
public struct AwardLeaderboard: Sendable, Equatable {
    public var totalAwards: Int?
    public var totalGold: Int?
    /// In the leaderboard's own order.
    public var tallies: [AwardTally]
    public var topAwarders: [AwardGiver]

    public init(totalAwards: Int?, totalGold: Int?, tallies: [AwardTally], topAwarders: [AwardGiver]) {
        self.totalAwards = totalAwards
        self.totalGold = totalGold
        self.tallies = tallies
        self.topAwarders = topAwarders
    }

    public var featured: AwardTally? { AwardSummary.featured(from: tallies) }
}

/// Which award a post or comment features.
public enum AwardSummary {
    /// Phoebus's rule for the award shown first. A paid award wins: the one
    /// with the most gold behind it, then the more often given, then the
    /// earlier in the leaderboard. With only free awards, the most often
    /// given, ties to the earlier. No award, no result.
    public static func featured(from tallies: [AwardTally]) -> AwardTally? {
        let given = tallies.enumerated().filter { $0.element.count > 0 }
        let paid = given.filter { !$0.element.isFree }
        if let best = paid.min(by: { lhs, rhs in
            if lhs.element.gold != rhs.element.gold { return lhs.element.gold > rhs.element.gold }
            if lhs.element.count != rhs.element.count { return lhs.element.count > rhs.element.count }
            return lhs.offset < rhs.offset
        }) {
            return best.element
        }
        return given.min(by: { lhs, rhs in
            if lhs.element.count != rhs.element.count { return lhs.element.count > rhs.element.count }
            return lhs.offset < rhs.offset
        })?.element
    }
}

/// One award the picker offers, from the award dialog's catalogue.
public struct AwardCatalogueEntry: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// Gold the award costs; 0 for a free award.
    public let goldPrice: Int
    public let iconURL: URL?
    public let isQuickGive: Bool

    public var isFree: Bool { goldPrice <= 0 }

    public init(id: String, name: String, goldPrice: Int, iconURL: URL?, isQuickGive: Bool) {
        self.id = id
        self.name = name
        self.goldPrice = goldPrice
        self.iconURL = iconURL
        self.isQuickGive = isQuickGive
    }
}

/// The award dialog for one post or comment: what can be given, the user's
/// Gold and where the leaderboard lives.
public struct AwardDialog: Sendable, Equatable {
    public var catalogue: [AwardCatalogueEntry]
    /// The user's Gold, when the dialog states it.
    public var goldBalance: Int?
    /// The signed leaderboard partial the dialog points at.
    public var leaderboardURL: URL?

    public init(catalogue: [AwardCatalogueEntry], goldBalance: Int?, leaderboardURL: URL?) {
        self.catalogue = catalogue
        self.goldBalance = goldBalance
        self.leaderboardURL = leaderboardURL
    }

    /// Whether the user can pay for `entry` with the Gold they have. Unknown
    /// when the dialog states no balance; Reddit's answer decides then.
    public func canAfford(_ entry: AwardCatalogueEntry) -> Bool? {
        if entry.isFree { return true }
        guard let goldBalance else { return nil }
        return goldBalance >= entry.goldPrice
    }
}

/// What Reddit confirmed after `CreateAwardOrder`.
public struct AwardOrderResult: Sendable, Equatable {
    public let awardID: String
    public let name: String
    public let goldPrice: Int
    public let iconURL: URL?

    public init(awardID: String, name: String, goldPrice: Int, iconURL: URL?) {
        self.awardID = awardID
        self.name = name
        self.goldPrice = goldPrice
        self.iconURL = iconURL
    }
}
