import SwiftUI
import PhoebusCore

/// What a row of a comment's menu can do. The comment performs them; the
/// Action Menus preview performs none.
enum CommentMenuAction {
    case upvote, downvote, reply, quote, save, edit, delete, voteInsights, copyLink, copyText
    case shareImage, copyUsername, tagUser, translate, award, report, remindMe, toggleMute
    case moderator(CommentModeratorAction)
}

enum CommentModeratorAction {
    case approve, remove, spam, distinguish, sticky, notes
}

/// What a comment menu's rows depend on: the comment, who is looking at it
/// and the row's own state.
struct CommentMenuFacts {
    var comment: RedditComment
    /// What the comment offers, and the author and text it shows.
    var policy: CommentInteractionPolicy
    var canShareAsImage: Bool
    var isModerator: Bool
    var isSaved: Bool
    var isMuted: Bool
    var isDistinguished: Bool
    var isStickied: Bool
}

/// A comment's ••• menu, shared by the long press and the byline "..."
/// button. Entries are listed in the app's order, then arranged by the
/// user's Action Menus layout (Reborn #1131): ids from `ActionMenuCatalog`
/// can be moved or hidden; this app's extra rows (Quote, Copy Link…)
/// travel with the entry before them.
///
/// `facts` is read when the menu's content is built, so the saved, muted and
/// moderator rows show the state at that moment, as the rows did when they read
/// the comment row directly.
struct CommentActionMenuContent: View {
    private let makeFacts: () -> CommentMenuFacts
    var isPreview = false
    /// False for the Action Menus preview of the Moderator (Comment) menu,
    /// which shows only the moderator rows.
    var showsMain = true
    let perform: (CommentMenuAction) -> Void

    init(facts: @autoclosure @escaping () -> CommentMenuFacts, isPreview: Bool = false, showsMain: Bool = true,
         perform: @escaping (CommentMenuAction) -> Void) {
        makeFacts = facts
        self.isPreview = isPreview
        self.showsMain = showsMain
        self.perform = perform
    }

    var body: some View {
        CommentMenuRows(facts: makeFacts(), isPreview: isPreview, showsMain: showsMain, perform: perform)
    }
}

private struct CommentMenuRows: View {
    let facts: CommentMenuFacts
    let isPreview: Bool
    let showsMain: Bool
    let perform: (CommentMenuAction) -> Void

    private var comment: RedditComment { facts.comment }

    var body: some View {
        let plan = ActionMenuPlan.comment(
            policy: facts.policy, canShareAsImage: facts.canShareAsImage, isModerator: facts.isModerator)
        if showsMain {
            ForEach(plan.main, id: \.self) { id in
                row(id)
            }
        }
        if let moderator = plan.moderator {
            if showsMain { Divider() }
            ForEach(moderator, id: \.self) { id in
                row(id)
            }
        }
    }

    @ViewBuilder
    private func row(_ id: String) -> some View {
        switch id {
        case "upvote":
            Button { perform(.upvote) } label: { Label("Upvote", systemImage: "arrow.up") }
        case "downvote":
            Button { perform(.downvote) } label: { Label("Downvote", systemImage: "arrow.down") }
        case "reply":
            Button { perform(.reply) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        case "quote":
            // Apollo's select-text mode "Quote" action.
            Button { perform(.quote) } label: { Label("Quote", systemImage: "quote.opening") }
        case "save":
            Button { perform(.save) } label: {
                Label(facts.isSaved ? "Unsave" : "Save", systemImage: facts.isSaved ? "bookmark.fill" : "bookmark")
            }
        case "edit":
            Button { perform(.edit) } label: { Label("Edit", systemImage: "pencil") }
        case "delete":
            Button(role: .destructive) { perform(.delete) } label: { Label("Delete", systemImage: "trash") }
        case "vote-insights":
            // Reborn "Comment Insights" (author-only /commentstats).
            Button { perform(.voteInsights) } label: { Label("Vote Insights", systemImage: "chart.bar") }
        case "share":
            MenuShareLink(item: .url(comment.shareURL()), isPreview: isPreview)
        case "copy-link":
            // Apollo's CopyURLActivity: the comment's own permalink.
            Button { perform(.copyLink) } label: { Label("Copy Link", systemImage: "link") }
        case "copy-text":
            Button { perform(.copyText) } label: { Label("Copy Text", systemImage: "doc.on.doc") }
        case "share-image":
            if facts.canShareAsImage {
                Button { perform(.shareImage) } label: { Label("Share as Image", systemImage: "photo.badge.plus") }
            }
        case "copy-username":
            // Reborn: Copy Username (from the avatar's hold menu).
            Button { perform(.copyUsername) } label: { Label("Copy Username", systemImage: "doc.on.doc") }
        case "tag-user":
            // Phoebus-only user tags (`UserTags`).
            UserTagMenuItem(username: facts.policy.author) { perform(.tagUser) }
        case "translate":
            Button { perform(.translate) } label: { Label("Translate", systemImage: "character.bubble") }
        case "award":
            Button { perform(.award) } label: { Label("Give Award", systemImage: "medal") }
        case "report":
            Button(role: .destructive) { perform(.report) } label: { Label("Report", systemImage: "flag") }
        case "remind-me":
            // Reborn "Action Menus" (#1368): Remind Me In… is a catalogued row.
            Button { perform(.remindMe) } label: { Label("Remind Me In…", systemImage: "alarm") }
        case "mute-notifications":
            // On-device suppression list: Reddit's API has no endpoint.
            Button { perform(.toggleMute) } label: {
                Label(facts.isMuted ? "Unmute Notifications" : "Mute Notifications", systemImage: facts.isMuted ? "bell" : "bell.slash")
            }
        case "mod-approve":
            Button { perform(.moderator(.approve)) } label: { Label("Approve", systemImage: "checkmark.shield") }
        case "mod-remove":
            Button(role: .destructive) { perform(.moderator(.remove)) } label: { Label("Remove", systemImage: "xmark.shield") }
        case "mod-spam":
            Button(role: .destructive) { perform(.moderator(.spam)) } label: {
                Label("Mark as Spam", systemImage: "exclamationmark.shield")
            }
        case "mod-distinguish":
            Button { perform(.moderator(.distinguish)) } label: {
                Label(facts.isDistinguished ? "Undistinguish" : "Distinguish", systemImage: "shield.lefthalf.filled")
            }
        case "mod-sticky":
            Button { perform(.moderator(.sticky)) } label: { Label(facts.isStickied ? "Unsticky" : "Sticky", systemImage: "pin") }
        case "mod-notes":
            if comment.subreddit != nil, comment.author != "[deleted]" {
                Button { perform(.moderator(.notes)) } label: { Label("Mod Notes", systemImage: "note.text") }
                    .accessibilityIdentifier("comment.menu.modNotes")
            }
        default:
            EmptyView()
        }
    }
}
