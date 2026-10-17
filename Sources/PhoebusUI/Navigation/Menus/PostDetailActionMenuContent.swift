import SwiftUI
import PhoebusCore

/// What a row of the post screen's ••• menu can do. The post screen
/// performs them; the Action Menus preview performs none.
enum PostDetailMenuAction {
    case upvote, downvote, save, reply, viewProfile, copyUsername, viewSubreddit
    case collapseChildren, selectText, shareImage, crosspost, otherDiscussions, findInComments
    case award, copyLink, remindMe, translate, copyText, edit, delete, summarize, keepInFloatingTab
    case toggleMute, report, liveActivity, deletedComments, insights
    case moderator(PostModeratorAction)
}

/// What the post screen's ••• rows depend on: the post, who is looking at
/// it and the screen's own state.
struct PostDetailMenuFacts {
    var post: RedditPost
    /// The post with this session's Mark NSFW / Mark Spoiler changes.
    var markedPost: RedditPost
    var signedInUsername: String?
    var isModerator: Bool
    var isOwnPost: Bool
    var isPostDeleted: Bool
    var summariesEnabled: Bool
    var floatingTabsEnabled: Bool
    var isSaved: Bool
    var isMuted: Bool
    var anyChildCollapsed: Bool
    var isKeptInFloatingTab: Bool
    var liveActivityRunning: Bool
    var deletedCommentsRecoveryActive: Bool
    var moderator: PostModeratorMenuState
}

/// The post screen's ••• menu, and the menu a touch and hold on the post
/// opens. Entries are in the app's order, arranged by the user's Action
/// Menus layout for the comments view (Reborn #1131, context `post-detail`).
///
/// `facts` is read when the menu's content is built, not when the screen's
/// toolbar is, so the saved, muted, kept-in-a-tab and live-activity rows show
/// the state at that moment, as the rows did when they read the screen directly.
struct PostDetailActionMenuContent: View {
    private let makeFacts: () -> PostDetailMenuFacts
    let repository: RedditRepository
    var isPreview = false
    let perform: (PostDetailMenuAction) -> Void

    init(facts: @autoclosure @escaping () -> PostDetailMenuFacts, repository: RedditRepository,
         isPreview: Bool = false, perform: @escaping (PostDetailMenuAction) -> Void) {
        makeFacts = facts
        self.repository = repository
        self.isPreview = isPreview
        self.perform = perform
    }

    var body: some View {
        PostDetailMenuRows(facts: makeFacts(), makeFacts: makeFacts, repository: repository,
                           isPreview: isPreview, perform: perform)
    }
}

/// The Moderator (Post) menu under the post screen's Moderator row. Its rows
/// are built when the submenu opens, so they read the state then.
private struct PostDetailModeratorMenu: View {
    let makeFacts: () -> PostDetailMenuFacts
    let repository: RedditRepository
    let isPreview: Bool
    let perform: (PostDetailMenuAction) -> Void

    var body: some View {
        let facts = makeFacts()
        ForEach(ActionMenuPlan.moderatorPost(author: facts.post.author, signedInUsername: facts.signedInUsername,
                                             isModerator: facts.isModerator, includesNotes: true), id: \.self) { id in
            PostModeratorMenuRow(id: id, post: facts.markedPost, repository: repository, state: facts.moderator,
                                 markIdentifierPrefix: "postDetail.moderator", isPreview: isPreview) {
                perform(.moderator($0))
            }
        }
    }
}

private struct PostDetailMenuRows: View {
    let facts: PostDetailMenuFacts
    let makeFacts: () -> PostDetailMenuFacts
    let repository: RedditRepository
    let isPreview: Bool
    let perform: (PostDetailMenuAction) -> Void

    private var post: RedditPost { facts.post }

    private var plan: ActionMenuPlan {
        ActionMenuPlan.postDetail(
            author: post.author, signedInUsername: facts.signedInUsername, isModerator: facts.isModerator,
            isOwnPost: facts.isOwnPost, isPostDeleted: facts.isPostDeleted, isSelf: post.isSelf, selftext: post.selftext,
            otherDiscussionsAvailable: OtherDiscussions.isAvailable(for: post),
            summariesEnabled: facts.summariesEnabled, floatingTabsEnabled: facts.floatingTabsEnabled)
    }

    var body: some View {
        ForEach(plan.main, id: \.self) { id in
            row(id)
        }
    }

    /// The Moderator row: the Moderator (Post) menu, arranged by its layout.
    private var moderatorMenu: some View {
        Menu {
            PostDetailModeratorMenu(makeFacts: makeFacts, repository: repository, isPreview: isPreview, perform: perform)
        } label: { Label("Moderator", systemImage: "shield") }
        .accessibilityIdentifier("postDetail.menu.moderator")
    }

