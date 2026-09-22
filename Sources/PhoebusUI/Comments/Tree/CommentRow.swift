import SwiftUI
import PhoebusCore

struct CommentRow: View {
    let node: CommentTreeNode
    /// Full depth-color palette. Each bar is indexed by its own position
    /// (not the row's depth) so a depth's color stays consistent down the
    /// thread.
    let depthColors: [Color]
    let repository: RedditRepository
    let isNew: Bool
    /// This is the comment an Inbox reply linked to, so it is drawn
    /// highlighted.
    var isLinkedToComment: Bool = false
    /// See `CommentTreeScreen.isModerator`'s doc comment.
    var isModerator: Bool = false
    /// Reborn "Deleted Comments" archive recovery. Non-nil only when the
    /// body looks deleted, recovery is active and the archive had a usable
    /// copy. Renders the recovered body (or a tappable reason chip under
    /// Tap-to-Reveal) instead of "[deleted]".
    var archivedComment: ArchivedComment? = nil
    /// See `DeletedCommentsSettings.tapToReveal`'s doc comment.
    var tapToReveal: Bool = false
    /// Present when Share as Image is available for this comment.
    var onShareAsImage: (() -> Void)? = nil
    /// Whether the user has already tapped through this comment's chip.
    var isRevealed: Bool = false
    /// Marks this comment's chip as revealed.
    var onReveal: () -> Void = {}
    let onToggleCollapse: () -> Void
    let onReplyTapped: () -> Void
    let onQuoteTapped: () -> Void
    /// Tapping a commenter's username navigates to their profile.
    /// Optional since not every call site threads a navigation target.
    var onAuthorTapped: () -> Void = {}

    /// Vote and save state come from the shared store, not private
    /// `@State` (see `VoteStateStore`): the swipe gesture is handled by the
    /// parent list, so per-row state cannot reflect it.
    @ObservedObject private var voteStore = VoteStateStore.shared
    /// Row colours: #D0D1D6 username/body, #61626A score and age (see
    /// `Color.apolloPrimaryText`).
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var themeColors

    private var voteState: Bool? { voteStore.vote(for: node.comment.name, serverValue: node.comment.likes) }
    /// The archive's author for a recovered comment (Reborn restores it
    /// with `setAuthor:`), else Reddit's.
    private var displayAuthor: String {
        if let author = archivedComment?.author, !author.isEmpty, author != "[deleted]" { return author }
        return node.comment.author
    }

    private var displayScore: Int { node.comment.score + voteStore.scoreDelta(for: node.comment.name) }
    private var isSaved: Bool { voteStore.isSaved(node.comment.name, serverValue: node.comment.saved) }
    @State private var showingReport = false
    @State private var showingTranslator = false
    @State private var isOwnComment = false
    @State private var isEditing = false
    @State private var editedText: String
    @State private var isDeleted = false
    @State private var displayBody: String
    @Setting(GeneralSettings.self) private var general
    @State private var isMuted = false
    /// Local optimistic mirrors of moderator-only comment state, since
    /// `node.comment` is nested in an immutable value-type tree.
    @State private var isDistinguished: Bool
    @State private var isStickied: Bool

    /// Reborn "Tap to Collapse…" (`TapToCollapseEnabledType`): where a
    /// single tap collapses (header, body, both, neither).
    private func collapseFromHeader() {
        if general.tapToCollapseType.collapsesOnHeaderTap { onToggleCollapse() }
    }

    private func collapseFromBody() {
        if general.tapToCollapseType.collapsesOnBodyTap { onToggleCollapse() }
    }

