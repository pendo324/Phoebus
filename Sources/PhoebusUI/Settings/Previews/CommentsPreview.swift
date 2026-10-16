import SwiftUI
import PhoebusCore

/// The Comments and Thread Colours preview: the thread screen's own
/// `CommentRow` for the sample thread, one reply chain with a pinned
/// AutoModerator comment, a new comment from a new account, a followed user's
/// edited reply, your own reply and a removed comment. Phoebus-only; neither
/// Apollo nor Reborn previews a thread.
///
/// The rows are the real ones, laid out with the thread's insets, so every
/// Comments setting reaches them the way it reaches a thread; the collapse
/// settings go through the thread builder, and the removed comment through the
/// archive recovery the thread uses. The jump button sits where Jump Button
/// Position puts it. Thread Colours passes `appliesCollapseSettings: false` so
/// every depth stays open for its colour to show.
struct CommentsPreview: View {
    let repository: RedditRepository
    let depthColors: [Color]
    var appliesCollapseSettings = true

    @Setting(GeneralSettings.self) private var general
    @Setting(DeletedCommentsSettingsStore.storage) private var deleted
    @Environment(\.colorScheme) private var colorScheme
    @State private var post = SettingsPreviewSample.post(imageURL: SettingsPreviewImage.url)
    @State private var now = Date()

    var body: some View {
        let roots = SettingsPreviewSample.thread(
            autoCollapseChildren: appliesCollapseSettings && general.autoCollapseChildComments,
            collapsePinned: appliesCollapseSettings && general.autoCollapsePinnedComments,
            collapseAutoModerator: appliesCollapseSettings && general.autoCollapseAutoModeratorComments,
            now: now)
        let byFullname = general.commentAgeMode == .relativeToParent ? CommentAgeFormatter.commentsByFullname(roots) : [:]
        let nodes = roots.flatMap { $0.visibleFlattened() }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                let archived = CommentTreeStore.archivedCopy(for: node.comment, recoveryActive: deleted.mode == .alwaysShow,
                                                             archive: SettingsPreviewSample.archivedComments)
                CommentRow(
                    node: node, depthColors: depthColors, repository: repository,
                    isNew: SettingsPreviewSample.newCommentIDs.contains(node.id),
                    ageLabel: general.commentAgeMode == .sincePosted ? nil
                        : CommentAgeFormatter.label(comment: node.comment, post: post, parent: byFullname[node.comment.parentID],
                                                    mode: general.commentAgeMode, now: now),
                    archivedComment: archived, tapToReveal: deleted.tapToReveal,
                    onToggleCollapse: {}, onReplyTapped: {}, onQuoteTapped: {})
                    // The depth bar is a flexible `Rectangle`: a list row sizes to its text, and so must this.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: node.isCollapsed ? 10.5 : 10, leading: CommentRowMetrics.leadingInset(depth: node.depth),
                                        bottom: node.isCollapsed ? 10.5 : 11, trailing: 16))
                    .background(archived.map { DeletedCommentHighlight.color(for: $0.reason) } ?? .clear)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(Color.apolloSeparator(colorScheme: colorScheme))
                                .frame(height: 1.0 / 3.0)
                        }
                    }
            }
        }
        .overlay(alignment: general.jumpButtonPosition.alignment) {
            if general.showJumpButton {
                CommentJumpButtonLabel().padding(8)
            }
        }
        .inertSettingsPreview(label: "Preview: a sample comment thread as it appears under a post.")
        .accessibilityIdentifier("comments.preview")
    }
}
