import SwiftUI
import PhoebusCore

/// What a Share row shares: a post's text, or a comment's link.
enum MenuShareItem {
    case text(String)
    case url(URL)
}

/// A Share row. `ShareLink` opens the share sheet by itself, so the Action
/// Menus preview (`isPreview`) draws a button that does nothing instead.
struct MenuShareLink: View {
    let item: MenuShareItem
    let isPreview: Bool

    private var label: some View { Label("Share", systemImage: "square.and.arrow.up") }

    var body: some View {
        if isPreview {
            Button {} label: { label }
        } else {
            switch item {
            case .text(let text): ShareLink(item: text) { label }
            case .url(let url): ShareLink(item: url) { label }
            }
        }
    }
}

/// What a Moderator (Post) row can do. The post screen and the feed both
/// build their moderator rows from `PostModeratorMenuRow`.
enum PostModeratorAction {
    case approve, remove, spam, distinguish, sticky, lock, notes
}

/// What the Moderator (Post) rows' titles depend on.
struct PostModeratorMenuState: Equatable {
    var distinguished: Bool
    var stickied: Bool
    var locked: Bool
}

/// One Moderator (Post) row of the feed's post menu and of the post
/// screen's Moderator menu. `markIdentifierPrefix` and the Mod Notes row's
/// identifier differ per screen.
struct PostModeratorMenuRow: View {
    let id: String
    let post: RedditPost
    let repository: RedditRepository
    let state: PostModeratorMenuState
    let markIdentifierPrefix: String
    let isPreview: Bool
    let perform: (PostModeratorAction) -> Void

    var body: some View {
        switch id {
        case "mod-approve":
            Button { perform(.approve) } label: { Label("Approve", systemImage: "checkmark.shield") }
        case "mod-remove":
            Button(role: .destructive) { perform(.remove) } label: { Label("Remove", systemImage: "xmark.shield") }
        case "mod-spam":
            Button(role: .destructive) { perform(.spam) } label: { Label("Mark as Spam", systemImage: "exclamationmark.shield") }
        case "mod-distinguish":
            Button { perform(.distinguish) } label: {
                Label(state.distinguished ? "Undistinguish" : "Distinguish", systemImage: "shield.lefthalf.filled")
            }
        case "mod-sticky":
            Button { perform(.sticky) } label: { Label(state.stickied ? "Unsticky" : "Sticky", systemImage: "pin") }
        case "nsfw", "spoiler":
            if let mark = PostMark(rawValue: id) {
                PostMarkMenuButton(mark: mark, post: post, repository: repository,
                                   identifierPrefix: markIdentifierPrefix, isInert: isPreview)
            }
        case "mod-lock":
            Button { perform(.lock) } label: {
                Label(state.locked ? "Unlock Comments" : "Lock Comments", systemImage: state.locked ? "lock.open" : "lock")
            }
        case "mod-notes":
            if post.author != "[deleted]" {
                Button { perform(.notes) } label: { Label("Mod Notes", systemImage: "note.text") }
                    .accessibilityIdentifier("postDetail.menu.modNotes")
            }
        default:
            EmptyView()
        }
    }
}