    init(node: CommentTreeNode, depthColors: [Color], repository: RedditRepository, isNew: Bool = false, isLinkedToComment: Bool = false, isModerator: Bool = false, archivedComment: ArchivedComment? = nil, tapToReveal: Bool = false, isRevealed: Bool = false, onReveal: @escaping () -> Void = {}, onToggleCollapse: @escaping () -> Void, onReplyTapped: @escaping () -> Void, onQuoteTapped: @escaping () -> Void, onAuthorTapped: @escaping () -> Void = {}, onShareAsImage: (() -> Void)? = nil) {
        self.node = node
        self.depthColors = depthColors
        self.repository = repository
        self.isNew = isNew
        self.isLinkedToComment = isLinkedToComment
        self.isModerator = isModerator
        self.archivedComment = archivedComment
        self.tapToReveal = tapToReveal
        self.onShareAsImage = onShareAsImage
        self.isRevealed = isRevealed
        self.onReveal = onReveal
        self.onToggleCollapse = onToggleCollapse
        self.onReplyTapped = onReplyTapped
        self.onQuoteTapped = onQuoteTapped
        self.onAuthorTapped = onAuthorTapped
        _editedText = State(initialValue: node.comment.body)
        _displayBody = State(initialValue: node.comment.body)
        _isMuted = State(initialValue: MutedThreadsStore.isMuted(node.comment.name))
        _isDistinguished = State(initialValue: node.comment.distinguished == "moderator")
        _isStickied = State(initialValue: node.comment.stickied)
    }

    /// The comment's ••• menu, shared by the long press and the byline
    /// "..." button. Entries are listed in the app's order, then arranged
    /// by the user's Action Menus layout (Reborn #1131): ids from
    /// `ActionMenuCatalog` can be moved or hidden; this app's extra rows
    /// (Quote, Copy Link…) travel with the entry before them.
    @ViewBuilder
    private var actionMenu: some View {
        ForEach(ActionMenuLayoutStore.arrange(commentMenuIDs, for: .comment), id: \.self) { id in
            commentMenuRow(id)
        }
        if isModerator {
            Divider()
            ForEach(ActionMenuLayoutStore.arrange(moderatorMenuIDs, for: .moderatorComment), id: \.self) { id in
                commentMenuRow(id)
            }
        }
    }

    private var commentMenuIDs: [String] {
        var ids = ["upvote", "downvote", "reply", "quote", "save"]
        if isOwnComment && !isDeleted { ids += ["edit", "delete", "vote-insights"] }
        ids += ["share", "copy-link", "copy-text"]
        if onShareAsImage != nil { ids.append("share-image") }
        ids += ["copy-username", "translate", "award", "report", "mute-notifications"]
        return ids
    }

    private let moderatorMenuIDs = ["mod-approve", "mod-remove", "mod-spam", "mod-distinguish", "mod-sticky"]

