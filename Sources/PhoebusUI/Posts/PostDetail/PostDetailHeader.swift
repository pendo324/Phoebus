import SwiftUI
import PhoebusCore

struct PostDetailHeader: View {
    /// "Translate Post Titles" result (see `TitleTranslation`).
    @State private var translatedTitle: String?
    /// The post action bar follows the active theme's accent, not
    /// SwiftUI's own `.accentColor`, matching every other call site.
    @Environment(\.apolloTheme) private var apolloTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var actionTint: Color { apolloTheme.color(.accent) ?? .accentColor }

    /// 15pt regular, distinct from the 17pt comment body size.
    static let bodyFontSize: CGFloat = 15

    /// The byline avatars' diameter.
    static let bylineAvatarSize: CGFloat = 24

    let post: RedditPost
    let repository: RedditRepository
    /// Per-subreddit flair colors, gated on "Color Flairs"
    /// (`GeneralSettings.enableFlairColors`, default true).
    private var linkFlairTextColor: Color? {
        guard general.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: post.linkFlairTextColorRaw).map(Color.init(hex:))
    }
    private var linkFlairBackgroundColor: Color? {
        guard general.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: post.linkFlairBackgroundColor).map(Color.init(hex:))
    }
    private var bylineScale: CGFloat { dynamicTypeSize.isAccessibilitySize ? 0.5 : 1 }

    private var authorFlairTextColor: Color? {
        guard general.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: post.authorFlairTextColorRaw).map(Color.init(hex:))
    }
    private var authorFlairBackgroundColor: Color? {
        guard general.enableFlairColors else { return nil }
        return RedditFlairColor.validHex(from: post.authorFlairBackgroundColor).map(Color.init(hex:))
    }
    /// Tapping the post's own subreddit/author (in the header, not
    /// the feed row) should navigate there too.
    var onSubredditTap: () -> Void = {}
    var onAuthorTap: () -> Void = {}
    var onJumpToComments: (() -> Void)?
    /// Opens the composer from the header's own action bar
    /// (upvote/downvote/save/reply/share).
    var onReply: (() -> Void)?
    /// Drives the inline AI summary cards. Optional so the header
    /// still renders standalone in previews.
    var aiSummary: AISummaryController?
    @ObservedObject private var voteStore = VoteStateStore.shared
    @Setting(GeneralSettings.self) private var general
    private var voteState: Bool? { voteStore.vote(for: post.name, serverValue: post.likes) }
    @State private var showingVoteBreakdown = false
    @Setting(InfoRowSettings.self) private var infoRow
    @State private var selfTextCollapsed = false
    @State private var isEditing = false
    @State private var editedText: String
    @State private var isOwnPost = false
    @State private var isDeleted = false
    /// The body as last saved from the editor, shown until the post
    /// is reloaded (the post passed in still has the old text).
    @State private var savedEdit: String?
    /// The post-detail action row: five icon-only buttons, upvote,
    /// downvote, bookmark, reply, share.
    private var isSaved: Bool { voteStore.isSaved(post.name, serverValue: post.saved) }
    /// With this device's own vote, as the feed row shows it.
    private var displayScore: Int { post.score + voteStore.scoreDelta(for: post.name) }

    init(post: RedditPost, repository: RedditRepository, onSubredditTap: @escaping () -> Void = {}, onAuthorTap: @escaping () -> Void = {}, onJumpToComments: (() -> Void)? = nil, onReply: (() -> Void)? = nil, aiSummary: AISummaryController? = nil) {
        self.onReply = onReply
        self.aiSummary = aiSummary
        self.post = post
        self.onJumpToComments = onJumpToComments
        self.repository = repository
        self.onSubredditTap = onSubredditTap
        self.onAuthorTap = onAuthorTap
        _editedText = State(initialValue: post.selftext ?? "")
    }

    /// Image, GIF, video and gallery posts open with their media across the full
    /// width, above the title; link cards, text posts and polls keep the title first.
    private var mediaLeads: Bool {
        guard !isDeleted, post.pollData == nil, !post.isSelf, post.crosspostParent == nil else { return false }
        switch PostMediaKind.classify(post: post) {
        case .image, .gif, .video, .redgifs, .gfycat, .streamable, .gallery, .imgurAlbum:
            return true
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mediaLeads {
                PostMediaView(kind: .classify(post: post), contentWarning: PostMediaView.contentWarning(for: post), onJumpToComments: onJumpToComments, votePost: post, voteRepository: repository, onDoubleTapMedia: {
                    Task { await vote(direction: voteState == true ? 0 : 1) }
                })
            }
            content
                .padding(.horizontal, 16)
                .padding(.top, mediaLeads ? 12 : 19)
                .padding(.bottom, 12.7)
        }
        .task { await checkOwnership() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The flair follows the last word of the title and wraps with it.
            // `TitleFlairLayout` (not plain `FlowLayout`) since a lone `Text` inside a flow
            // never wraps. The title toggles the collapse: collapsing hides the body rather
            // than truncating it. Measured at the same Dynamic Type size the `Text` draws at,
            // or the flair lands on words at larger text sizes.
            TitleFlairLayout(titleString: translatedTitle ?? post.title,
                             fontSize: ScaledSystemFont.scaled(20, style: .body, for: dynamicTypeSize),
                             bold: true, gap: 6, lineSpacing: 3) {
                Text(translatedTitle ?? post.title)
                    .apolloFont(size: 20, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.apolloPrimaryText(
                        colorScheme: colorScheme, themeColors: apolloTheme))
                if post.over18 || post.linkFlairText?.isEmpty == false {
                HStack(spacing: 6) {
                if post.over18 { NSFWTag() }
                if let flair = post.linkFlairText, !flair.isEmpty {
                    // Same 13pt text in an 18pt capsule as the feed row.
                    LinkFlairLabel(text: flair, parts: post.linkFlairRichtext)
                        .apolloFont(size: 13)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .foregroundStyle(linkFlairTextColor ?? Color.apolloTertiaryText(
                            colorScheme: colorScheme, themeColors: apolloTheme))
                        .background(Capsule().fill(linkFlairBackgroundColor ?? Color.apolloFlairFill(colorScheme: colorScheme)))
                }
                }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let selftext = post.selftext, !selftext.isEmpty else { return }
                selfTextCollapsed.toggle()
            }
            .accessibilityIdentifier("postDetail.titleCollapseToggle")
            .apolloTranslatesTitle(post.title, into: $translatedTitle)
            if translatedTitle != nil {
                TitleTranslationMarker(original: post.title)
            }
            if isDeleted {
                Text("[deleted]").italic().foregroundStyle(.secondary)
            } else if post.pollData != nil {
                // Native Reddit polls are self-posts, so the `post.isSelf` branch would catch
                // them first and make `PostMediaView`'s `.poll` kind unreachable. Checked before
                // `isSelf`, as Devvit detection is inside `PostMediaKind.classify`.
                if let selftext = post.selftext, !selftext.isEmpty {
                    // Collapsing the body hides it entirely, not a truncated line budget.
                    if !selfTextCollapsed {
                        InlineMediaBodyView(selftext, mediaMetadata: post.mediaMetadata, linkContext: .body)
                            .apolloFont(size: Self.bodyFontSize)
                            .foregroundStyle(Color.apolloPrimaryText(
                                colorScheme: colorScheme, themeColors: apolloTheme))
                            .onTapGesture { selfTextCollapsed.toggle() }
                    }
                }
                PostMediaView(kind: .classify(post: post), contentWarning: PostMediaView.contentWarning(for: post), onJumpToComments: onJumpToComments, votePost: post, voteRepository: repository)
            } else if post.isSelf {
                if isEditing {
                    TextEditor(text: $editedText)
                        .frame(minHeight: 100)
                    HStack {
                        Button("Cancel") { isEditing = false }
                        Button("Save") { Task { await saveEdit() } }
                    }
                } else if let selftext = savedEdit ?? post.selftext, !selftext.isEmpty {
                    // Anchor 2: immediately above the body markdown,
                    // so on a plain text post the card sits between
                    // the title and the body.
                    postSummaryCard
                    // Collapsing the body hides it entirely, not a truncated line budget.
                    if !selfTextCollapsed {
                        InlineMediaBodyView(selftext, mediaMetadata: post.mediaMetadata, linkContext: .body)
                            .apolloFont(size: Self.bodyFontSize)
                            .foregroundStyle(Color.apolloPrimaryText(
                                colorScheme: colorScheme, themeColors: apolloTheme))
                            .onTapGesture { selfTextCollapsed.toggle() }
                    }
                }
            } else {
                // Media first, then body text: a link/gallery post's media is the post. The
                // double-tap is handed down to the media view because an outer
                // `.onTapGesture(count: 2)` swallows the single tap that opens the fullscreen
                // pager. See `apolloMediaPager`. A crosspost is its card alone, as in Apollo.
                if !mediaLeads, post.crosspostParent == nil {
                    PostMediaView(kind: .classify(post: post), contentWarning: PostMediaView.contentWarning(for: post), onJumpToComments: onJumpToComments, votePost: post, voteRepository: repository, onDoubleTapMedia: {
                        Task { await vote(direction: voteState == true ? 0 : 1) }
                    })
                }
                // Anchor 1: directly below the link-preview card.
                if post.crosspostParent == nil { postSummaryCard }
                if let selftext = post.selftext, !selftext.isEmpty {
                    // A spoiler-marked post must hide its body too, not
                    // just its media, since `PostMediaView.contentWarning`
                    // only gates the media node.
                    if !selfTextCollapsed {
                        SpoilerGatedBody(
                            text: selftext,
                            isHidden: PostMediaView.contentWarning(for: post) != nil,
                            lineLimit: nil
                        ) { selfTextCollapsed.toggle() }
                        .apolloFont(size: Self.bodyFontSize)
                        .foregroundStyle(Color.apolloPrimaryText(
                            colorScheme: colorScheme, themeColors: apolloTheme))
                    }
                }
            }

            // Byline row: subreddit avatar + name, "by", author avatar
            // + name, no "in" prefix and no `r/`/`u/` markers.
            HStack(spacing: 4) {
                Button(action: onSubredditTap) {
                    HStack(spacing: 8) {
                        SubredditIconView(subreddit: post.subreddit,
                                          repository: repository,
                                          size: Self.bylineAvatarSize)
                        // Apollo's display capitalization: the byline reads "iOSProgramming", not
                        // "iosprogramming".
                        Text(SubredditCapitalization.display(post.subreddit))
                            .apolloFont(size: 15, weight: .semibold)
                            // At accessibility text sizes the name shrinks rather than splitting mid-word; at
                            // normal sizes the row could hand the names a too-narrow pass and leave them at
                            // half size, so they truncate.
                            .lineLimit(1)
                            .minimumScaleFactor(bylineScale)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("postDetail.subredditLink")
                Text("by")
                    .apolloFont(size: 15)
                Button(action: onAuthorTap) {
                    HStack(spacing: 4) {
                        AvatarView(username: post.author,
                                   repository: repository,
                                   size: Self.bylineAvatarSize)
                        Text(post.author)
                            .apolloFont(size: 15, weight: .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(bylineScale)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("postDetail.authorLink")
                .contextMenu {
                    Button {
                        PasteboardHelper.copy(post.author)
                    } label: {
                        Label("Copy Username", systemImage: "doc.on.doc")
                    }
                }
                // "User Flair" toggle (Settings > Appearance > Flair).
                if general.showUserFlair, let authorFlair = post.authorFlairText, !authorFlair.isEmpty {
                    // One line: a long flair truncates rather than
                    // wrapping into a tall pill beside the byline.
                    Text(authorFlair)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                        .padding(.horizontal, 4)
                        .foregroundStyle(authorFlairTextColor ?? .secondary)
                        .background(Capsule().fill(authorFlairBackgroundColor ?? Color.secondary.opacity(0.15)))
                }
                if post.authorCakeday == true {
                    Text("🎂").accessibilityLabel("Cake day")
                }
                // "Show Awards" toggle (Settings > Appearance > Other).
                if general.showAwards, let awards = post.totalAwardsReceived, awards > 0 {
                    Label("\(awards)", systemImage: "medal.fill")
                        .foregroundStyle(.yellow)
                }
                Spacer(minLength: 0)
            }
            .apolloFont(size: 15)
            // Byline grey #94969C; `.secondary` resolves lighter.
            .foregroundStyle(Color.apolloSecondaryText(
                colorScheme: colorScheme, themeColors: apolloTheme))
            .accessibilityIdentifier("postDetail.byline")

            // Score, upvote ratio, age, in Apollo's own glyphs
            // (`posts-points`, `posts-liked`, `posts-clock`) at 13pt
            // with 9pt cluster gaps. See `StockIcon`.
            HStack(spacing: 9) {
                HStack(spacing: 5) {
                    StockIcon("posts-points")
                    // Abbreviated like the feed: "10.9K".
                    Text(displayScore.apolloAbbreviated)
                }
                // Info Row Popup / Overlay: the % and the age explain themselves on a tap, as in
                // Reborn.
                if let ratio = post.upvoteRatio {
                    HStack(spacing: 5) {
                        StockIcon("posts-liked")
                        Text("\(Int((ratio * 100).rounded()))%")
                    }
                    .modifier(InfoRowDetailTap(popup: infoRow.popupMode, overlay: infoRow.overlayMode, edge: .leading) { condensed in
                        InfoRowPercentDetail.lines(score: displayScore, ratio: ratio, condensed: condensed)
                    })
                }
                HStack(spacing: 5) {
                    StockIcon("posts-clock")
                    Text(ShareCardFormatting.compactAge(since: post.created))
                }
                .modifier(InfoRowDetailTap(popup: infoRow.popupMode, overlay: infoRow.overlayMode, edge: .leading) { condensed in
                    InfoRowAgeDetail.lines(created: post.created, condensed: condensed)
                })
                Spacer(minLength: 0)
            }
            .apolloFont(size: 13)
            .foregroundStyle(Color.apolloSecondaryText(
                colorScheme: colorScheme, themeColors: apolloTheme))
            .accessibilityIdentifier("postDetail.metadata")

            // Hairline rule above the action bar.
            Rectangle()
                .fill(Color.apolloSeparator(colorScheme: colorScheme))
                .frame(height: 0.33)
                .padding(.horizontal, -1)
                .padding(.top, 4)
                .padding(.bottom, 12.5 - 8)

            // Tinted by the active theme, applied to the whole row
            // rather than per glyph since the enclosing stack's
            // `.foregroundStyle(.secondary)` would otherwise leak in.
            // Spread evenly via equal-width Spacer cells.
            HStack(spacing: 0) {
                Button {
                    Task { await vote(direction: voteState == true ? 0 : 1) }
                } label: {
                    // Glyph only; the score lives in the metadata row above.
                    StockIcon("option-upvote")
                        // The voted state is a colour change on the same glyph (Apollo's upvote orange);
                        // the bar has no filled or circled variant.
                        .foregroundStyle(voteState == true ? Color.orange : actionTint)
                }
                .accessibilityLabel(voteState == true ? "Remove Upvote" : "Upvote")
                .accessibilityAddTraits(voteState == true ? .isSelected : [])
                .accessibilityIdentifier("postDetail.upvote")
                Spacer(minLength: 0)
                // Long-press the score for an approximate vote breakdown.
                .onLongPressGesture { showingVoteBreakdown = true }
                .popover(isPresented: $showingVoteBreakdown) {
                    VoteBreakdownView(score: post.score, upvoteRatio: post.upvoteRatio)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
                Button {
                    Task { await vote(direction: voteState == false ? 0 : -1) }
                } label: {
                    StockIcon("option-downvote")
                        .foregroundStyle(voteState == false ? Color.blue : actionTint)
                }
                .accessibilityLabel(voteState == false ? "Remove Downvote" : "Downvote")
                .accessibilityAddTraits(voteState == false ? .isSelected : [])
                .accessibilityIdentifier("postDetail.downvote")
                Spacer(minLength: 0)
                // No comment-count control: Apollo's bar is up / down / save / reply / share.
                Button {
                    Task { await ContentActions.toggleSave(post, repository: repository) }
                } label: {
                    // Saved is a colour change on the same glyph, like the
                    // votes, in the green the saved-post wedge uses.
                    StockIcon("option-save")
                        .foregroundStyle(isSaved ? Color.green : actionTint)
                }
                .accessibilityLabel(isSaved ? "Unsave" : "Save")
                .accessibilityAddTraits(isSaved ? .isSelected : [])
                .accessibilityIdentifier("postDetail.save")
                Spacer(minLength: 0)
                if let onReply {
                    Button {
                        onReply()
                    } label: {
                        StockIcon("option-reply")
                    }
                    .accessibilityLabel("Reply")
                    .accessibilityIdentifier("postDetail.reply")
                Spacer(minLength: 0)
                }
                ShareLink(item: post.shareText()) {
                    StockIcon("option-share")
                }
                .accessibilityLabel("Share")
                .accessibilityIdentifier("postDetail.share")
                // No pencil/trash glyphs in this bar; own-post actions live in the long-press
                // menu below.
            }
            // Own-post Edit/Delete, evicted from the five-glyph bar.
            .contextMenu {
                if isOwnPost && post.isSelf && !isDeleted {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit Post", systemImage: "pencil")
                    }
                }
                if isOwnPost && !isDeleted {
                    Button(role: .destructive) {
                        Task { await deletePost() }
                    } label: {
                        Label("Delete Post", systemImage: "trash")
                    }
                }
            }
            // Glyphs use the theme accent.
            .padding(.leading, 25 - 16)
            .padding(.trailing, 393 - 369 - 16)
            .foregroundStyle(actionTint)
            .buttonStyle(.plain)
            // One symbol size for the whole quick bar: `.font` + `.imageScale` alone leave SF
            // Symbols at different proportions (`arrow.up` tall/narrow vs
            // `arrowshape.turn.up.left` squat/wide). A fixed square frame per icon with
            // `.symbolRenderingMode(.monochrome)` equalizes them.
            .apolloFont(size: 17)
            .imageScale(.medium)

            // Last child of the header stack, appended after the
            // action bar rather than inserted, immediately before the
            // first comment.
            discussionSummaryCard
        }
    }

    /// The post/link summary card. Placement follows
    /// `ApolloAIInsertPostSummary`: below the inline link-preview
    /// card, or failing that above the body markdown.
    @ViewBuilder
    private var postSummaryCard: some View {
        if let aiSummary, aiSummary.showsPostCard {
            AISummaryCardView(
                kind: aiSummary.postKind,
                state: aiSummary.postState,
                provider: aiSummary.provider,
                expanded: Binding(
                    get: { aiSummary.postExpanded },
                    set: { _ in aiSummary.toggleExpansion(isPost: true) }),
                onTap: { aiSummary.tapToGeneratePost() }
            )
        }
    }

    /// The "Discussion so far" card, appended after the action bar,
    /// immediately before the first comment.
    @ViewBuilder
    private var discussionSummaryCard: some View {
        if let aiSummary, aiSummary.commentState != .none {
            AISummaryCardView(
                kind: .discussion,
                state: aiSummary.commentState,
                provider: aiSummary.provider,
                sourceCount: aiSummary.commentSourceCount,
                expanded: Binding(
                    get: { aiSummary.commentExpanded },
                    set: { _ in aiSummary.toggleExpansion(isPost: false) }),
                onTap: { aiSummary.tapToGenerateComments() }
            )
        }
    }

    /// Mirrors Apollo's "Edit"/"Delete" own-content menu items, gated
    /// on whether the signed-in user authored this post.
    private func checkOwnership() async {
        if let username = await CurrentUsernameCache.username(repository: repository) {
            isOwnPost = username.caseInsensitiveCompare(post.author) == .orderedSame
        }
    }

    private func saveEdit() async {
        do {
            try await repository.editUserText(fullname: post.name, text: editedText)
            savedEdit = editedText
            isEditing = false
        } catch {
            // Leave editor open on failure so the user can retry.
        }
    }

    private func deletePost() async {
        // Only on success, so a failed delete does not show the post as deleted.
        guard (try? await repository.delete(fullname: post.name)) != nil else { return }
        isDeleted = true
    }

    private func vote(direction: Int) async {
        Haptics.light()
        await ContentActions.vote(post, direction: direction, repository: repository)
    }
}
