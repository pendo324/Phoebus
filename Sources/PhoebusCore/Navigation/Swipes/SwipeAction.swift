import Foundation

/// Configurable swipe action, reimplementing Apollo's per-row swipe
/// gesture customization (Settings > Gestures). Posts, Comments, Inbox,
/// and Profile Posts/Comments each have their own independent set of
/// four slots (left-short, left-long, right-short, right-long) with
/// their own defaults.
public enum SwipeAction: String, CaseIterable, Sendable, Codable {
    case upvote
    case downvote
    case save
    case reply
    case share
    case hide
    /// Comments-only: collapses the top-level thread this comment belongs to
    /// (Apollo's default for the right-short-swipe slot).
    case collapseTop
    /// Inbox-only: marks the message read/unread (Apollo's default for the
    /// right-short-swipe slot).
    case markRead
    /// Folds the swiped comment itself (stock `collapse`).
    case collapse
    /// Hides every post above this one in the feed (stock `hide-above`).
    case hidePostsAbove
    /// Scrolls to the comment this one replies to (stock `parent-comment`).
    case parentComment
    case author
    case subreddit
    /// The item's text in a selectable sheet (stock `select-mode`).
    case selectText
    case none

    public var systemImage: String {
        switch self {
        case .upvote: return "arrow.up"
        case .downvote: return "arrow.down"
        case .save: return "bookmark"
        case .reply: return "arrowshape.turn.up.left"
        case .share: return "square.and.arrow.up"
        case .hide: return "eye.slash"
        // `chevron.up.to.line` is not an SF Symbol and renders as nothing;
        // `arrow.up.to.line` ships in SF Symbols 2+.
        case .collapseTop: return "arrow.up.to.line"
        case .markRead: return "envelope.open"
        case .collapse: return "chevron.up"
        case .hidePostsAbove: return "eye.slash.circle"
        case .parentComment: return "arrow.up.message"
        case .author: return "person.crop.circle"
        case .subreddit: return "r.circle"
        case .selectText: return "selection.pin.in.out"
        case .none: return "circle.slash"
        }
    }

    public var tintColor: String {
        switch self {
        case .upvote: return "orange"
        case .downvote: return "blue"
        case .save: return "green"
        case .reply: return "purple"
        case .share: return "gray"
        case .hide: return "red"
        case .collapseTop: return "gray"
        case .markRead: return "blue"
        case .collapse: return "gray"
        case .hidePostsAbove: return "red"
        case .parentComment: return "blue"
        case .author: return "green"
        case .subreddit: return "purple"
        case .selectText: return "gray"
        case .none: return "gray"
        }
    }

    public var displayName: String {
        switch self {
        case .collapseTop: return "Collapse Top"
        case .markRead: return "Mark Read"
        case .hidePostsAbove: return "Hide Posts Above"
        case .parentComment: return "Parent Comment"
        case .selectText: return "Select Text"
        default: return rawValue.capitalized
        }
    }
}

/// The four configurable swipe slots for one screen, matching
/// Apollo's left-short-swipe / left-long-swipe / right-short-swipe /
/// right-long-swipe settings keys.
public struct SwipeActionSettings: Codable, Sendable, Equatable {
    public var leftShort: SwipeAction
    public var leftLong: SwipeAction
    public var rightShort: SwipeAction
    public var rightLong: SwipeAction

    /// Apollo's Posts-screen default: left short = Upvote, left long =
    /// Downvote, right short = Reply, right long = Save.
    public static let postsDefault = SwipeActionSettings(
        leftShort: .upvote,
        leftLong: .downvote,
        rightShort: .reply,
        rightLong: .save
    )

    /// Apollo's Comments-screen default.
    public static let commentsDefault = SwipeActionSettings(
        leftShort: .upvote,
        leftLong: .downvote,
        rightShort: .collapseTop,
        rightLong: .reply
    )

    /// Apollo's Inbox-screen default.
    public static let inboxDefault = SwipeActionSettings(
        leftShort: .upvote,
        leftLong: .downvote,
        rightShort: .markRead,
        rightLong: .reply
    )

    /// Same as Posts.
    public static let profilePostsDefault = SwipeActionSettings(
        leftShort: .upvote,
        leftLong: .downvote,
        rightShort: .reply,
        rightLong: .save
    )

    /// Save/reply are swapped relative to every other screen.
    public static let profileCommentsDefault = SwipeActionSettings(
        leftShort: .upvote,
        leftLong: .downvote,
        rightShort: .save,
        rightLong: .reply
    )