    @ViewBuilder
    private func commentMenuRow(_ id: String) -> some View {
        switch id {
        case "upvote":
            Button { Task { await vote(direction: voteState == true ? 0 : 1) } } label: {
                Label("Upvote", systemImage: "arrow.up")
            }
        case "downvote":
            Button { Task { await vote(direction: voteState == false ? 0 : -1) } } label: {
                Label("Downvote", systemImage: "arrow.down")
            }
        case "reply":
            Button { onReplyTapped() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        case "quote":
            // Apollo's select-text mode "Quote" action.
            Button { onQuoteTapped() } label: { Label("Quote", systemImage: "quote.opening") }
        case "save":
            Button { Task { await toggleSave() } } label: {
                Label(isSaved ? "Unsave" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
            }
        case "edit":
            Button { isEditing = true } label: { Label("Edit", systemImage: "pencil") }
        case "delete":
            Button(role: .destructive) { Task { await deleteComment() } } label: {
                Label("Delete", systemImage: "trash")
            }
        case "share":
            ShareLink(item: node.comment.shareURL()) { Label("Share", systemImage: "square.and.arrow.up") }
        case "copy-link":
            // Apollo's CopyURLActivity: the comment's own permalink.
            Button { PasteboardHelper.copy(url: node.comment.shareURL()) } label: {
                Label("Copy Link", systemImage: "link")
            }
        case "copy-text":
            Button { PasteboardHelper.copy(node.comment.body) } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        case "share-image":
            if let onShareAsImage {
                Button { onShareAsImage() } label: { Label("Share as Image", systemImage: "photo.badge.plus") }
            }
        case "copy-username":
            // Reborn: Copy Username (from the avatar's hold menu).
            Button { PasteboardHelper.copy(node.comment.author) } label: {
                Label("Copy Username", systemImage: "doc.on.doc")
            }
        case "translate":
            Button { showingTranslator = true } label: { Label("Translate", systemImage: "character.bubble") }
        case "report":
            Button(role: .destructive) { showingReport = true } label: { Label("Report", systemImage: "flag") }
        case "mute-notifications":
            // On-device suppression list: Reddit's API has no endpoint.
            Button {
                isMuted.toggle()
                MutedThreadsStore.setMuted(node.comment.name, muted: isMuted)
            } label: {
                Label(isMuted ? "Unmute Notifications" : "Mute Notifications", systemImage: isMuted ? "bell" : "bell.slash")
            }
        case "mod-approve":
            Button { Task { try? await repository.approve(fullname: node.comment.name) } } label: {
                Label("Approve", systemImage: "checkmark.shield")
            }
        case "mod-remove":
            Button(role: .destructive) {
                Task { _ = try? await repository.remove(fullname: node.comment.name, isSpam: false) }
            } label: { Label("Remove", systemImage: "xmark.shield") }
        case "mod-spam":
            Button(role: .destructive) {
                Task { _ = try? await repository.remove(fullname: node.comment.name, isSpam: true) }
            } label: { Label("Mark as Spam", systemImage: "exclamationmark.shield") }
        case "mod-distinguish":
            Button {
                Task {
                    // Only on success, so the badge and colour match Reddit.
                    guard (try? await repository.distinguish(fullname: node.comment.name, asMod: !isDistinguished)) != nil else { return }
                    isDistinguished.toggle()
                }
            } label: {
                Label(isDistinguished ? "Undistinguish" : "Distinguish", systemImage: "shield.lefthalf.filled")
            }
        case "mod-sticky":
            Button {
                Task {
                    guard (try? await repository.setSticky(fullname: node.comment.name, sticky: !isStickied)) != nil else { return }
                    isStickied.toggle()
                }
            } label: { Label(isStickied ? "Unsticky" : "Sticky", systemImage: "pin") }
        default:
            EmptyView()
        }
    }

    /// VoiceOver treatment for the row (see `CommentAccessibility`).
    private var accessibility: CommentAccessibility {
        CommentAccessibility(
            label: AccessibilitySummary.comment(
                author: node.comment.author, body: node.comment.body, score: displayScore,
                scoreHidden: node.comment.scoreHidden, created: node.comment.created,
                isOP: node.comment.isSubmitter == true, collapsed: node.isCollapsed,
                hiddenReplies: node.isCollapsed ? Self.descendantCount(node) : 0, vote: voteState),
            author: node.comment.author, voteState: voteState, isSaved: isSaved,
            onCollapse: onToggleCollapse, onReply: onReplyTapped, onAuthor: onAuthorTapped,
            onVote: { direction in Task { await vote(direction: direction) } },
            onSave: { Task { await toggleSave() } })
    }

    /// Replies hidden under a collapsed comment, for its spoken label.
    static func descendantCount(_ node: CommentTreeNode) -> Int {
        node.children.reduce(0) { $0 + 1 + descendantCount($1) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // One solid depth bar per row, at the row's own indent, colored by its
            // own depth (not a dimmed ancestor stack). Top-level comments have no
            // bar; a reply's 2pt bar sits at x = depth × 12 with its content 15pt
            // past the bar.
            if node.depth > 0 {
                Rectangle()
                    .fill(depthColors[node.depth % depthColors.count])
                    .frame(width: 2)
                    .padding(.trailing, CommentRowMetrics.barToContent)
            }
            // A dedicated collapse strip left of the whole comment, scoped so it
            // never overlaps the "...", score, or username tap targets. It adds no
            // width of its own: an `.overlay` on the content claims the leading
            // gutter for hit-testing without pushing the avatar/body inset off the
            // 15pt used by the post header.

            // 8pt between the header line and the body.
            VStack(alignment: .leading, spacing: 8) {
                // 11pt between the username cluster and the score arrow.
                HStack(spacing: 11) {
                    // New-comments tracker: a small dot for a comment not present at last
                    // visit.
                    if isNew {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    }
                    // A pinned (stickied) comment leads with Apollo's
                    // green pin (`inline-sticky`).
                    if isStickied {
                        StockIcon("inline-sticky", size: CGSize(width: 10, height: 15))
                            .foregroundStyle(Color(hex: ApolloPalette.moderatorGreenHex))
                            .accessibilityLabel("Pinned")
                    }
                    // Reborn's "Show User Profile Pictures".
                    HStack(spacing: 4.7) {
                    if general.showUserProfilePictures {
                        // 27pt avatar, 4.7pt from the name.
                        AvatarView(username: displayAuthor, repository: repository, size: 27)
                    }
                    Text(displayAuthor)
                        // 15pt medium in #D0D1D6: Apollo's name strokes are lighter than
                        // semibold.
                        .apolloFont(size: 15, weight: .medium)
                        // Apollo's moderator green (see `ApolloPalette`).
                        .foregroundStyle(isDistinguished ? Color(hex: ApolloPalette.moderatorGreenHex) : (node.comment.distinguished == "admin" ? Color.red : Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: themeColors)))
                        // Tapping the username opens the profile. A long username shrinks to
                        // one line with a tail ellipsis instead of pushing the score, badges
                        // and age off the row (Reborn #1162).
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onAuthorTapped)
                        .accessibilityIdentifier("comment.authorLabel.\(node.id)")
                    }
                    // "OP" badge next to the post's own author's comments.
                    if node.comment.isSubmitter == true {
                        Text("OP")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.apolloAccent))
                    }
                    // Mod/admin badge, separate from the OP badge (a moderator replying
                    // to their own post shows both).
                    if let distinguished = isDistinguished ? "moderator" : (node.comment.distinguished == "admin" ? "admin" : nil),
                       distinguished == "moderator" || distinguished == "admin", !isStickied {
                        Text(distinguished == "moderator" ? "MOD" : "ADMIN")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(distinguished == "moderator" ? Color(hex: ApolloPalette.moderatorGreenHex) : Color.red))
                    }
                    // Reborn "New Account Highlight" (`GeneralSettings.highlightAccountAge`);
                    // see `AccountAgeBadge`.
                    if general.highlightAccountAge {
                        AccountAgeBadge(username: node.comment.author, repository: repository)
                    }
                    // "User Flair" toggle (Settings > Appearance > Flair).
                    if general.showUserFlair, let authorFlair = node.comment.authorFlairText, !authorFlair.isEmpty {
                        CommentFlairPill(text: authorFlair, parts: node.comment.authorFlairRichtext,
                                         textColor: authorFlairTextColor, fill: authorFlairBackgroundColor)
                            // Below the author's -1: a long flair truncates before the username.
                            .layoutPriority(-2)
                    }
                    // `author_cakeday` (true on the account-creation anniversary): Apollo
                    // shows a cake icon.
                    if node.comment.authorCakeday == true {
                        Text("🎂")
                            .font(.caption2)
                            .accessibilityLabel("Cake day")
                    }
                    // Apollo shows the score as an arrow + number, styled like the feed
                    // row's, with the arrow reflecting the user's vote. An explicit
                    // `HStack` (not `Label`, which is inert and has wide icon-to-title
                    // spacing) gives a 3pt gap and makes the whole cluster a live vote
                    // control.
                    Button {
                        Task { await vote(direction: voteState == true ? 0 : 1) }
                    } label: {
                        HStack(spacing: 5) {
                            // The arrow is sized separately from the number. It is Apollo's
                            // `posts-points` glyph at 10x12pt, 5pt from the 13pt regular score.
                            // The idle pair is #61626A (`apolloIdleVoteArrow`'s opt-out colour);
                            // the helper stays so "Colourize Vote Arrows" still reaches comments.
                            if voteState == false {
                                StockIcon("posts-points")
                                    .rotationEffect(.degrees(180))
                            } else {
                                StockIcon("posts-points")
                            }
                            // Reddit hides a new comment's score for a while; Apollo draws an em
                            // dash.
                            Text(node.comment.scoreHidden ? "\u{2014}" : displayScore.apolloAbbreviated)
                                .apolloFont(size: 13)
                        }
                        .foregroundStyle(voteState == true ? Color.orange
                                         : (voteState == false ? Color.blue : Color.apolloIdleVoteArrow))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("comment.scoreUpvote.\(node.id)")
                    // Locked comments carry Apollo's lock glyph, green like the pin.
                    if node.comment.locked == true {
                        StockIcon("inline-locked", size: CGSize(width: 11, height: 14))
                            .foregroundStyle(Color(hex: ApolloPalette.moderatorGreenHex))
                            .accessibilityLabel("Locked")
                    }
                    // Expanded rows end with "••• <age>"; collapsed rows end with a badge
                    // holding the hidden-descendant count and a separate chevron, dropping
                    // the age. The empty band between score and trailing cluster collapses
                    // on a tap: a `Color.clear` overlay with its own `contentShape` on a
                    // real `Spacer`, so it adds no height and doesn't stretch the byline.
                    Spacer(minLength: 0)
                        .overlay {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { collapseFromHeader() }
                                .accessibilityIdentifier("comment.headerSpacerCollapse.\(node.id)")
                        }
                    if node.isCollapsed {
                        Button(action: onToggleCollapse) {
                            HStack(spacing: 6) {
                                // The badge counts the collapsed comment itself plus every hidden
                                // descendant: a pinned AutoModerator notice with no replies reads "1".
                                Text("\(node.threadCount)")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.25)))
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            // The gap between the badge and the chevron, and the padding around
                            // them, are part of the button's hit area.
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("comment.collapseToggle.\(node.id)")
                    } else {
                        // The "..." is an actions button, presenting the same menu as a long
                        // press.
                        Menu {
                            actionMenu
                        } label: {
                            // Apollo's `inline-more-options` glyph (18x4) in the quaternary label
                            // colour #505256, not an SF `ellipsis`.
                            StockIcon("inline-more-options")
                                .foregroundStyle(colorScheme == .dark ? Color(hex: "505256") : Color(hex: "C4C4C6"))
                                // A bare glyph is a ~10pt target; enlarge the hit area without
                                // changing the look.
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("comment.actionsMenu.\(node.id)")
                        .accessibilityLabel("Comment actions")
                        // The age owns the detailed-timestamp tap, not the "...". The info-row
                        // detail icons (% upvoted, timestamp, edited pencil) reveal their
                        // detail on tap; `TimestampLabel` gives itself its own `contentShape`
                        // so the row's collapse gesture doesn't swallow it.
                        TimestampLabel(node.comment.created)
                            // 13pt regular in #61626A (tertiary), 16pt trailing inset, 11pt gap
                            // back to the "•••".
                            .apolloFont(size: 13)
                            .foregroundStyle(Color.apolloTertiaryText(
                                colorScheme: colorScheme, themeColors: themeColors))
                            .padding(.leading, 11)
                            .fixedSize()
                            .accessibilityIdentifier("comment.age.\(node.id)")
                    }
                }
                // The collapse tap lives on the byline's background, sized to its
                // parent so it covers the whole band including the empty gap, and sits
                // behind the score button and "..." menu, which keep their own taps.
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { collapseFromHeader() }
                        .accessibilityIdentifier("comment.headerSpacerCollapse.\(node.id)")
                )
                // The byline strip is itself a collapse trigger. Scoped to the byline
                // only, not the whole cell, so the body stays tappable for link taps
                // and text selection; the author name and chevron keep their own taps
                // (an inner gesture takes precedence).
                .contentShape(Rectangle())
                if !node.isCollapsed {
                    if isEditing {
                        TextEditor(text: $editedText)
                            .frame(minHeight: 60)
                        HStack {
                            Button("Cancel") { isEditing = false }
                            Button("Save") { Task { await saveEdit() } }
                        }
                        .font(.caption)
                    } else if isDeleted {
                        Text("[deleted]").italic().foregroundStyle(.secondary)
                    } else if let archivedComment {
                        // Reborn "Deleted Comments" archive recovery. Tap-to-Reveal hides the
                        // recovered body behind the reason chip until tapped.
                        if tapToReveal && !isRevealed {
                            Button(action: onReveal) {
                                DeletedReasonChip(label: archivedComment.reason.displayLabel)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("comment.deletedCommentReveal.\(node.id)")
                        } else {
                            // The recovered body in the normal comment style, then the reason chip.
                            VStack(alignment: .leading, spacing: 5.7) {
                                InlineMediaBodyView(archivedComment.body)
                                    .apolloFont(size: 15)
                                    .foregroundStyle(Color.apolloPrimaryText(
                                        colorScheme: colorScheme, themeColors: themeColors))
                                DeletedReasonChip(label: archivedComment.reason.displayLabel)
                            }
                        }
                    } else if DeletedCommentsClassifier.bodyLooksDeletedOrRemoved(displayBody) {
                        // No archive coverage: plain placeholder text.
                        Text(displayBody).italic().foregroundStyle(.secondary)
                    } else {
                        // 15pt, Apollo's comment body size.
                        InlineMediaBodyView(displayBody, mediaMetadata: node.comment.mediaMetadata)
                            .apolloFont(size: 15)
                            // "Tap to Collapse: Comments / Both" also collapses on a tap on the
                            // comment text. Links inside the body keep their own taps.
                            .onTapGesture { collapseFromBody() }
                            // No extra leading: the body runs on the font's own 18pt pitch, flush
                            // with the avatar.
                            .foregroundStyle(Color.apolloPrimaryText(
                                colorScheme: colorScheme, themeColors: themeColors))
                    }
                    // Apollo shows no persistent action bar under comments; actions are
                    // on swipes and the long-press/••• menu.
                }
            }
            // The full-height collapse gutter is overlaid rather than laid out so
            // the avatar can start at x=15.
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onTapGesture { collapseFromHeader() }
                    .accessibilityIdentifier("comment.collapseStrip.\(node.id)")
                    .accessibilityLabel(node.isCollapsed ? "Expand comment" : "Collapse comment")
            }
        }

        // Apollo's saved-post wedge, drawn from the 18pt
        // `saved-triangle-small` asset, matching the denser comment row.
        .overlay(alignment: .bottomTrailing) {
            if isSaved {
                SavedIndicatorBadge(size: .small)
            }
        }
        // Reborn/Apollo "New Comments Highlightifier" (Settings > General >
        // Comments): tints comments posted since your last visit.
        .background(
            // The linked-comment highlight takes precedence over the new-comment
            // tint, since it marks one specific comment.
            isLinkedToComment
                ? Color.apolloAccent.opacity(0.22)
                : ((isNew && general.newCommentsHighlightifier)
                    ? Color.apolloAccent.opacity(0.12)
                    : Color.clear)
        )
        .contextMenu { actionMenu }
        .modifier(accessibility)
        .sheet(isPresented: $showingReport) {
            ReportSheet(fullname: node.comment.name, repository: repository) {
                showingReport = false
            }
        }
        .apolloTranslator(isPresented: $showingTranslator, text: node.comment.body)
        .task { await checkOwnership() }
        // The row keeps its identity across refreshes, so its local copies
        // follow the comment when a newer version arrives (edit, live update,
        // moderator change).
        .onChange(of: node.comment.body) { _, body in
            displayBody = body
            if !isEditing { editedText = body }
        }
        .onChange(of: node.comment.distinguished) { _, value in isDistinguished = value == "moderator" }
        .onChange(of: node.comment.stickied) { _, value in isStickied = value }
    }

    /// The author-only actions (Edit, Delete, Vote Insights), grouped so the
    /// context menu stays within `ViewBuilder`'s ten-child limit. Gated on
    /// the signed-in user matching the comment's author; the username is
    /// cached and resolved once per session to avoid one `/api/v1/me`
    /// request per row.
    private func checkOwnership() async {
        guard let username = await CurrentUsernameCache.username(repository: repository) else { return }
        isOwnComment = username.caseInsensitiveCompare(node.comment.author) == .orderedSame
    }

    private func saveEdit() async {
        do {
            try await repository.editUserText(fullname: node.comment.name, text: editedText)
            displayBody = editedText
            isEditing = false
        } catch {
            // Leave the editor open on failure so the user can retry.
        }
    }

    private func deleteComment() async {
        try? await repository.delete(fullname: node.comment.name)
        isDeleted = true
    }

    private func vote(direction: Int) async {
        Haptics.light()
        await CommentVoting.vote(comment: node.comment, direction: direction, repository: repository)
    }

    private func toggleSave() async {
        Haptics.light()
        await CommentVoting.toggleSave(comment: node.comment, repository: repository)
    }

    /// Per-subreddit flair colors (see `RedditFlairColor`), gated on "Color
    /// Flairs" (`GeneralSettings.enableFlairColors`). `nil` falls back to
    /// flat grey.
    private var authorFlairBackgroundColor: Color? {
        guard general.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: node.comment.authorFlairBackgroundColor).map(Color.init(hex:))
    }
    private var authorFlairTextColor: Color? {
        guard general.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: node.comment.authorFlairTextColorRaw).map(Color.init(hex:))
    }
}

