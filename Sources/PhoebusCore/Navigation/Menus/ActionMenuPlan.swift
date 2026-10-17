import Foundation

/// The rows each Action Menus menu offers for a post, comment or subreddit,
/// in the app's own order and then arranged by the user's layout (Reborn
/// "Action Menus", #1131). The ••• menus in the feed, on a post, on a
/// comment and in the moderator queue, and the Action Menus preview, all
/// draw their rows from these, so which rows exist and where they go is
/// decided once.
///
/// `main` is the menu's own rows; `moderator` is the moderator rows that
/// follow them (nil when the viewer doesn't moderate the subreddit).
public struct ActionMenuPlan: Equatable, Sendable {
    public let main: [String]
    public let moderator: [String]?

    public init(main: [String], moderator: [String]? = nil) {
        self.main = main
        self.moderator = moderator
    }
}

public extension ActionMenuPlan {
    /// A post's menu in a feed (context `post`): the ••• row button and
    /// touching and holding the post. Report always closes the menu and is
    /// not part of the layout.
    static func feedPost(author: String, signedInUsername: String?, isModerator: Bool, galleryImageCount: Int) -> ActionMenuPlan {
        var ids = ["save", "hide", "share", "copy-link"]
        if galleryImageCount > 1 { ids.append("save-all-media") }
        ids += ["crosspost", "remind-me", "mute-notifications", "filter-subreddit"]
        ids += PostMarkMenuPolicy.menuIDs(in: .postMenu, author: author,
                                          signedInUsername: signedInUsername, isModerator: isModerator)
        if isModerator || author == signedInUsername { ids.append("post-flair") }
        if PostInsightsParser.isEligible(author: author, currentUsername: signedInUsername) { ids.append("post-insights") }
        ids += ["media-download", "subscribe-actions"]
        return ActionMenuPlan(
            main: ActionMenuLayoutStore.arrange(ids, for: .post),
            moderator: isModerator
                ? moderatorPost(author: author, signedInUsername: signedInUsername, isModerator: true, includesNotes: false)
                : nil)
    }

    /// The post screen's ••• menu (context `post-detail`). The Moderator
    /// row opens the Moderator (Post) rows in `moderator`.
    static func postDetail(author: String, signedInUsername: String?, isModerator: Bool, isOwnPost: Bool,
                           isPostDeleted: Bool, isSelf: Bool, selftext: String?, otherDiscussionsAvailable: Bool,
                           summariesEnabled: Bool, floatingTabsEnabled: Bool) -> ActionMenuPlan {
        var ids = isModerator ? ["moderator"] : []
        ids += ["upvote", "downvote", "save", "reply", "author", "subreddit", "collapse-children",
                "select-text", "share", "share-image", "crosspost"]
        if otherDiscussionsAvailable { ids.append("other-discussions") }
        ids += ["find", "award", "copy-link", "remind-me"]
        if isSelf, let selftext, !selftext.isEmpty { ids += ["translate", "copy-text"] }
        if isOwnPost && !isPostDeleted {
            if isSelf { ids.append("edit") }
            ids.append("delete")
        }
        if summariesEnabled { ids.append("summarize") }
        if floatingTabsEnabled { ids.append("spec.FloatingTabs") }
        ids += PostMarkMenuPolicy.menuIDs(in: .postMenu, author: author,
                                          signedInUsername: signedInUsername, isModerator: isModerator)
        ids += ["mute-notifications", "report", "live-activity", "spec.DeletedComments"]
        if isOwnPost { ids.append("post-insights") }
        return ActionMenuPlan(
            main: ActionMenuLayoutStore.arrange(ids, for: .postDetail),
            moderator: isModerator
                ? moderatorPost(author: author, signedInUsername: signedInUsername, isModerator: true, includesNotes: true)
                : nil)
    }

    /// A comment's menu (context `comment`), shared by the long press and
    /// the byline's •••. The policy removes the rows a deleted, removed or
    /// restored comment can't offer, and the Moderator section with them.
    static func comment(policy: CommentInteractionPolicy, canShareAsImage: Bool, isModerator: Bool) -> ActionMenuPlan {
        var ids = ["upvote", "downvote", "reply", "quote", "save", "edit", "delete", "vote-insights",
                   "share", "copy-link", "copy-text"]
        if canShareAsImage { ids.append("share-image") }
        ids += ["copy-username", "tag-user", "translate", "award", "report", "remind-me", "mute-notifications"]
        let moderator = isModerator ? moderatorComment(allowing: policy.allowsMenuItem) : []
        return ActionMenuPlan(
            main: ActionMenuLayoutStore.arrange(ids.filter(policy.allowsMenuItem), for: .comment),
            moderator: moderator.isEmpty ? nil : moderator)
    }

    /// The Moderator (Post) rows. Your own post keeps Mark NSFW and Mark
    /// Spoiler in its ••• menu, so they only appear here for someone else's.
    /// The post screen's Moderator menu adds Mod Notes.
    static func moderatorPost(author: String, signedInUsername: String?, isModerator: Bool, includesNotes: Bool) -> [String] {
        let marks = PostMarkMenuPolicy.menuIDs(in: .moderatorMenu, author: author,
                                               signedInUsername: signedInUsername, isModerator: isModerator)
        let ids = ["mod-approve", "mod-remove", "mod-spam"] + marks
            + ["mod-distinguish", "mod-sticky", "mod-lock"] + (includesNotes ? ["mod-notes"] : [])
        return ActionMenuLayoutStore.arrange(ids, for: .moderatorPost)
    }

    /// The Moderator (Comment) rows.
    static func moderatorComment(allowing: (String) -> Bool = { _ in true }) -> [String] {
        let ids = ["mod-approve", "mod-remove", "mod-spam", "mod-distinguish", "mod-sticky", "mod-notes"]
        return ActionMenuLayoutStore.arrange(ids.filter(allowing), for: .moderatorComment)
    }

    /// The Moderator (Subreddit) menu: the rows this app can open, in Apollo's order.
    static func moderatorSubreddit() -> [String] {
        ActionMenuLayoutStore.arrange(["mod-mail", "mod-queue", "mod-log", "mod-reports", "mod-spam-queue",
                                       "mod-unmoderated", "mod-all-comments", "mod-traffic", "mod-ban-users",
                                       "mod-mute-users", "mod-rules", "mod-automoderator",
                                       "mod-approved-submitters", "mod-moderators"],
                                      for: .moderatorSubreddit)
    }
}
