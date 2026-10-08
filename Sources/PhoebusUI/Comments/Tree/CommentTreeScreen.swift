import SwiftUI
import PhoebusCore

/// Comment tree screen: Apollo's post-detail comment view. Renders
/// depth-indented comments with per-depth color bars (Apollo's comment color
/// themes) and tap-to-collapse. A standalone wrapper around
/// `CommentTreeContent`, used when comments are shown without full post detail
/// (e.g. inbox reply-to links).
public struct CommentTreeScreen: View {
    let subreddit: String
    let postID: String
    let repository: RedditRepository
    @State private var sort = GeneralSettingsStore.load().defaultCommentSort
    @State private var jumpUser: String?
    /// The post, fetched so comments can be shared as images.
    @State private var post: RedditPost?
    @State private var commentShareAsImage: CommentShareTarget?
    @StateObject private var store = CommentTreeStore()
    /// Gives moderators Approve/Remove/Mark Spam actions on individual
    /// comments, gated on subreddit mod status.
    @State private var isModerator = false
    /// Reborn's comments-screen globe: translates this thread (or shows its
    /// originals), leaving the app-wide setting alone. Starts from the setting.
    @State private var threadTranslated = TranslationSettings.threadStartsTranslated(TranslationSettingsStore.load())

    /// Reddit's comment sort options ("confidence" is Reddit's name for "Best").
    /// "Live" is Reborn's "Live Update" sort and its auto-refresh UX.
    static let sorts: [(label: String, value: String)] = [
        ("Best", "confidence"),
        ("Top", "top"),
        ("New", "new"),
        ("Controversial", "controversial"),
        ("Old", "old"),
        ("Q&A", "qa"),
        ("Live", "live"),
    ]

    /// The comment an Inbox reply refers to: opens the post header, the
    /// parent chain, and this comment drawn highlighted, scrolled to the
    /// top. `nil` for a normal thread opening.
    public var focusedCommentID: String?
    @State private var hasScrolledToFocusedComment = false