/// A tappable "N more replies" row for a Reddit `more` continuation stub.
/// Tapping fetches its real children via `/api/morechildren` and splices
/// them into the tree in place.
struct MoreRepliesRow: View {
    let stub: MoreStub
    var depthColors: [Color] = []
    let isResolving: Bool
    let onTap: () -> Void

    /// The stub stands at its replies' depth: a depth-2 thread's "1 more
    /// reply" carries the depth-2 bar.
    private var barColor: Color {
        guard !depthColors.isEmpty else { return .accentColor }
        return depthColors[stub.depth % depthColors.count]
    }

    /// Apollo's link blue, #4B96F7.
    private static let linkBlue = Color(red: 75 / 255, green: 150 / 255, blue: 247 / 255)

    var body: some View {
        Button(action: onTap) {
            // 39pt row; a 2pt × 21pt depth bar, vertically centred; the label 16pt
            // past the bar in 14pt regular link blue; a chevron at the trailing
            // edge.
            HStack(spacing: 0) {
                // A root-level stub (more top-level comments) has no bar.
                if stub.depth > 0 {
                    Capsule()
                        .fill(barColor)
                        .frame(width: 2, height: 21)
                        .padding(.trailing, 16)
                }
                // Apollo's two presentations of a `more` object: "N more replies" for
                // the resolvable kind, and the verbatim "Continue thread\u{2026}" for
                // Reddit's depth-limit marker, which stands for an unknown number of
                // replies.
                Text(stub.isContinueThread
                     ? "Continue thread\u{2026}"
                     : (stub.count == 1 ? "1 more reply" : "\(stub.count) more replies"))
                    // 14pt, matching the cap height of the 15pt body.
                    .apolloFont(size: 14)
                    .foregroundStyle(Self.linkBlue)
                Spacer(minLength: 0)
                if isResolving {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Self.linkBlue)
                        .padding(.trailing, 0.7)
                }
            }
            .frame(height: 39.3)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isResolving)
        .accessibilityIdentifier("comment.moreReplies.\(stub.id)")
    }
}

