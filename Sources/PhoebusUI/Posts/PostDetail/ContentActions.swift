import Foundation
import PhoebusCore

/// The one vote/save/hide path for posts and comments.
///
/// Every surface (arrows, swipes, menus, the media viewer) goes through
/// here so the change is optimistic in `VoteStateStore`, which every view
/// of the item reads, is reverted if Reddit rejects it, and raises the
/// "Sign In to ..." alert when signed out.
@MainActor
public enum ContentActions {
    /// Sets the vote to `direction` (1, -1, or 0 to clear). Returns whether
    /// Reddit accepted it. Pass `presentsSignIn: false` from surfaces that
    /// show their own error, such as the fullscreen media viewer.
    @discardableResult
    public static func vote(_ item: some Votable, direction: Int, repository: RedditRepository,
                            presentsSignIn: Bool = true) async -> Bool {
        let store = VoteStateStore.shared
        let previous = store.vote(for: item.name, serverValue: item.likes)
        let delta = store.applyVote(fullname: item.name, direction: direction, serverValue: item.likes)
        do {
            try await repository.vote(fullname: item.name, direction: direction)
            return true
        } catch {
            store.revertVote(fullname: item.name, to: previous, delta: delta)
            if presentsSignIn {
                SignInRequiredPresenter.shared.presentIfNotAuthenticated(
                    error, action: SignInRequiredCopy.voteAction(direction: direction)
                )
            }
            return false
        }
    }

    /// Votes `tapped`, or clears the vote if it is already `tapped`.
    public static func toggleVote(_ item: some Votable, tapped: Int, repository: RedditRepository) async {
        let current = VoteStateStore.shared.vote(for: item.name, serverValue: item.likes)
        let resolved = VoteStateStore.toggledDirection(current: current, tapped: tapped)
        await vote(item, direction: resolved, repository: repository)
    }

    /// Saves or unsaves. Saving also upvotes when "Upvote on Save" is on.
    public static func toggleSave(_ item: some Votable, repository: RedditRepository) async {
        let store = VoteStateStore.shared
        let wasSaved = store.isSaved(item.name, serverValue: item.saved)
        store.setSaved(!wasSaved, for: item.name)
        do {
            if wasSaved {
                try await repository.unsave(fullname: item.name)
            } else {
                try await repository.save(fullname: item.name)
                if GeneralSettingsStore.load().upvoteOnSave {
                    await vote(item, direction: 1, repository: repository)
                }
            }
        } catch {
            store.setSaved(wasSaved, for: item.name)
            SignInRequiredPresenter.shared.presentIfNotAuthenticated(error, action: .save)
        }
    }

    /// Hides a post. Returns whether Reddit accepted it, so the caller can
    /// drop the row only on success.
    @discardableResult
    public static func hide(_ post: RedditPost, repository: RedditRepository) async -> Bool {
        (try? await repository.hide(fullname: post.name)) != nil
    }
}

/// Screen-specific handling for the swipe actions `ContentActions` does
/// not own. Leave a hook nil where the action has no meaning on a screen.
@MainActor
public struct SwipeActionHooks {
    public var onReply: (() -> Void)?
    public var onShare: (() -> Void)?
    /// Posts: called after a successful hide. Comments: collapse instead.
    public var onHide: (() -> Void)?
    public var onCollapseTop: (() -> Void)?
    public var onMarkRead: (() async -> Void)?
    /// Comments: fold this comment (stock `collapse`).
    public var onCollapse: (() -> Void)?
    public var onHidePostsAbove: (() async -> Void)?
    public var onParentComment: (() -> Void)?
    /// Who and where, for Author / Subreddit (opened in the current tab).
    public var author: String?
    public var subreddit: String?
    /// The text Select Text shows, with its sheet title.
    public var selectableText: (title: String, body: String)?

    public init(onReply: (() -> Void)? = nil, onShare: (() -> Void)? = nil,
                onHide: (() -> Void)? = nil, onCollapseTop: (() -> Void)? = nil,
                onMarkRead: (() async -> Void)? = nil, onCollapse: (() -> Void)? = nil,
                onHidePostsAbove: (() async -> Void)? = nil, onParentComment: (() -> Void)? = nil,
                author: String? = nil, subreddit: String? = nil,
                selectableText: (title: String, body: String)? = nil) {
        self.onReply = onReply
        self.onShare = onShare
        self.onHide = onHide
        self.onCollapseTop = onCollapseTop
        self.onMarkRead = onMarkRead
        self.onCollapse = onCollapse
        self.onHidePostsAbove = onHidePostsAbove
        self.onParentComment = onParentComment
        self.author = author
        self.subreddit = subreddit
        self.selectableText = selectableText
    }
}

extension ContentActions {
    /// Runs a row swipe on a post: vote/save/hide here, the rest through
    /// `hooks`.
    public static func perform(_ action: SwipeAction, on post: RedditPost,
                               repository: RedditRepository, hooks: SwipeActionHooks) async {
        Haptics.light()
        switch action {
        case .hide:
            if await hide(post, repository: repository) { hooks.onHide?() }
        default:
            await performShared(action, on: post, repository: repository, hooks: hooks)
        }
    }

    /// Runs a row swipe on a comment, or any other votable item. Reddit
    /// cannot hide comments, so Hide goes to `hooks.onHide`.
    public static func perform(_ action: SwipeAction, on item: some Votable,
                               repository: RedditRepository, hooks: SwipeActionHooks) async {
        Haptics.light()
        if action == .hide { hooks.onHide?(); return }
        await performShared(action, on: item, repository: repository, hooks: hooks)
    }

    private static func performShared(_ action: SwipeAction, on item: some Votable,
                                      repository: RedditRepository, hooks: SwipeActionHooks) async {
        switch action {
        case .upvote: await toggleVote(item, tapped: 1, repository: repository)
        case .downvote: await toggleVote(item, tapped: -1, repository: repository)
        case .save: await toggleSave(item, repository: repository)
        case .reply: hooks.onReply?()
        case .share: hooks.onShare?()
        case .collapseTop: hooks.onCollapseTop?()
        case .markRead: await hooks.onMarkRead?()
        case .collapse: (hooks.onCollapse ?? hooks.onHide)?()
        case .hidePostsAbove: await hooks.onHidePostsAbove?()
        case .parentComment: hooks.onParentComment?()
        case .author:
            if let author = hooks.author, !author.isEmpty, author != "[deleted]" { RedditLinkNavigator.open(.user(author)) }
        case .subreddit:
            if let subreddit = hooks.subreddit, !subreddit.isEmpty { RedditLinkNavigator.open(.subreddit(subreddit)) }
        case .selectText:
            if let text = hooks.selectableText { SelectTextPresenter.shared.present(title: text.title, body: text.body) }
        case .hide, .none: break
        }
    }
}


/// Select Text from a row swipe, shown by the app's root so any list can
/// ask for it (a sheet attached inside a `List` row doesn't present).
@MainActor
public final class SelectTextPresenter: ObservableObject {
    public static let shared = SelectTextPresenter()

    public struct Request: Identifiable {
        public let id = UUID()
        public let title: String
        public let body: String
    }

    @Published public var request: Request?

    public func present(title: String, body: String) {
        request = Request(title: title, body: body)
    }
}
