import Foundation

/// Apollo's Mark NSFW / Mark Spoiler on a post (`api/marknsfw`,
/// `api/unmarknsfw`, `api/spoiler`, `api/unspoiler`). Raw values are the
/// Action Menus catalogue ids.
public enum PostMark: String, CaseIterable, Sendable {
    case nsfw
    case spoiler

    public func isSet(on post: RedditPost) -> Bool {
        switch self {
        case .nsfw: return post.over18
        case .spoiler: return post.spoiler
        }
    }

    public func set(_ value: Bool, on post: inout RedditPost) {
        switch self {
        case .nsfw: post.over18 = value
        case .spoiler: post.spoiler = value
        }
    }

    public func path(marking: Bool) -> String {
        switch self {
        case .nsfw: return marking ? "/api/marknsfw" : "/api/unmarknsfw"
        case .spoiler: return marking ? "/api/spoiler" : "/api/unspoiler"
        }
    }

    /// The menu row, which states the action: "Mark NSFW" or "Unmark NSFW".
    public func title(marking: Bool) -> String {
        switch self {
        case .nsfw: return marking ? "Mark NSFW" : "Unmark NSFW"
        case .spoiler: return marking ? "Mark Spoiler" : "Unmark Spoiler"
        }
    }

    public var symbol: String {
        switch self {
        case .nsfw: return "exclamationmark.triangle"
        case .spoiler: return "eye.trianglebadge.exclamationmark"
        }
    }

    /// Apollo's failure wording ("Error marking NSFW.").
    public func failureMessage(marking: Bool) -> String {
        switch self {
        case .nsfw: return marking ? "Error marking NSFW." : "Error unmarking NSFW."
        case .spoiler: return marking ? "Error marking spoiler." : "Error unmarking spoiler."
        }
    }
}

/// Where a post's Mark NSFW / Mark Spoiler rows go. Reddit lets the
/// author and the subreddit's moderators change both marks.
public enum PostMarkMenuPolicy {
    public enum Placement: Equatable, Sendable {
        /// The post's own ••• menu (your own post).
        case postMenu
        /// The Moderator (Post) menu, beside Apollo's other moderator actions.
        case moderatorMenu
    }

    /// Your own post keeps them in its ••• menu even where you moderate,
    /// so they never show twice.
    public static func placement(author: String, signedInUsername: String?, isModerator: Bool) -> Placement? {
        if let signedInUsername, !signedInUsername.isEmpty,
           author.caseInsensitiveCompare(signedInUsername) == .orderedSame {
            return .postMenu
        }
        return isModerator ? .moderatorMenu : nil
    }

    /// The rows `placement` gets for this post, in catalogue order.
    public static func menuIDs(in placement: Placement, author: String, signedInUsername: String?, isModerator: Bool) -> [String] {
        guard self.placement(author: author, signedInUsername: signedInUsername, isModerator: isModerator) == placement
        else { return [] }
        return PostMark.allCases.map(\.rawValue)
    }
}

/// The NSFW and Spoiler marks a new post is submitted with.
public struct PostSubmitMarks: Equatable, Sendable {
    public var nsfw: Bool
    public var spoiler: Bool

    public init(nsfw: Bool = false, spoiler: Bool = false) {
        self.nsfw = nsfw
        self.spoiler = spoiler
    }

    /// For the form-encoded `/api/submit`.
    public var formParameters: [String: String] {
        ["nsfw": nsfw ? "true" : "false", "spoiler": spoiler ? "true" : "false"]
    }

    /// For the JSON submit endpoints (gallery and poll).
    public var jsonParameters: [String: Bool] {
        ["nsfw": nsfw, "spoiler": spoiler]
    }
}

/// A post's NSFW or Spoiler mark changed in this app, sent as
/// `.apolloPostMarkChanged` so every screen showing the post follows.
public struct PostMarkChange: Equatable, Sendable {
    public let fullname: String
    public let mark: PostMark
    public let value: Bool

    public init(fullname: String, mark: PostMark, value: Bool) {
        self.fullname = fullname
        self.mark = mark
        self.value = value
    }

    public init?(_ note: Notification) {
        guard note.name == .apolloPostMarkChanged,
              let fullname = note.object as? String,
              let mark = (note.userInfo?["mark"] as? String).flatMap(PostMark.init(rawValue:)),
              let value = note.userInfo?["value"] as? Bool else { return nil }
        self.init(fullname: fullname, mark: mark, value: value)
    }

    public var notification: Notification {
        Notification(name: .apolloPostMarkChanged, object: fullname,
                     userInfo: ["mark": mark.rawValue, "value": value])
    }

    /// Applies the change if `post` is the one it names.
    @discardableResult
    public func apply(to post: inout RedditPost) -> Bool {
        guard post.name == fullname else { return false }
        mark.set(value, on: &post)
        return true
    }
}

public extension Notification.Name {
    static let apolloPostMarkChanged = Notification.Name("ApolloPostMarkChangedNotification")
}
