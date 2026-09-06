import Foundation

/// A subscription changed, from anywhere: the header's Join pill, a •••
/// menu, the Subscriptions list, or an interactive post that subscribed
/// the user server-side. Posted by `RedditRepository.subscribe` (and the
/// Devvit check) so every surface agrees (Reborn #1264).
public struct SubscriptionChange: Sendable, Equatable {
    /// Display name, when known.
    public let name: String?
    /// `t5_` fullname, when known.
    public let fullname: String?
    public let subscribed: Bool

    public init(name: String? = nil, fullname: String? = nil, subscribed: Bool) {
        self.name = name
        self.fullname = fullname
        self.subscribed = subscribed
    }

    /// Whether this change is about the subreddit with this name/fullname.
    public func matches(name other: String?, fullname otherFullname: String?) -> Bool {
        if let name, let other, name.caseInsensitiveCompare(other) == .orderedSame { return true }
        if let fullname, let otherFullname, fullname == otherFullname { return true }
        return false
    }

    public static func post(_ change: SubscriptionChange) {
        NotificationCenter.default.post(name: .apolloSubscriptionsChanged, object: nil, userInfo: ["change": change])
    }

    public static func from(_ note: Notification) -> SubscriptionChange? {
        note.userInfo?["change"] as? SubscriptionChange
    }
}

public extension Notification.Name {
    static let apolloSubscriptionsChanged = Notification.Name("ApolloSubscriptionsChanged")
}

/// When to ask Reddit whether an interactive post just subscribed the
/// user (Reborn #1264 "Subscription sync"): 2, 5 and 12 seconds after the
/// last tap in the widget, at most 12 checks per subreddit in any 10
/// minutes.
public struct DevvitSubscriptionCheckLimiter: Sendable {
    public static let delays: [TimeInterval] = [2, 5, 12]
    public static let checksPerWindow = 12
    public static let window: TimeInterval = 600

    private var times: [String: [TimeInterval]] = [:]

    public init() {}

    /// Spends one check for `subreddit` at `now`, or returns false when
    /// its window is used up.
    public mutating func take(_ subreddit: String, now: TimeInterval) -> Bool {
        let key = subreddit.lowercased()
        var list = (times[key] ?? []).filter { now - $0 <= Self.window }
        guard list.count < Self.checksPerWindow else { times[key] = list; return false }
        list.append(now)
        times[key] = list
        return true
    }
}