    public init(subreddit: String, postID: String, repository: RedditRepository, focusedCommentID: String? = nil) {
        self.subreddit = subreddit
        self.postID = postID
        self.repository = repository
        self.focusedCommentID = focusedCommentID
    }

    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedComments) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        ScrollViewReader { scrollProxy in
            List {
                CommentTreeContent(store: store, subreddit: subreddit, postID: postID, repository: repository, post: post, sort: sort, isModerator: isModerator, onAuthorTapped: { jumpUser = $0 },
                                   onShareAsImage: { comment, parents in
                                       commentShareAsImage = CommentShareTarget(comment: comment, parents: parents)
                                   },
                                   highlightedCommentID: focusedCommentID)
                    .id(sort)
            }
            // See `PostDetailScreen`: comment rows size to their content.
            .environment(\.defaultMinListRowHeight, 1)
            // See `PostDetailScreen`: room under the last comment.
            .modifier(ApolloTabBarClearance())
            // Parent Comment swipe.
            .onChange(of: store.scrollRequest) { _, target in
                guard let target else { return }
                withAnimation { scrollProxy.scrollTo(target, anchor: .top) }
                store.scrollRequest = nil
            }
            // Stock dark surface + Pure Black tiers (`ApolloStockSurface`).
            .scrollContentBackground(.hidden)
            .apolloStockSurface()
            // Loading is driven here, at the top-level `List`, rather than inside
            // `CommentTreeContent`'s own `.task`; see `CommentTreeStore`.
            .task(id: sort) { await store.fetch(subreddit: subreddit, postID: postID, sort: sort, repository: repository) }
            // Land on the linked comment, at the top. `scrollTo` resolves against the
            // realized row, so waiting for the tree to arrive is enough.
            .onChange(of: store.roots.count) { _, _ in
                guard let focusedCommentID, !hasScrolledToFocusedComment, !store.roots.isEmpty else { return }
                hasScrolledToFocusedComment = true
                withAnimation { scrollProxy.scrollTo(store.rowID(focusedCommentID), anchor: .top) }
            }
            // Pull-to-refresh. `force: true` because `fetch` no-ops for
            // an already-loaded (postID, sort).
            .refreshable {
                await store.fetch(subreddit: subreddit, postID: postID, sort: sort, repository: repository, force: true)
            }
            .environment(\.threadTranslation, threadTranslated)
            .task { isModerator = (try? await repository.fetchSubredditInfo(name: subreddit).userIsModerator) == true }
            .task { post = try? await repository.fetchPost(subreddit: subreddit, postID: postID) }
            .sheet(item: $commentShareAsImage) { target in
                if let post {
                    ShareAsImageScreen(post: post, comment: target.comment,
                                       availableParents: target.parents, repository: repository)
                }
            }
            // Reborn's "Deleted Comments" archive recovery; see
            // `CommentTreeStore.fetchArchivedCommentsIfNeeded`. Fetches only in Always
            // mode (Passive mode's fetch is triggered by the "..." menu shortcut below,
            // once the user opts a thread in).
            .task { await store.fetchArchivedCommentsIfNeeded(postID: postID) }
            .onDisappear { store.stopLivePolling() }
            // "At the live edge" is approximated from `visibleTopLevelRootID` (updated by
            // each top-level row's `.onAppear`), since SwiftUI's `List` doesn't expose
            // scroll offset: whether the first comment is in view is the same FOLLOW/READ
            // signal, pinned to the newest vs. reading further down.
            .onChange(of: store.visibleTopLevelRootID) { _, newValue in
                guard sort == "live" else { return }
                store.isAtLiveEdge = (newValue == nil) || (newValue == store.roots.first?.id)
            }
            .safeAreaInset(edge: .top) {
                if sort == "live", store.liveNewCount > 0 {
                    Button {
                        Task {
                            await store.jumpToLiveEdge(subreddit: subreddit, postID: postID, repository: repository)
                            if let firstID = store.roots.first?.id {
                                withAnimation { scrollProxy.scrollTo(store.rowID(firstID), anchor: .top) }
                            }
                        }
                    } label: {
                        Label("\(store.liveNewCount) new comment\(store.liveNewCount == 1 ? "" : "s")", systemImage: "chevron.up")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.apolloAccent))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("commentTree.liveNewCommentsPill")
                }
            }
            // Unwinds with the rest of the Posts tab on a tab re-tap.
            .apolloPopsOnTabReselection(item: $jumpUser)
            .navigationDestination(item: $jumpUser) { username in
                UserProfileScreen(username: username, repository: repository)
            }
            .apolloTracksForwardNavigation($jumpUser)
            .apolloOpensRedditTargetsHere()
            .apolloForwardSwipe()
            .apolloFlatListAppearance()
            .navigationTitle("Comments")
            .apolloCentersTitle("Comments", key: "comments.\(postID)")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Every row carries its own Apollo sort icon, and the
                    // toolbar glyph reflects the active sort.
                    Menu {
                        ForEach(Self.sorts, id: \.value) { option in
                            Button {
                                sort = option.value
                            } label: {
                                // Icon rows carry no checkmark; only
                                // icon-less rows get one.
                                Label(option.label,
                                      systemImage: PostDetailScreen.iconName(forCommentSort: option.value))
                            }
                        }
                    } label: {
                        Image(systemName: PostDetailScreen.iconName(forCommentSort: sort))
                        .accessibilityLabel("Sort Comments")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        threadTranslated.toggle()
                    } label: {
                        Image(systemName: "globe")
                        .accessibilityLabel(threadTranslated ? "Show Original" : "Translate Thread")
                    }
                    .tint(threadTranslated ? .green : nil)
                    .accessibilityIdentifier("commentTree.bulkTranslateToggle")
                }
                // Comments "..." menu shortcut; see
                // `CommentTreeStore.toggleDeletedCommentsShortcut`.
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await store.toggleDeletedCommentsShortcut(postID: postID) }
                        } label: {
                            Label(
                                store.deletedCommentsRecoveryActive ? "Hide Deleted Comments" : "Show Deleted Comments",
                                systemImage: store.deletedCommentsRecoveryActive ? "eye.slash" : "eye"
                            )
                        }
                        .accessibilityIdentifier("commentTree.deletedCommentsShortcut")
                    } label: {
                        Image(systemName: "ellipsis")
                        .accessibilityLabel("More")
                    }
                    .accessibilityIdentifier("commentTree.overflowMenu")
                }
            }
        }
    }
}

