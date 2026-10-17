import Foundation

/// The Action Menus preview (Phoebus-only; neither Apollo nor Reborn previews
/// a menu): a sample post or comment whose ••• opens the same menu the app
/// shows, in the layout being edited. These decide which switches the card
/// offers and who the sample is seen by, so the menu shows the rows that only
/// appear for your own post, a moderator, and so on.
public enum ActionMenuPreviewPolicy {
    public enum Toggle: Hashable, Sendable {
        /// Your own post or comment: Edit, Delete, Insights, the marks.
        case yourItem
        /// A moderator of the sample's subreddit.
        case moderator
    }

    /// The switches a menu's card offers. A moderator menu is the moderator
    /// variant already; the subreddit menu has no own-item rows.
    public static func toggles(for context: ActionMenuContext) -> [Toggle] {
        switch context {
        case .feed: return [.moderator]
        case .post, .postDetail, .comment: return [.yourItem, .moderator]
        case .moderatorSubreddit, .moderatorPost, .moderatorComment: return []
        }
    }

    public static func title(of toggle: Toggle, in context: ActionMenuContext) -> String {
        switch toggle {
        case .yourItem: return context == .comment ? "Your comment" : "Your post"
        case .moderator: return "Moderator"
        }
    }

    /// The menus that open on a touch and hold as well as on their •••.
    public static func opensOnHold(_ context: ActionMenuContext) -> Bool {
        switch context {
        case .post, .postDetail, .comment, .moderatorPost, .moderatorComment: return true
        case .feed, .moderatorSubreddit: return false
        }
    }

    /// Who is looking at the sample: its author with "Your post" on, else
    /// someone else.
    public static func signedInUsername(yourItem: Bool) -> String {
        yourItem ? SettingsPreviewSample.postAuthor : SettingsPreviewSample.ownUsername
    }

    /// The moderator menus always show their moderator rows.
    public static func isModerator(_ context: ActionMenuContext, moderator: Bool) -> Bool {
        context.isModerator || moderator
    }
}