/// VoiceOver: one element per comment, read as "author, 35 points,
/// 2 hours ago, body". Activating it collapses, as Apollo's own
/// accessibility hint says, and the long-press menu's main actions are
/// rotor actions.
struct CommentAccessibility: ViewModifier {
    let label: String
    let author: String
    let voteState: Bool?
    let isSaved: Bool
    let onCollapse: () -> Void
    let onReply: () -> Void
    let onAuthor: () -> Void
    let onVote: (Int) -> Void
    let onSave: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint("Double tap to collapse, double tap and hold for actions")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onCollapse() }
            .accessibilityAction(named: voteState == true ? "Remove Upvote" : "Upvote") {
                onVote(voteState == true ? 0 : 1)
            }
            .accessibilityAction(named: voteState == false ? "Remove Downvote" : "Downvote") {
                onVote(voteState == false ? 0 : -1)
            }
            .accessibilityAction(named: "Reply") { onReply() }
            .accessibilityAction(named: isSaved ? "Unsave" : "Save") { onSave() }
            .accessibilityAction(named: "Go to \(author)") { onAuthor() }
    }
}

/// Comment-row geometry.
enum CommentRowMetrics {
    /// Horizontal step per reply depth.
    static let indentStep: CGFloat = 12
    /// From a reply's depth bar to its content.
    static let barToContent: CGFloat = 15
    /// A row's leading inset: 15pt at depth 0, else the bar's x.
    static func leadingInset(depth: Int) -> CGFloat {
        depth == 0 ? 15 : CGFloat(depth) * indentStep
    }
}