/// Reusable comment-tree content for any List (its own screen, or a section
/// within `PostDetailScreen`).
struct CommentTreeContent: View {
    @Setting(DeletedCommentsSettings.self) private var deletedCommentsSettings
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: CommentTreeStore
    @State private var replyTargetID: String?
    /// Target for the Share swipe action.
    @State private var shareCommentTarget: RedditComment?
    @State private var quotedText: [String: String] = [:]
    /// Quote-reply preview: the quoted comment's author and snippet,
    /// for the card docked above the composer toolbar.
    @State private var quotedPreview: [String: (author: String, snippet: String, age: String?)] = [:]
    @Setting(SwipeActionStore.storage(for: .comments)) private var swipeSettings

    let subreddit: String
    let postID: String
    let repository: RedditRepository
    /// The post these comments belong to, when the caller has it.
    /// Needed for Share as Image: the card renders a comment under its
    /// post's title, so a comment alone is not enough.
    var post: RedditPost? = nil
    var sort: String = "confidence"
    /// See `CommentTreeScreen.isModerator`; threaded down so `CommentRow`'s
    /// context menu can show Approve/Remove/Mark Spam.
    var isModerator: Bool = false
    /// Reports a tapped commenter's username up to the hosting screen
    /// so it can navigate to that user's profile.
    var onAuthorTapped: ((String) -> Void)?
    /// Presents Share as Image for a comment and its ancestors. This view
    /// is a group of rows inside the host's `List`, where a `.sheet` of
    /// its own does not reliably present, so the host screen owns it.
    var onShareAsImage: ((RedditComment, [RedditComment]) -> Void)?
    /// The comment an Inbox reply linked to, drawn highlighted. See
    /// `CommentTreeScreen.focusedCommentID`.
    var highlightedCommentID: String?

    /// Apollo's named comment palettes (Rainbow, Combustion, Ocean, Forest, Nuit,
    /// Blep), with a generic rainbow-by-depth cycle as the default. Sourced from
    /// the active theme's palette or the user's "Comments Theme" override.
    /// Computed per render so a palette change applies without a relaunch.
    private var depthColors: [Color] {
        CommentsThemeStore.effectiveHexes(theme: ThemeStore.load()).map(Color.init(hex:))
    }