    /// Generic alias of `postsDefault` for unmigrated call sites.
    public static let `default` = postsDefault

    public init(leftShort: SwipeAction, leftLong: SwipeAction, rightShort: SwipeAction, rightLong: SwipeAction) {
        self.leftShort = leftShort
        self.leftLong = leftLong
        self.rightShort = rightShort
        self.rightLong = rightLong
    }
}

/// One of the four swipe slots, with the verbatim row titles the
/// Gestures screen uses: "Left Short Swipe" / "Left Long Swipe" /
/// "Right Short Swipe" / "Right Long Swipe".
public enum SwipeSlot: String, CaseIterable, Sendable {
    case leftShort
    case leftLong
    case rightShort
    case rightLong

    public var title: String {
        switch self {
        case .leftShort: return "Left Short Swipe"
        case .leftLong: return "Left Long Swipe"
        case .rightShort: return "Right Short Swipe"
        case .rightLong: return "Right Long Swipe"
        }
    }

    public func value(in settings: SwipeActionSettings) -> SwipeAction {
        switch self {
        case .leftShort: return settings.leftShort
        case .leftLong: return settings.leftLong
        case .rightShort: return settings.rightShort
        case .rightLong: return settings.rightLong
        }
    }

    public func set(_ action: SwipeAction, in settings: inout SwipeActionSettings) {
        switch self {
        case .leftShort: settings.leftShort = action
        case .leftLong: settings.leftLong = action
        case .rightShort: settings.rightShort = action
        case .rightLong: settings.rightLong = action
        }
    }
}

/// Which screen a `SwipeActionSettings` applies to; each persists
/// independently.
public enum SwipeActionScreen: String, CaseIterable, Sendable {
    case posts
    case comments
    case inbox
    case profilePosts
    case profileComments

    public var displayName: String {
        switch self {
        case .posts: return "Posts"
        case .comments: return "Comments"
        case .inbox: return "Inbox"
        case .profilePosts: return "Profile Posts"
        case .profileComments: return "Profile Comments"
        }
    }

    /// The actions Apollo offers on this screen, in its order.
    public var availableActions: [SwipeAction] {
        switch self {
        case .posts: return [.upvote, .downvote, .save, .reply, .hide, .hidePostsAbove, .author, .subreddit, .share]
        case .comments: return [.upvote, .downvote, .save, .reply, .collapseTop, .collapse, .parentComment, .author, .selectText, .share]
        case .inbox: return [.markRead, .upvote, .downvote, .reply, .author, .subreddit, .selectText, .share]
        case .profilePosts: return [.upvote, .downvote, .save, .reply, .subreddit, .share]
        case .profileComments: return [.upvote, .downvote, .save, .reply, .selectText, .share]
        }
    }

    var defaultSettings: SwipeActionSettings {
        switch self {
        case .posts: return .postsDefault
        case .comments: return .commentsDefault
        case .inbox: return .inboxDefault
        case .profilePosts: return .profilePostsDefault
        case .profileComments: return .profileCommentsDefault
        }
    }
}

/// Persists swipe action configuration per screen (see
/// `SwipeActionScreen`), mirroring Apollo's UserDefaults persistence.
public enum SwipeActionStore {
    private static func key(for screen: SwipeActionScreen) -> String {
        "com.pendo324.Phoebus.swipeActionSettings.\(screen.rawValue)"
    }

    private static let storages: [SwipeActionScreen: SettingsStore<SwipeActionSettings>] =
        Dictionary(uniqueKeysWithValues: SwipeActionScreen.allCases.map { screen in
            (screen, SettingsStore(key: key(for: screen)) { screen.defaultSettings })
        })

    public static func storage(for screen: SwipeActionScreen) -> SettingsStore<SwipeActionSettings> {
        storages[screen]!
    }

    public static func load(for screen: SwipeActionScreen) -> SwipeActionSettings {
        storage(for: screen).load()
    }

    public static func save(_ settings: SwipeActionSettings, for screen: SwipeActionScreen) {
        storage(for: screen).save(settings)
    }

    public static func restoreDefaults(for screen: SwipeActionScreen) {
        save(screen.defaultSettings, for: screen)
    }

    // MARK: - Posts-screen shorthands, used by the backup bundle's
    // pre-per-screen `swipeActionSettings` field.

    public static func load() -> SwipeActionSettings { load(for: .posts) }

    public static func save(_ settings: SwipeActionSettings) { save(settings, for: .posts) }

    public static func restoreDefaults() { restoreDefaults(for: .posts) }
}