/// A post's flair label, inside the caller's capsule: custom emoji as
/// images at the text's height, as Apollo draws `:n_great_goal: Great
/// Goal`. Font and colour come from the caller.
struct LinkFlairLabel: View {
    let text: String
    let parts: [FlairPart]?

    var body: some View {
        let runs = FlairRuns.runs(text: text, parts: parts)
        HStack(spacing: 2) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case .emoji(let url):
                    CachedAsyncImage(url: url)
                        .frame(width: 15, height: 15)
                case .text(let value):
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { Text(trimmed) }
                }
            }
        }
    }
}

enum FlairRuns {
    /// Rich parts when Reddit sent any, else the plain text with its
    /// `:emoji:` codes stripped.
    static func runs(text: String, parts: [FlairPart]?) -> [FlairPart.Kind] {
        if let parts, !parts.isEmpty { return parts.map(\.kind) }
        let stripped = text.replacingOccurrences(of: #":[A-Za-z0-9_+\-]+:"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? [] : [.text(stripped)]
    }
}

/// A commenter's flair as Apollo draws it: a 16pt rounded pill (5pt
/// corners) in #1A1A1A with #616269 text at the username's size, custom
/// emoji as 16pt images. Reddit's `:flag-me:` codes are the emoji's
/// names, so they are replaced by their images rather than printed.
struct CommentFlairPill: View {
    let text: String
    let parts: [FlairPart]?
    let textColor: Color?
    let fill: Color?