    var body: some View {
        Group {
            if let errorMessage = store.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            // The comment list's own loading and empty states, drawn as list cells
            // rather than an overlay.
            if store.roots.isEmpty && store.errorMessage == nil {
                if store.isLoadingComments {
                    ApolloLoadingCell()
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("comments.loading")
                } else {
                    Text("No comments yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("comments.empty")
                }
            }
            ForEach(flattenedVisible(), id: \.id) { item in
                switch item {
                case .comment(let node):
                    VStack(alignment: .leading, spacing: 4) {
                        CommentRow(
                            node: node,
                            depthColors: depthColors,
                            repository: repository,
                            isNew: store.newCommentIDs.contains(node.id),
                            // The comment an Inbox reply pointed at, drawn highlighted.
                            isLinkedToComment: highlightedCommentID == node.id,
                            isModerator: isModerator,
                            // Reborn "Deleted Comments" archive recovery; see
                            // `CommentRow.archivedComment`. Only for a comment Reddit shows as
                            // deleted/removed: Arctic Shift archives every comment in a thread, so
                            // matching by fullname alone would replace live comments too.
                            archivedComment: CommentTreeStore.archivedCopy(
                                for: node.comment,
                                recoveryActive: store.deletedCommentsRecoveryActive,
                                archive: store.archivedComments),
                            tapToReveal: deletedCommentsSettings.tapToReveal,
                            isRevealed: store.revealedFullnames.contains(node.comment.name),
                            onReveal: { store.revealComment(node.comment.name) },
                            onToggleCollapse: { toggleCollapse(node) },
                            onReplyTapped: { replyTargetID = (replyTargetID == node.id) ? nil : node.id },
                            onQuoteTapped: {
                                // Apollo's select-mode "Quote" action: pre-fills the reply composer with
                                // the comment text as a markdown blockquote.
                                quotedText[node.id] = RedditMarkdown.asBlockquote(node.comment.body)
                                quotedPreview[node.id] = (author: node.comment.author, snippet: node.comment.body, age: node.comment.created.apolloRelativeTime)
                                replyTargetID = node.id
                            },
                            onAuthorTapped: { onAuthorTapped?(node.comment.author) },
                            onShareAsImage: shareAsImageAction(for: node.comment)
                        )
                        // Reborn "Siri & Spotlight" (#1299): the comment, for onscreen context.
                        .siriCommentContext(node.comment.name)
                        .onAppear {
                            // See `CommentTreeStore.visibleTopLevelRootID`: only depth-0 comments update
                            // this, since the floating collapse button targets a whole top-level thread.
                            if node.depth == 0 {
                                store.visibleTopLevelRootID = node.id
                                store.onScreenRootIDs.insert(node.id)
                            }
                        }
                        .onDisappear {
                            if node.depth == 0 { store.onScreenRootIDs.remove(node.id) }
                        }
                    }
                    // Replying opens the full-screen "New Comment" modal
                    // rather than an inline caption-sized field.
                    .sheet(isPresented: Binding(
                        get: { replyTargetID == node.id },
                        set: { if !$0 { replyTargetID = nil } }
                    )) {
                        CommentComposerScreen(
                            parentFullname: node.comment.name,
                            repository: repository,
                            quotedPreview: quotedPreview[node.id],
                            initialText: quotedText[node.id] ?? "",
                            subreddit: subreddit,
                            onSubmitted: {
                                replyTargetID = nil
                                quotedText[node.id] = nil
                                quotedPreview[node.id] = nil
                                Task { await store.fetch(subreddit: subreddit, postID: postID, sort: sort, repository: repository, force: true) }
                            },
                            onPosted: { posted in
                                replyTargetID = nil
                                quotedText[node.id] = nil
                                quotedPreview[node.id] = nil
                                if !store.insertPosted(posted, parentFullname: node.comment.name) {
                                    Task { await store.fetch(subreddit: subreddit, postID: postID, sort: sort, repository: repository, force: true) }
                                }
                            }
                        )
                    }
                    .apolloSwipeActions(settings: swipeSettings, subject: SwipeSubject(comment: node.comment)) { action in
                        Task { await handleSwipeAction(action, on: node) }
                    }
                    // Apollo's hairline sits on top of each row, starting at that row's own
                    // indent (the depth bar's x), and runs to the screen edge.
                    .listRowSeparator(.hidden)
                    // Reborn tints a recovered comment's whole cell.
                    .listRowBackground(recoveredHighlight(for: node))
                    .listRowInsets(EdgeInsets(top: node.isCollapsed ? 10.5 : 10, leading: CommentRowMetrics.leadingInset(depth: node.depth), bottom: node.isCollapsed ? 10.5 : 11, trailing: 16))
                    // A collapsed row is 48pt between rules.
                    .overlay(alignment: .top) {
                        rowRule(depth: node.depth, topInset: node.isCollapsed ? 10.5 : 10)
                    }
                    // Changes with each collapse toggle; see
                    // `CommentTreeStore.rowGeneration`.
                    .id(store.rowID(node.id))
                case .more(let stub):
                    // A tappable "N more replies" row, indented to the
                    // stub's thread depth, that lazily resolves Reddit's
                    // `more` continuation object via `/api/morechildren`.
                    MoreRepliesRow(stub: stub, depthColors: depthColors, isResolving: store.resolvingStubIDs.contains(stub.id)) {
                        Task { await store.resolveMoreStub(stub, repository: repository) }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: CommentRowMetrics.leadingInset(depth: stub.depth), bottom: 0, trailing: 16))
                    .overlay(alignment: .top) {
                        rowRule(depth: stub.depth, topInset: 0)
                    }
                    .id(stub.id)
                }
            }
        }
        .sheet(item: $store.deletedMoreStubExplanation) { stub in
            DeletedMoreCommentsExplanationScreen(stub: stub) {
                store.deletedMoreStubExplanation = nil
            }
        }
        // Share swipe action for comments; see `handleSwipeAction`.
        .sheet(item: $shareCommentTarget) { comment in
            ActivityShareSheet(items: [comment.shareURL()])
        }
    }

