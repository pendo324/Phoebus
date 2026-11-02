import Foundation

/// Which interactions a comment offers. A deleted or removed comment has
/// nothing to vote on, reply to or save (stock Apollo's `RDKComment` carries
/// `isDeleted` / `isRemoved` for this), so every surface that acts on a
/// comment (the vote arrow, the ••• and long-press menu, row swipes,
/// VoiceOver actions) asks here and they cannot disagree.
///
/// A comment restored by the Deleted Comments feature is still deleted on
/// Reddit: it shows its recovered text and author, but it takes no writes.
/// A live comment is never restricted; locked comments keep every action
/// and Reddit's own refusal shows as it does today.
public struct CommentInteractionPolicy: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case live
        case userDeleted
        case removed
    }

    public enum Interaction: Sendable, CaseIterable {
        case vote, reply, quote, save, award, report
        case share, copyLink, copyText, copyUsername, tagUser, openProfile, translate
        case shareAsImage, remindMe, muteNotifications
        case edit, delete, voteInsights, moderate, modNotes
        case collapse
    }

    public let status: Status
    /// The archive's copy is what the row shows.
    public let isRecovered: Bool
    /// The author the row shows: the archive's for a restored comment.
    public let author: String
    /// The text the row shows (the recovered text for a restored comment).
    public let text: String
    private let textVisible: Bool
    private let isOwn: Bool

    /// `recovered` is the archive copy the row shows (`CommentTreeStore.archivedCopy`,
    /// which only returns one for a placeholder body). `textRevealed` is false
    /// while Tap to Show Deleted Comments hides the recovered text behind its
    /// chip. `locallyDeleted` is the signed-in user's own delete that the tree
    /// has not reloaded yet.
    public init(author: String, body: String, recovered: ArchivedComment? = nil, textRevealed: Bool = true,
                locallyDeleted: Bool = false, isOwn: Bool = false) {
        let restored = locallyDeleted ? nil : recovered
        let placeholder = locallyDeleted || restored != nil || DeletedCommentsClassifier.bodyIsRedditPlaceholder(body)
        if !placeholder {
            status = .live
        } else if locallyDeleted {
            status = .userDeleted
        } else if let restored {
            status = restored.reason == .userDeleted ? .userDeleted : .removed
        } else {
            status = DeletedCommentsClassifier.bodyLooksUserDeleted(body) ? .userDeleted : .removed
        }
        isRecovered = restored != nil
        if let name = restored?.author, !name.isEmpty, name != "[deleted]" {
            self.author = name
        } else {
            self.author = author
        }
        text = restored?.body ?? body
        textVisible = textRevealed
        self.isOwn = isOwn
    }

    public init(comment: RedditComment, recovered: ArchivedComment? = nil, textRevealed: Bool = true,
                locallyDeleted: Bool = false, isOwn: Bool = false) {
        self.init(author: comment.author, body: comment.body, recovered: recovered, textRevealed: textRevealed,
                  locallyDeleted: locallyDeleted, isOwn: isOwn)
    }

    public var isLive: Bool { status == .live }

    /// A real username to open, copy or tag. Reddit's "[deleted]" is not one.
    public var hasUsername: Bool { !author.isEmpty && author != "[deleted]" }

    /// Text worth copying, translating or selecting: the live body, or a
    /// restored one once it is revealed. A bare placeholder is not.
    private var hasText: Bool { isLive || (isRecovered && textVisible) }

    public func allows(_ interaction: Interaction) -> Bool {
        switch interaction {
        case .collapse, .share, .copyLink, .remindMe, .muteNotifications:
            return true
        case .vote, .reply, .quote, .save, .award, .report, .shareAsImage, .moderate:
            return isLive
        case .modNotes:
            return isLive && hasUsername
        case .edit, .voteInsights:
            return isLive && isOwn
        case .delete:
            return isOwn && status != .userDeleted
        case .copyText, .translate:
            return hasText
        case .copyUsername, .tagUser, .openProfile:
            return hasUsername
        }
    }

    /// The comment ••• menu's row ids (`CommentRow.commentMenuIDs` and the
    /// moderator menu). An id this policy does not know is left alone.
    public func allowsMenuItem(_ id: String) -> Bool {
        switch id {
        case "upvote", "downvote": return allows(.vote)
        case "reply": return allows(.reply)
        case "quote": return allows(.quote)
        case "save": return allows(.save)
        case "edit": return allows(.edit)
        case "delete": return allows(.delete)
        case "vote-insights": return allows(.voteInsights)
        case "share": return allows(.share)
        case "copy-link": return allows(.copyLink)
        case "copy-text": return allows(.copyText)
        case "share-image": return allows(.shareAsImage)
        case "copy-username": return allows(.copyUsername)
        case "tag-user": return allows(.tagUser)
        case "translate": return allows(.translate)
        case "award": return allows(.award)
        case "report": return allows(.report)
        case "remind-me": return allows(.remindMe)
        case "mute-notifications": return allows(.muteNotifications)
        case "mod-notes": return allows(.modNotes)
        case "mod-approve", "mod-remove", "mod-spam", "mod-distinguish", "mod-sticky": return allows(.moderate)
        default: return true
        }
    }

    /// A row swipe. Collapse, Parent Comment, Share, Subreddit and Mark Read
    /// touch nothing on Reddit and stay; Hide is Collapse on a comment.
    public func allows(swipe action: SwipeAction) -> Bool {
        switch action {
        case .upvote, .downvote: return allows(.vote)
        case .save: return allows(.save)
        case .reply: return allows(.reply)
        case .author: return allows(.openProfile)
        case .selectText: return allows(.copyText)
        case .share, .hide, .collapseTop, .markRead, .collapse, .hidePostsAbove, .parentComment, .subreddit, .none:
            return true
        }
    }

    /// The swipe slots for this row: an action it cannot perform becomes
    /// `.none`, so the row reveals nothing for it, as for a disabled side.
    public func restricting(_ settings: SwipeActionSettings) -> SwipeActionSettings {
        func keep(_ action: SwipeAction) -> SwipeAction { allows(swipe: action) ? action : .none }
        return SwipeActionSettings(leftShort: keep(settings.leftShort), leftLong: keep(settings.leftLong),
                                   rightShort: keep(settings.rightShort), rightLong: keep(settings.rightLong))
    }
}