    private static let defaultFill = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    private static let defaultText = Color(red: 97 / 255, green: 98 / 255, blue: 105 / 255)

    /// Rich parts when Reddit sent any, else the plain text with its
    /// `:emoji:` codes stripped.
    private var runs: [FlairPart.Kind] { FlairRuns.runs(text: text, parts: parts) }

    var body: some View {
        let runs = self.runs
        if !runs.isEmpty {
            HStack(spacing: 1) {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    switch run {
                    case .emoji(let url):
                        CachedAsyncImage(url: url)
                            .frame(width: 16, height: 16)
                    case .text(let value):
                        let trimmed = value.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            Text(trimmed)
                                .apolloFont(size: 14.5)
                                .lineLimit(1)
                                .foregroundStyle(textColor ?? Self.defaultText)
                        }
                    }
                }
            }
            .padding(.leading, runs.first.map { if case .emoji = $0 { return 4.7 } else { return 5.7 } } ?? 5.7)
            .padding(.trailing, 5.7)
            .frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill ?? Self.defaultFill))
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Reborn's deleted-comment reason pill: bold text at 0.82× the body
/// size in #6B0F0F on #FFA8A3, 9pt side and 2.5pt vertical padding,
/// fully rounded.
struct DeletedReasonChip: View {
    let label: String

    var body: some View {
        Text(label)
            // Reborn asks for the body font's bold trait, which renders with
            // semibold-width strokes.
            .apolloFont(size: 15 * 0.82, weight: .semibold)
            .foregroundStyle(Color(red: 0.42, green: 0.06, blue: 0.06))
            .padding(.horizontal, 9)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color(red: 1.0, green: 0.66, blue: 0.64)))
    }
}

/// Reborn's full-row tint behind a recovered comment.
enum DeletedCommentHighlight {
    static func color(for reason: DeletedCommentReason) -> Color {
        switch reason {
        // (37, 3, 5) over the black page.
        case .userDeleted: return Color(red: 0.82, green: 0.02, blue: 0.08).opacity(0.16)
        case .moderatorRemoved: return Color.red.opacity(0.24)
        }
    }
}