    @ViewBuilder
    private func row(_ id: String) -> some View {
        switch id {
        case "moderator":
            moderatorMenu
        case "upvote":
            Button { perform(.upvote) } label: { Label("Upvote", systemImage: "arrow.up") }
                .accessibilityIdentifier("postDetail.menu.upvote")
        case "downvote":
            Button { perform(.downvote) } label: { Label("Downvote", systemImage: "arrow.down") }
                .accessibilityIdentifier("postDetail.menu.downvote")
        case "save":
            Button { perform(.save) } label: {
                Label(facts.isSaved ? "Unsave" : "Save", systemImage: facts.isSaved ? "bookmark.fill" : "bookmark")
            }
            .accessibilityIdentifier("postDetail.menu.save")
        case "reply":
            Button { perform(.reply) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                .accessibilityIdentifier("postDetail.menu.reply")
        case "author":
            // Labelled with the name itself, opening a submenu.
            Menu {
                Button { perform(.viewProfile) } label: { Label("View Profile", systemImage: "person.crop.circle") }
                Button { perform(.copyUsername) } label: { Label("Copy Username", systemImage: "doc.on.doc") }
            } label: { Label(post.author, systemImage: "person.circle") }
            .accessibilityIdentifier("postDetail.menu.author")
        case "subreddit":
            Menu {
                Button { perform(.viewSubreddit) } label: {
                    Label("View Subreddit", systemImage: "list.bullet.below.rectangle")
                }
            } label: { Label(post.subreddit, systemImage: "house") }
            .accessibilityIdentifier("postDetail.menu.subreddit")
        case "collapse-children":
            Button { perform(.collapseChildren) } label: {
                Label(facts.anyChildCollapsed ? "Expand Child Comments" : "Collapse Child Comments",
                      systemImage: facts.anyChildCollapsed ? "chevron.down.2" : "chevron.up.2")
            }
            .accessibilityIdentifier("postDetail.menu.collapseChildComments")
        case "select-text":
            Button { perform(.selectText) } label: { Label("Select Text", systemImage: "selection.pin.in.out") }
                .accessibilityIdentifier("postDetail.menu.selectText")
        case "share":
            MenuShareLink(item: .text(post.shareText()), isPreview: isPreview)
                .accessibilityIdentifier("postDetail.menu.share")
        case "post-insights":
            Button { perform(.insights) } label: { Label("Insights", systemImage: "chart.bar") }
                .accessibilityIdentifier("postDetail.menu.insights")
        case "share-image":
            Button { perform(.shareImage) } label: { Label("Share as Image…", systemImage: "photo.badge.plus") }
        case "crosspost":
            Button { perform(.crosspost) } label: { Label("Crosspost", systemImage: "arrowshape.turn.up.right") }
        case "other-discussions":
            Button { perform(.otherDiscussions) } label: {
                Label("Other Discussions", systemImage: "bubble.left.and.bubble.right")
            }
            .accessibilityIdentifier("postDetail.menu.otherDiscussions")
        case "find":
            Button { perform(.findInComments) } label: { Label("Find in Comments", systemImage: "magnifyingglass") }
                .accessibilityIdentifier("postDetail.menu.findInComments")
        case "award":
            Button { perform(.award) } label: { Label("Give Award", systemImage: "medal") }
                .accessibilityIdentifier("postDetail.menu.giveAward")
        case "copy-link":
            Button { perform(.copyLink) } label: { Label("Copy Link", systemImage: "link") }
        case "remind-me":
            Button { perform(.remindMe) } label: { Label("Remind Me In…", systemImage: "alarm") }
        case "translate":
            Button { perform(.translate) } label: { Label("Translate", systemImage: "character.bubble") }
        case "copy-text":
            Button { perform(.copyText) } label: { Label("Copy Text", systemImage: "doc.on.doc") }
        case "edit":
            Button { perform(.edit) } label: { Label("Edit Post", systemImage: "pencil") }
                .accessibilityIdentifier("postDetail.menu.editPost")
        case "delete":
            Button(role: .destructive) { perform(.delete) } label: { Label("Delete Post", systemImage: "trash") }
                .accessibilityIdentifier("postDetail.menu.deletePost")
        case "summarize":
            Button { perform(.summarize) } label: { Label("Summarize with AI", systemImage: "sparkles") }
                .accessibilityIdentifier("postDetail.summarizeWithAI")
        case "spec.FloatingTabs":
            Button { perform(.keepInFloatingTab) } label: {
                Label(facts.isKeptInFloatingTab ? "Already Kept in Floating Tab" : "Keep in Floating Tab",
                      systemImage: "circle.grid.2x2")
            }
            .disabled(facts.isKeptInFloatingTab)
            .accessibilityIdentifier("postDetail.keepInFloatingTab")
        case "mute-notifications":
            Button { perform(.toggleMute) } label: {
                Label(facts.isMuted ? "Unmute Notifications" : "Mute Notifications",
                      systemImage: facts.isMuted ? "bell.slash.fill" : "bell.slash")
            }
        case "report":
            Button(role: .destructive) { perform(.report) } label: { Label("Report", systemImage: "flag") }
        case "live-activity":
            // The local activity runs; its push half cannot (see
            // `FollowThreadActivity`).
            Button { perform(.liveActivity) } label: {
                Label(facts.liveActivityRunning ? "End Live Activity" : "Start Live Activity",
                      systemImage: facts.liveActivityRunning ? "stop.circle" : "clock.badge")
            }
            .accessibilityIdentifier("postDetail.menu.liveActivity")
        case "nsfw", "spoiler":
            if let mark = PostMark(rawValue: id) {
                PostMarkMenuButton(mark: mark, post: facts.markedPost, repository: repository,
                                   identifierPrefix: "postDetail.menu", isInert: isPreview)
            }
        case "spec.DeletedComments":
            // See `CommentTreeStore.toggleDeletedCommentsShortcut`.
            Button { perform(.deletedComments) } label: {
                Label(facts.deletedCommentsRecoveryActive ? "Hide Deleted Comments" : "Show Deleted Comments",
                      systemImage: facts.deletedCommentsRecoveryActive ? "eye.slash" : "eye")
            }
            .accessibilityIdentifier("postDetail.deletedCommentsShortcut")
        default:
            EmptyView()
        }
    }
}
