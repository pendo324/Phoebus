import Foundation

/// What the Gestures & Haptics preview shows. Phoebus-only; neither Apollo nor
/// Reborn previews a row swipe.
///
/// The preview row is swiped by the real swipe modifier, whose decisions are
/// `SwipeRowPolicy`'s; these are the ones around it, kept here so they can be
/// asserted: what each side reads in the labelled strip, and what the
/// preview's release handler does (nothing but name the action).
public enum SwipePreviewPolicy {
    /// What one side reads in the strip under the row.
    public enum Strip: Equatable, Sendable {
        case actions(short: SwipeAction, long: SwipeAction)
        /// The side's setting is off and the drag goes to page navigation.
        case pageSwipe(String)
        case none
    }

    public static func strip(for side: SwipeRowPolicy.Side, settings: SwipeActionSettings, navigation: NavigationGestureSettings) -> Strip {
        switch side {
        case .left:
            if navigation.disableLeftSwipeGestureActions { return .pageSwipe("Swipe back") }
            return settings.leftShort == .none && settings.leftLong == .none
                ? .none : .actions(short: settings.leftShort, long: settings.leftLong)
        case .right:
            if navigation.disableRightSwipeGestureActions { return .pageSwipe("Swipe forward") }
            return settings.rightShort == .none && settings.rightLong == .none
                ? .none : .actions(short: settings.rightShort, long: settings.rightLong)
        }
    }

    /// The preview's release handler. The row springs back and the action is
    /// never run: no vote, save, reply or hide is sent, and nothing is written.
    /// It only returns the text for the label that names the action.
    public static func release(_ action: SwipeAction) -> String? {
        action == .none ? nil : "Would \(action.displayName)"
    }

    /// The accessibility summary of the card: each side's actions in words.
    public static func summary(settings: SwipeActionSettings, navigation: NavigationGestureSettings) -> String {
        SwipeRowPolicy.Side.allCases.map { side in
            switch strip(for: side, settings: settings, navigation: navigation) {
            case .actions(let short, let long):
                return "\(side.title) swipe: \(short.displayName), then \(long.displayName) past the trigger point."
            case .pageSwipe(let text):
                return "\(side.title) swipe: \(text)."
            case .none:
                return "\(side.title) swipe: nothing."
            }
        }.joined(separator: " ")
    }
}

/// The four choices on the preview's segmented control. Profile Posts and
/// Profile Comments share the last one: it shows whichever of the two was
/// changed last.
public enum SwipePreviewSegment: String, CaseIterable, Sendable {
    case posts
    case comments
    case inbox
    case profile

    public var title: String {
        switch self {
        case .posts: return "Posts"
        case .comments: return "Comments"
        case .inbox: return "Inbox"
        case .profile: return "Profile"
        }
    }

    public init(screen: SwipeActionScreen) {
        switch screen {
        case .posts: self = .posts
        case .comments: self = .comments
        case .inbox: self = .inbox
        case .profilePosts, .profileComments: self = .profile
        }
    }

    /// The screen a tap on the segment shows; Profile keeps Profile Comments if
    /// that is what it was showing.
    public func screen(keeping current: SwipeActionScreen) -> SwipeActionScreen {
        switch self {
        case .posts: return .posts
        case .comments: return .comments
        case .inbox: return .inbox
        case .profile: return current == .profileComments ? .profileComments : .profilePosts
        }
    }

    /// The screen whose slots just changed, so the card can switch to it: set
    /// only when exactly one screen differs. Restore Defaults changes several
    /// at once and keeps the card where it is.
    public static func changedScreen(from old: [SwipeActionScreen: SwipeActionSettings],
                                     to new: [SwipeActionScreen: SwipeActionSettings]) -> SwipeActionScreen? {
        let changed = SwipeActionScreen.allCases.filter { old[$0] != new[$0] }
        return changed.count == 1 ? changed[0] : nil
    }
}