    /// Share as Image is offered only when the owner supplied a post,
    /// since the card renders the comment under its post's title.
    private func shareAsImageAction(for comment: RedditComment) -> (() -> Void)? {
        guard post != nil, let onShareAsImage else { return nil }
        return { onShareAsImage(comment, ancestors(of: comment)) }
    }

    /// The chain of comments above `comment`, nearest parent last. Backs the
    /// Parent Comments stepper, which lets a comment share pull in N ancestors for
    /// context.
    private func ancestors(of comment: RedditComment) -> [RedditComment] {
        var byName: [String: RedditComment] = [:]
        for node in store.roots.flatMap({ $0.flattenedAll() }) {
            byName[node.comment.name] = node.comment
        }
        var chain: [RedditComment] = []
        var currentParent = comment.parentID
        // Bounded: a malformed parent chain must not spin forever.
        while chain.count < 16, let parent = byName[currentParent] {
            chain.append(parent)
            currentParent = parent.parentID
        }
        return chain.reversed()
    }

    private func recoveredHighlight(for node: CommentTreeNode) -> Color? {
        guard let archived = CommentTreeStore.archivedCopy(
            for: node.comment,
            recoveryActive: store.deletedCommentsRecoveryActive,
            archive: store.archivedComments) else { return nil }
        return DeletedCommentHighlight.color(for: archived.reason)
    }

    /// The hairline above a comment-list row, from its indent to the
    /// screen's trailing edge.
    private func rowRule(depth: Int, topInset: CGFloat) -> some View {
        Rectangle()
            .fill(Color.apolloSeparator(colorScheme: colorScheme))
            .frame(height: 1.0 / 3.0)
            .padding(.trailing, -16)
            .offset(y: -topInset)
    }

    private func flattenedVisible() -> [CommentDisplayValue] {
        var items = store.roots.flatMap { $0.visibleFlattenedWithMore() }
        if let rootStub = store.rootMoreStub {
            items.append(.more(rootStub))
        }
        return items
    }

    private func toggleCollapse(_ node: CommentTreeNode) {
        store.toggleCollapse(node)
    }

    private func handleSwipeAction(_ action: SwipeAction, on node: CommentTreeNode) async {
        await ContentActions.perform(action, on: node.comment, repository: repository, hooks: SwipeActionHooks(
            onReply: { replyTargetID = (replyTargetID == node.id) ? nil : node.id },
            onShare: { shareCommentTarget = node.comment },
            // Reddit cannot hide comments, so Hide collapses the comment.
            onHide: { toggleCollapse(node) },
            // Apollo's default collapses the whole top-level thread.
            onCollapseTop: {
                if let topLevelRoot = store.roots.first(where: { $0.contains(id: node.id) }) {
                    toggleCollapse(topLevelRoot)
                }
            },
            onCollapse: { toggleCollapse(node) },
            onParentComment: {
                // The host's list scrolls to it (`scrollRequest`).
                let parentID = node.comment.parentID
                guard parentID.hasPrefix("t1_") else { return }
                store.scrollRequest = store.rowID(String(parentID.dropFirst(3)))
            },
            author: node.comment.author, subreddit: subreddit,
            selectableText: (title: node.comment.author, body: node.comment.body)
        ))
    }
}

/// Caches the signed-in username per account, so resolving it per row doesn't
/// fire one `/api/v1/me` request per comment. Keyed by the repository, which
/// `AccountManager` rebuilds on every account switch, so a name never carries
/// over to another account's comments.
actor CurrentUsernameCache {
    private static let shared = CurrentUsernameCache()

    private var owner: ObjectIdentifier?
    private var cached: String?
    private var inFlight: Task<String?, Never>?

    static func username(repository: RedditRepository) async -> String? {
        await shared.resolve(repository: repository)
    }

    private func resolve(repository: RedditRepository) async -> String? {
        let id = ObjectIdentifier(repository)
        if owner != id {
            owner = id
            cached = nil
            inFlight = nil
        }
        if let cached { return cached }
        // Coalesce concurrent callers into one request.
        if let inFlight { return await inFlight.value }
        let task = Task<String?, Never> { try? await repository.fetchIdentity().name }
        inFlight = task
        let name = await task.value
        guard owner == id else { return name }
        cached = name
        inFlight = nil
        return name
    }
}
