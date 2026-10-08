import SwiftUI
import PhoebusCore

/// Post detail screen: the full post (title, selftext or media, vote controls)
/// above the comment tree.
public struct PostDetailScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let post: RedditPost
    let repository: RedditRepository
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showingCrosspost = false
    @State private var showingRemindMe = false
    @State private var showingReport = false
    @State private var showingShareAsImage = false
    @State private var showingTranslator = false
    @State private var showingAward = false
    @State private var commentSort: String
    @State private var showingCommentSortSheet = false
    @State private var showingReplyComposer = false
    @State private var isMuted = false
    /// Gates `CommentRow`'s Approve/Remove/Mark Spam actions. See
    /// `CommentTreeScreen.isModerator`'s doc comment.
    @State private var isModerator = false
    /// What this screen's own moderator actions have changed on the post.
    @State var modDistinguished: Bool?
    @State var modStickied: Bool?
    @State var modLocked: Bool?
    @State var modMessage: String?

    /// Reborn "Apollo AI". Gated on `ApolloAISettings.summariesEnabled` so the menu
    /// action only appears once the user has opted in from `ApolloAISettingsScreen`.
    @Setting(ApolloAISettingsStore.storage) private var aiSettings
    /// Drives the two inline summary cards. The menu action + sheet
    /// below is a manual, on-demand path; these cards generate
    /// automatically once the screen opens.
    @StateObject private var aiSummary: AISummaryController
    @State private var showingAISummary = false
    @State private var isSummarizing = false
    @State private var aiSummaryText: String?
    @State private var aiSummaryError: String?
    /// Reborn "Floating Post Tabs". Optional so previews/tests work without one;
    /// `MainTabView` installs the app-wide instance via
    /// `.environment(\.floatingPostTabsManager:)`.
    @Environment(\.floatingPostTabsManager) private var floatingPostTabsManager
    /// Height reserved by the floating Liquid Glass tab bar, so the
    /// jump button can sit clear of it.
    @Environment(\.colorScheme) private var colorScheme
    @Setting(FloatingPostTabsSettingsStore.storage) private var floatingTabsSettings
    // `.navigationDestination(item:)` dispatches by value type, not
    // binding identity, so two separate `String?` destinations would
    // collide; `JumpDestination` combines both into one enum.
    @State private var jumpDestination: JumpDestination?
    /// Vote/save state for the toolbar "•••" menu.
    @ObservedObject private var voteStore = VoteStateStore.shared
    private var menuVoteState: Bool? { voteStore.vote(for: post.name, serverValue: post.likes) }
    private var menuIsSaved: Bool { voteStore.isSaved(post.name, serverValue: post.saved) }
    @State private var showingSelectText = false
    @State private var commentShareAsImage: CommentShareTarget?
    @StateObject private var commentStore = CommentTreeStore()

    public var startScrolledToComments: Bool = false
    @State private var hasAutoScrolledToComments = false

    /// Opens the reply composer as soon as the screen appears.
    ///
    /// The destination of the real Reply swipe action: the gesture's
    /// icon means "reply", not "go look at the replies", so landing on
    /// the comments with nothing focused would be a worse outcome than
    /// the gesture promises.
    public var startComposingReply: Bool = false
    @State private var hasAutoOpenedComposer = false

    public init(post: RedditPost,
                repository: RedditRepository,
                startScrolledToComments: Bool = false,
                startComposingReply: Bool = false) {
        self.post = post
        self.repository = repository
        self.startScrolledToComments = startScrolledToComments
        self.startComposingReply = startComposingReply
        // Remembered sort (per-post or per-subreddit) beats suggested
        // sort, which beats the Default Sort setting.
        let aiSettings = ApolloAISettingsStore.load()
        _aiSummary = StateObject(wrappedValue:
            AISummaryController(post: post, settings: aiSettings))
        let settings = GeneralSettingsStore.load()
        _commentSort = State(initialValue:
            CommentSortMemoryStore.rememberedSort(subreddit: post.subreddit, postID: post.id)
                ?? (settings.ignoreSuggestedSort ? nil : post.suggestedSort)
                ?? settings.defaultCommentSort
        )
    }

    @State private var showingFindInComments = false
    @State private var liveActivityRunning = false
    /// Why a Live Activity could not start, shown as an alert. Several
    /// genuinely different reasons exist (off in Settings, unsupported
    /// device, request failure), so the row does not fail silently.
    @State private var liveActivityMessage: String?
    @State private var findQuery = ""
    @State private var findMatches: [CommentSearchMatch] = []
    @State private var findCurrentIndex = 0
    /// This thread's translate/original choice (Reborn's per-thread
    /// globe); the app-wide setting is left alone.
    @State private var threadTranslated = TranslationSettings.threadStartsTranslated(TranslationSettingsStore.load())
    @Setting(TranslationSettings.self) private var translationSettings

    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedPost) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        threadScreen.environment(\.threadTranslation, threadTranslated)
    }

    private var threadScreen: some View {
        ScrollViewReader { scrollProxy in
            // Find in Comments (Reborn #1036) rests at the top under the title, not docked
            // above the keyboard.
            ZStack(alignment: .top) {
            List {
                // The inline field is the first row, hidden once search
                // is active since the pinned `FindInCommentsBar` takes over.
                if !showingFindInComments {
                    Section {
                        FindInCommentsFieldRow { showingFindInComments = true }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    header(scrollProxy: scrollProxy)
                        // A `.plain` List draws a separator above its first row as well as below it, so
                        // the post header would get a rule under the nav bar that Apollo does not have.
                        .listRowSeparator(.hidden, edges: .top)
                        // The header's bottom separator is the post/comments divider, drawn explicitly.
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden, edges: .bottom)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.apolloSeparator(colorScheme: colorScheme))
                                .frame(height: 1.0 / 3.0)
                        }
                }
                // No "Comments" section header or "Add a comment..."
                // row; the comment list follows the post header directly.
                commentList
            }
            // Fetched from the top-level `List`/`ScrollViewReader`, not
            // inside the lazily-rendered Comments `Section`: `List` only
            // instantiates a section once it scrolls near-visible, so a
            // tall header would leave its `.task` never running.
            .task(id: commentSort) { await commentStore.fetch(subreddit: post.subreddit, postID: post.id, sort: commentSort, repository: repository) }
            .task { isModerator = (try? await repository.fetchSubredditInfo(name: post.subreddit).userIsModerator) == true }
            // Restores the row's verb if an activity from a previous visit is still running.
            .task { liveActivityRunning = FollowThreadActivityStore.isActive(postID: post.id) }
            .alert(modMessage ?? "", isPresented: $modMessage.isPresent()) {
                Button("OK", role: .cancel) {}
            }
            .alert("Live Activity",
                   isPresented: $liveActivityMessage.isPresent()) {
                Button("OK", role: .cancel) { liveActivityMessage = nil }
            } message: {
                Text(liveActivityMessage ?? "")
            }
            // Deleted Comments archive recovery; see `CommentTreeStore
            // .fetchArchivedCommentsIfNeeded`. This screen embeds its own
            // `commentStore` rather than sharing one, so it needs its own trigger.
            .task { await commentStore.fetchArchivedCommentsIfNeeded(postID: post.id) }
            // Generates the post summary card on open and the discussion
            // card once comments are in, as two separate requests.
            .onAppear {
                // Re-read on every appearance: display-time gating must
                // hide a generated card whose sub-toggle was just turned off.
                aiSummary.settingsChanged(to: aiSettings)
                aiSummary.onAppear()
            }
            .onChange(of: commentStore.roots) { _, newRoots in
                aiSummary.commentsDidLoad(candidates: Self.summaryCandidates(
                    roots: newRoots, linkAuthor: post.author))
                guard startScrolledToComments, !hasAutoScrolledToComments, let firstRootID = newRoots.first?.id else { return }
                hasAutoScrolledToComments = true
                withAnimation { scrollProxy.scrollTo(commentStore.rowID(firstRootID), anchor: .top) }
            }
            .onDisappear {
                commentStore.stopLivePolling()
                aiSummary.pause()
            }
            // Same FOLLOW/READ approximation as `CommentTreeScreen`;
            // SwiftUI's `List` has no CADisplayLink-based edge detector.
            .onChange(of: commentStore.visibleTopLevelRootID) { _, newValue in
                guard commentSort == "live" else { return }
                // Split deliberately: as one expression the type-checker times out.
                let firstRootID: String? = commentStore.roots.first?.id
                commentStore.isAtLiveEdge = (newValue == nil) || (newValue == firstRootID)
            }
            // Pinned under the nav bar so it stays put while chevrons scroll the thread.
            .safeAreaInset(edge: .top, spacing: 0) {
                if showingFindInComments {
                    FindInCommentsBar(
                        query: $findQuery,
                        matchCount: findMatches.count,
                        currentIndex: findCurrentIndex,
                        onClose: endFindInComments
                    )
                }
            }
            .scrollDismissesKeyboard(showingFindInComments ? .immediately : .automatic)
            .safeAreaInset(edge: .top) {
                if commentSort == "live", commentStore.liveNewCount > 0 {
                    Button {
                        Task {
                            await commentStore.jumpToLiveEdge(subreddit: post.subreddit, postID: post.id, repository: repository)
                            if let firstRootID = commentStore.roots.first?.id {
                                withAnimation { scrollProxy.scrollTo(commentStore.rowID(firstRootID), anchor: .top) }
                            }
                        }
                    } label: {
                        Label("\(commentStore.liveNewCount) new comment\(commentStore.liveNewCount == 1 ? "" : "s")", systemImage: "chevron.up")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.apolloAccent))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("postDetail.liveNewCommentsPill")
                }
            }
        .onAppear { isMuted = MutedThreadsStore.isMuted(post.name) }
            .apolloTracksForwardNavigation($jumpDestination)
            .apolloOpensRedditTargetsHere()
            .apolloForwardSwipe()
            .apolloPopsOnTabReselection(item: $jumpDestination)
            .sheet(isPresented: $showingSelectText) {
            SelectTextSheet(title: post.title, body: post.selftext ?? "") {
                showingSelectText = false
            }
        }
        .navigationDestination(item: $jumpDestination) { destination in
                switch destination {
                case .user(let username):
                    UserProfileScreen(username: username, repository: repository)
                case .subreddit(let name):
                    FeedScreen(subreddit: name, repository: repository)
                }
            }
            .listStyle(.plain)
            // Comment rows size to their content: Apollo's "N more
            // replies" row is 39pt and a collapsed comment 48pt, both
            // under the List's default 44pt floor.
            .environment(\.defaultMinListRowHeight, 1)
            // Stock dark surface + Pure Black tiers.
            .scrollContentBackground(.hidden)
            .apolloStockSurface()
            // `force: true`: `CommentTreeStore.fetch` no-ops when the
            // same (postID, sort) is already loaded, so a refresh must say it means it.
            .refreshable {
                await commentStore.fetch(subreddit: post.subreddit,
                                         postID: post.id,
                                         sort: commentSort,
                                         repository: repository,
                                         force: true)
            }
            // Room under the last comment, so the floating tab bar
            // doesn't cover it at the end of the thread, nor the jump
            // button when it sits at the bottom: the button's 44pt and
            // its 16pt padding, plus a 12pt gap.
            .modifier(ApolloTabBarClearance(bottom: generalSettings.showJumpButton
                                            && generalSettings.jumpButtonPosition.sitsAtBottom ? 72 : 24))
            .restoresPositionOnSecondScrollToTop()
            .apolloScrollReturnButton()
            // NOT `.apolloHidesHeaderOnScroll()`: that's gated on the
            // tab bar's own setting and pairs with hiding it; this
            // screen is pushed and has no tab bar of its own.
            .navigationTitle(post.numComments.apolloCounted("Comment", "Comments"))
            .apolloCentersTitle(post.numComments.apolloCounted("Comment", "Comments"), key: "post.\(post.id)")
            .navigationBarTitleDisplayModeIfAvailable()
            // "Jump Button Position" (Settings > General > Comments).
            .overlay(alignment: generalSettings.jumpButtonPosition.alignment) {
                // Find in Comments rests at the top (#1036), clear of this button.
                if generalSettings.showJumpButton, !showingFindInComments {
                // Mirrors ShowCommentJumpButton / CommentJumpButtonPosition
                // (default: on, bottom-right): scrolls to the next top-level comment.
                VStack(spacing: 12) {
                    if !commentStore.roots.isEmpty {
                        Button {
                            Haptics.selection()
                            // Jumps to the comment after the one being read.
                            guard let targetID = commentStore.nextRootIDForJump() else { return }
                            withAnimation { scrollProxy.scrollTo(commentStore.rowID(targetID), anchor: .top) }
                        } label: {
                            // A solid blue circle with a white
                            // chevron-down, sized to match the
                            // collapsed tab pill (44x44).
                            Image(systemName: "chevron.down")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.apolloAccent))
                                .shadow(radius: 2)
                        }
                        .accessibilityLabel("Next Comment")
                        .accessibilityIdentifier("postDetail.jumpToNextComment")
                    }
                }
                .padding()
                }
            }
            }
            // Parent Comment swipe.
            .onChange(of: commentStore.scrollRequest) { _, target in
                guard let target else { return }
                withAnimation { scrollProxy.scrollTo(target, anchor: .top) }
                commentStore.scrollRequest = nil
            }
            .onChange(of: findQuery) { _, newValue in
                recomputeFindMatches(query: newValue)
                if let first = findMatches.first {
                    scrollToMatch(first, scrollProxy: scrollProxy)
                }
            }
        .toolbar {
            // Icon reflects the active comment sort. Reborn collapses trailing actions into
            // one "..." pill (#1035, "Tidier Glass Navigation"); while search is live the
            // ^ v navigator stands in for it.
            ToolbarItem(placement: .primaryAction) {
                if showingFindInComments {
                    FindInCommentsNavigator(
                        enabled: !findMatches.isEmpty,
                        onPrevious: { moveMatch(by: -1, scrollProxy: scrollProxy) },
                        onNext: { moveMatch(by: 1, scrollProxy: scrollProxy) }
                    )
                } else {
                NavigationActionsPill(actions: navigationActions) {
                    postOverflowMenu
                }
                .apolloGlassBarTint()
                }
            }
        }
        // Same action-sheet chrome as the feed's sort sheet.
        .apolloActionSheet(isPresented: $showingCommentSortSheet, title: "Sort by…", rows: CommentTreeScreen.sorts.map { option in
            ApolloActionSheetRow(
                option.label,
                icon: Self.iconName(forCommentSort: option.value),
                trailing: option.value == commentSort ? .checkmark : .none,
                accessibilityIdentifier: "postDetail.commentSortSheet.\(option.value)"
            ) {
                commentSort = option.value
                CrashRecorder.record(.changedCommentSort)
                CommentSortMemoryStore.recordSortChange(subreddit: post.subreddit, postID: post.id, sort: option.value)
            }
        })
        // Opens the composer for the Reply swipe action, guarded so
        // dismissing it doesn't immediately re-present it.
        .onAppear {
            guard startComposingReply, !hasAutoOpenedComposer else { return }
            hasAutoOpenedComposer = true
            showingReplyComposer = true
        }
        .sheet(isPresented: $showingReplyComposer) {
            // Same composer the comment-tree reply flow uses.
            CommentComposerScreen(
                parentFullname: post.name,
                repository: repository,
                subreddit: post.subreddit,
                onSubmitted: {
                    Task { await commentStore.fetch(subreddit: post.subreddit, postID: post.id, sort: commentSort, repository: repository, force: true) }
                },
                onPosted: { posted in
                    commentStore.insertPosted(posted, parentFullname: post.name)
                }
            )
        }
        .sheet(isPresented: $showingCrosspost) {
            NavigationStack {
                CrosspostScreen(post: post, repository: repository) {
                    showingCrosspost = false
                }
            }
        }
        .sheet(isPresented: $showingRemindMe) {
            NavigationStack {
                RemindMeScreen(post: post) {
                    showingRemindMe = false
                }
            }
        }
        .sheet(isPresented: $showingShareAsImage) {
            ShareAsImageScreen(post: post, repository: repository)
        }
        .sheet(item: $commentShareAsImage) { target in
            ShareAsImageScreen(post: post, comment: target.comment,
                               availableParents: target.parents, repository: repository)
        }
        .apolloTranslator(isPresented: $showingTranslator,
                          text: [post.title, post.selftext ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        .sheet(isPresented: $showingAward) {
            AwardGiftingScreen(fullname: post.name, repository: repository) {
                showingAward = false
            }
        }
        .sheet(isPresented: $showingReport) {
            ReportSheet(fullname: post.name, repository: repository) {
                showingReport = false
            }
        }
        .sheet(isPresented: $showingAISummary) { aiSummarySheet }
        }
        // Closing this screen is the back-pop a floating PiP card answers.
        .floatingPiPScreenScope()
        // Reborn "Siri & Spotlight" (#1299): this screen is about one post.
        .siriPostActivity(fullName: post.name, title: post.title)
    }

    /// The single post header row, extracted from `body`: inlining it
    /// pushed the Swift type-checker past its budget.
    @ViewBuilder
    private func header(scrollProxy: ScrollViewProxy) -> some View {
        PostDetailHeader(
            post: post,
            repository: repository,
            onSubredditTap: { jumpDestination = .subreddit(post.subreddit) },
            onAuthorTap: { jumpDestination = .user(post.author) },
            onJumpToComments: {
                // "Jump to comments" reuses the same scroll target the
                // jump-to-next-comment button uses.
                if let firstRootID = commentStore.roots.first?.id {
                    withAnimation { scrollProxy.scrollTo(commentStore.rowID(firstRootID), anchor: .top) }
                }
            },
            onReply: { showingReplyComposer = true },
            aiSummary: aiSummary
        )
        // Reborn "Siri & Spotlight" (#1299): the header row carries the post entity.
        .siriPostContext(post.name)
        // Links opened from this post get the browser's comments button.
        .onAppear {
            InAppBrowserContext.set(postID: post.name) {
                if let firstRootID = commentStore.roots.first?.id {
                    withAnimation { scrollProxy.scrollTo(commentStore.rowID(firstRootID), anchor: .top) }
                }
            }
        }
        .onDisappear { InAppBrowserContext.clear(postID: post.name) }
    }

    @ViewBuilder
    private var commentList: some View {
        CommentTreeContent(
            store: commentStore,
            subreddit: post.subreddit, postID: post.id, repository: repository,
            post: post, sort: commentSort,
            isModerator: isModerator,
            onAuthorTapped: { jumpDestination = .user($0) },
            onShareAsImage: { comment, parents in
                commentShareAsImage = CommentShareTarget(comment: comment, parents: parents)
            }
        )
    }

    /// Flattens the loaded tree into ranking candidates. Uses
    /// `flattenedAll()`, not `visibleFlattened()`: a collapsed comment
    /// is still part of the discussion being summarized.
    static func summaryCandidates(roots: [CommentTreeNode], linkAuthor: String) -> [AICommentSelector.Candidate] {
        roots.flatMap { $0.flattenedAll() }.map { node in
            AICommentSelector.Candidate(
                id: node.comment.id,
                author: node.comment.author,
                body: node.comment.body,
                score: node.comment.score,
                controversiality: node.comment.controversiality ?? 0,
                depth: node.comment.depth ?? node.depth,
                linkAuthor: linkAuthor
            )
        }
    }

    /// Extracted from `body` for the same reason as `commentList`:
    /// inline, it tipped this view past the type-checker's budget.
    @ViewBuilder
    private var aiSummarySheet: some View {
        AISummarySheet(
            isSummarizing: isSummarizing,
            summaryText: aiSummaryText,
            errorMessage: aiSummaryError,
            onRetry: { Task { await summarizeWithAI() } }
        )
    }

    /// Builds a plain-text excerpt of the post's selftext plus top-level comments and
    /// sends it to `ApolloAIClient.summarize`, capped so a huge thread does not exceed
    /// a provider's context window.
    private func summarizeWithAI() async {
        isSummarizing = true
        aiSummaryText = nil
        aiSummaryError = nil
        defer { isSummarizing = false }
        var pieces: [String] = []
        pieces.append("Title: \(post.title)")
        // A live interactive (Devvit) post renders as its widget, not its body, so its
        // selftext is not summarized. See `DevvitPostDetector.aiShouldTreatAsBodyless`.
        let bodyless = DevvitPostDetector.aiShouldTreatAsBodyless(
            post: post,
            devvitInteractivePosts: generalSettings.devvitInteractivePosts
        )
        if !bodyless, let selftext = post.selftext, !selftext.isEmpty {
            pieces.append("Post body: \(selftext)")
        }
        let topComments = commentStore.roots.prefix(20).map { "u/\($0.comment.author): \($0.comment.body)" }
        if !topComments.isEmpty {
            pieces.append("Top comments:\n" + topComments.joined(separator: "\n"))
        }
        let combined = pieces.joined(separator: "\n\n")
        let bounded = String(combined.prefix(8000))
        do {
            aiSummaryText = try await ApolloAIClient.summarize(text: bounded, settings: aiSettings)
        } catch {
            aiSummaryError = (error as? LocalizedError)?.errorDescription ?? "Couldn't generate a summary: \(UserFacingError.text(for: error))"
        }
    }

    /// Recomputes matches over the currently-loaded comment tree. Only searches what
    /// is already fetched/expanded, no paging in more.
    private func recomputeFindMatches(query: String) {
        let flattened: [(id: String, author: String, body: String)] = commentStore.roots
            .flatMap { $0.visibleFlattened() }
            .map { ($0.id, $0.comment.author, $0.comment.body) }
        findMatches = CommentSearchEngine.findMatches(
            query: query,
            postTitle: post.title,
            postSelftext: post.selftext,
            postAuthor: post.author,
            subreddit: post.subreddit,
            flattenedComments: flattened
        )
        findCurrentIndex = 0
    }

    private func endFindInComments() {
        showingFindInComments = false
        findQuery = ""
        findMatches = []
        findCurrentIndex = 0
    }

    private func moveMatch(by delta: Int, scrollProxy: ScrollViewProxy) {
        guard !findMatches.isEmpty else { return }
        // Wraps around at either end.
        findCurrentIndex = (findCurrentIndex + delta + findMatches.count) % findMatches.count
        scrollToMatch(findMatches[findCurrentIndex], scrollProxy: scrollProxy)
    }

    private func scrollToMatch(_ match: CommentSearchMatch, scrollProxy: ScrollViewProxy) {
        guard let commentID = match.commentID else { return }
        withAnimation { scrollProxy.scrollTo(commentStore.rowID(commentID), anchor: .center) }
    }

    /// Sort and Find, plus the thread's translate globe once bulk
    /// translation is switched on.
    private var navigationActions: [NavigationActionsPill.Action] {
        var actions: [NavigationActionsPill.Action] = [
            .init(id: "commentSort", systemImage: commentSortIconName, label: "Sort Comments") {
                showingCommentSortSheet = true
            },
            .init(id: "findInComments", systemImage: "magnifyingglass", label: "Find in Comments") {
                showingFindInComments = true
            },
        ]
        if translationSettings.enableBulkTranslation {
            actions.append(.init(id: "translateThread", systemImage: "globe",
                                 label: threadTranslated ? "Show Original" : "Translate Thread") {
                threadTranslated.toggle()
            })
        }
        return actions
    }

    private var commentSortIconName: String {
        Self.iconName(forCommentSort: commentSort)
    }

    static func iconName(forCommentSort sort: String) -> String {
        switch sort {
        case "confidence": return "trophy"
        case "top": return "arrow.up.and.line.horizontal.and.arrow.down"
        case "new": return "clock"
        // Matches the feed's real Controversial icon (scissors).
        case "controversial": return "scissors"
        case "old": return "hourglass"
        case "qa": return "questionmark.circle"
        case "live": return "dot.radiowaves.left.and.right"
        // Anything not enumerated falls through to the shared table
        // of `option-sort-*` names, so a new sort gets its real icon.
        default: return ApolloMenuIcon.symbol("option-sort-\(sort)", fallback: "arrow.up.arrow.down")
        }
    }
}

extension PostDetailScreen {
    /// The post "•••" menu. Extracted from the toolbar closure since
    /// inlining it exceeded the type-checker's budget.
    /// Entries in the app's order, arranged by the user's Action Menus
    /// layout for the comments view (Reborn #1131, context `post-detail`).
    @ViewBuilder
    private var postOverflowMenu: some View {
        ForEach(ActionMenuLayoutStore.arrange(postDetailMenuIDs, for: .postDetail), id: \.self) { id in
            postDetailMenuRow(id)
        }
    }

    private var postDetailMenuIDs: [String] {
        var ids = isModerator ? ["moderator"] : []
        ids += ["upvote", "downvote", "save", "reply", "author", "subreddit", "collapse-children",
                   "select-text", "share", "share-image", "crosspost", "find", "award", "copy-link", "remind-me"]
        if post.isSelf, let selftext = post.selftext, !selftext.isEmpty { ids += ["translate", "copy-text"] }
        if aiSettings.summariesEnabled { ids.append("summarize") }
        if floatingTabsSettings.enabled { ids.append("spec.FloatingTabs") }
        ids += ["mute-notifications", "report", "live-activity", "spec.DeletedComments"]
        return ids
    }

    /// The Moderator row: the Moderator (Post) menu, arranged by its layout.
    private var moderatorPostMenu: some View {
        Menu {
            ForEach(ActionMenuLayoutStore.arrange(["mod-approve", "mod-remove", "mod-spam", "mod-distinguish",
                                                   "mod-sticky", "mod-lock"], for: .moderatorPost), id: \.self) { id in
                moderatorPostRow(id)
            }
        } label: { Label("Moderator", systemImage: "shield") }
        .accessibilityIdentifier("postDetail.menu.moderator")
    }

    @ViewBuilder
    private func moderatorPostRow(_ id: String) -> some View {
        let distinguished = modDistinguished ?? (post.distinguished == "moderator")
        let stickied = modStickied ?? post.stickied
        let locked = modLocked ?? (post.locked ?? false)
        switch id {
        case "mod-approve":
            Button { moderate("Approved") { _ = try await repository.approve(fullname: post.name) } } label: {
                Label("Approve", systemImage: "checkmark.shield")
            }
        case "mod-remove":
            Button(role: .destructive) {
                moderate("Removed") { _ = try await repository.remove(fullname: post.name, isSpam: false) }
            } label: { Label("Remove", systemImage: "xmark.shield") }
        case "mod-spam":
            Button(role: .destructive) {
                moderate("Marked as Spam") { _ = try await repository.remove(fullname: post.name, isSpam: true) }
            } label: { Label("Mark as Spam", systemImage: "exclamationmark.shield") }
        case "mod-distinguish":
            Button {
                moderate(distinguished ? "Undistinguished" : "Distinguished") {
                    _ = try await repository.distinguish(fullname: post.name, asMod: !distinguished)
                    modDistinguished = !distinguished
                }
            } label: {
                Label(distinguished ? "Undistinguish" : "Distinguish", systemImage: "shield.lefthalf.filled")
            }
        case "mod-sticky":
            Button {
                moderate(stickied ? "Unstickied" : "Stickied") {
                    _ = try await repository.setSticky(fullname: post.name, sticky: !stickied)
                    modStickied = !stickied
                }
            } label: { Label(stickied ? "Unsticky" : "Sticky", systemImage: "pin") }
        case "mod-lock":
            Button {
                moderate(locked ? "Comments Unlocked" : "Comments Locked") {
                    _ = try await repository.setLocked(fullname: post.name, locked: !locked)
                    modLocked = !locked
                }
            } label: {
                Label(locked ? "Unlock Comments" : "Lock Comments", systemImage: locked ? "lock.open" : "lock")
            }
        default:
            EmptyView()
        }
    }

    private func moderate(_ done: String, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                modMessage = done
            } catch {
                modMessage = "Couldn't complete that: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func postDetailMenuRow(_ id: String) -> some View {
        switch id {
        case "moderator":
            moderatorPostMenu
        case "upvote":
            Button {
                Task { await voteFromMenu(direction: menuVoteState == true ? 0 : 1) }
            } label: { Label("Upvote", systemImage: "arrow.up") }
            .accessibilityIdentifier("postDetail.menu.upvote")
        case "downvote":
            Button {
                Task { await voteFromMenu(direction: menuVoteState == false ? 0 : -1) }
            } label: { Label("Downvote", systemImage: "arrow.down") }
            .accessibilityIdentifier("postDetail.menu.downvote")
        case "save":
            Button {
                Task { await toggleSavedFromMenu() }
            } label: {
                Label(menuIsSaved ? "Unsave" : "Save", systemImage: menuIsSaved ? "bookmark.fill" : "bookmark")
            }
            .accessibilityIdentifier("postDetail.menu.save")
        case "reply":
            Button { showingReplyComposer = true } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            .accessibilityIdentifier("postDetail.menu.reply")
        case "author":
            // Labelled with the name itself, opening a submenu.
            Menu {
                Button { jumpDestination = .user(post.author) } label: {
                    Label("View Profile", systemImage: "person.crop.circle")
                }
                Button { PasteboardHelper.copy(post.author) } label: {
                    Label("Copy Username", systemImage: "doc.on.doc")
                }
            } label: { Label(post.author, systemImage: "person.circle") }
            .accessibilityIdentifier("postDetail.menu.author")
        case "subreddit":
            Menu {
                Button { jumpDestination = .subreddit(post.subreddit) } label: {
                    Label("View Subreddit", systemImage: "list.bullet.below.rectangle")
                }
            } label: { Label(post.subreddit, systemImage: "house") }
            .accessibilityIdentifier("postDetail.menu.subreddit")
        case "collapse-children":
            let anyCollapsed = commentStore.roots.contains { $0.hasCollapsedDescendant }
            Button {
                commentStore.setAllChildrenCollapsed(!anyCollapsed)
            } label: {
                Label(anyCollapsed ? "Expand Child Comments" : "Collapse Child Comments",
                      systemImage: anyCollapsed ? "chevron.down.2" : "chevron.up.2")
            }
            .accessibilityIdentifier("postDetail.menu.collapseChildComments")
        case "select-text":
            Button { showingSelectText = true } label: {
                Label("Select Text", systemImage: "selection.pin.in.out")
            }
            .accessibilityIdentifier("postDetail.menu.selectText")
        case "share":
            ShareLink(item: post.shareText()) { Label("Share", systemImage: "square.and.arrow.up") }
                .accessibilityIdentifier("postDetail.menu.share")
        case "share-image":
            Button { showingShareAsImage = true } label: {
                Label("Share as Image…", systemImage: "photo.badge.plus")
            }
        case "crosspost":
            Button { showingCrosspost = true } label: {
                Label("Crosspost", systemImage: "arrowshape.turn.up.right")
            }
        case "find":
            Button { showingFindInComments = true } label: {
                Label("Find in Comments", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("postDetail.menu.findInComments")
        case "award":
            Button { showingAward = true } label: { Label("Give Award", systemImage: "medal") }
                .accessibilityIdentifier("postDetail.menu.giveAward")
        case "copy-link":
            Button { PasteboardHelper.copy(url: post.shareURL()) } label: {
                Label("Copy Link", systemImage: "link")
            }
        case "remind-me":
            Button { showingRemindMe = true } label: { Label("Remind Me", systemImage: "alarm") }
        case "translate":
            Button { showingTranslator = true } label: {
                Label("Translate", systemImage: "character.bubble")
            }
        case "copy-text":
            Button { PasteboardHelper.copy(post.selftext ?? "") } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        case "summarize":
            Button {
                showingAISummary = true
                Task { await summarizeWithAI() }
            } label: { Label("Summarize with AI", systemImage: "sparkles") }
            .accessibilityIdentifier("postDetail.summarizeWithAI")
        case "spec.FloatingTabs":
            Button { floatingPostTabsManager?.add(post: post) } label: {
                Label(floatingPostTabsManager?.isKept(post) == true ? "Already Kept in Floating Tab" : "Keep in Floating Tab",
                      systemImage: "circle.grid.2x2")
            }
            .disabled(floatingPostTabsManager?.isKept(post) == true)
            .accessibilityIdentifier("postDetail.keepInFloatingTab")
        case "mute-notifications":
            Button {
                isMuted.toggle()
                MutedThreadsStore.setMuted(post.name, muted: isMuted)
            } label: {
                Label(isMuted ? "Unmute Notifications" : "Mute Notifications",
                      systemImage: isMuted ? "bell.slash.fill" : "bell.slash")
            }
        case "report":
            Button(role: .destructive) { showingReport = true } label: { Label("Report", systemImage: "flag") }
        case "live-activity":
            // The local activity runs; its push half cannot (see
            // `FollowThreadActivity`).
            Button {
                if liveActivityRunning {
                    Task { await LiveActivityHelper.end(postID: post.id) }
                    liveActivityRunning = false
                } else {
                    let result = LiveActivityHelper.start(
                        postID: post.id, title: post.title, subreddit: post.subreddit,
                        commentCount: post.numComments, score: post.score)
                    liveActivityRunning = result == .started
                    liveActivityMessage = result.message
                }
            } label: {
                Label(liveActivityRunning ? "End Live Activity" : "Start Live Activity",
                      systemImage: liveActivityRunning ? "stop.circle" : "clock.badge")
            }
            .accessibilityIdentifier("postDetail.menu.liveActivity")
        case "spec.DeletedComments":
            // See `CommentTreeStore.toggleDeletedCommentsShortcut`.
            Button {
                Task { await commentStore.toggleDeletedCommentsShortcut(postID: post.id) }
            } label: {
                Label(commentStore.deletedCommentsRecoveryActive ? "Hide Deleted Comments" : "Show Deleted Comments",
                      systemImage: commentStore.deletedCommentsRecoveryActive ? "eye.slash" : "eye")
            }
            .accessibilityIdentifier("postDetail.deletedCommentsShortcut")
        default:
            EmptyView()
        }
    }

    private func voteFromMenu(direction: Int) async {
        Haptics.light()
        await ContentActions.vote(post, direction: direction, repository: repository)
    }

    private func toggleSavedFromMenu() async {
        await ContentActions.toggleSave(post, repository: repository)
    }

}

/// Presentation surface for "Summarize with AI": shows the generated
/// summary or an error from `ApolloAIClient` as a sheet.
struct AISummarySheet: View {
    let isSummarizing: Bool
    let summaryText: String?
    let errorMessage: String?
    let onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isSummarizing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Summarizing…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        Button("Try Again", action: onRetry)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("aiSummary.error")
                } else if let summaryText {
                    ScrollView {
                        Text(summaryText)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("aiSummary.text")
                } else {
                    Text("No summary yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("AI Summary")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension Image {
}

/// A comment to share as an image, with the ancestors the card can include.
struct CommentShareTarget: Identifiable {
    let comment: RedditComment
    let parents: [RedditComment]
    var id: String { comment.id }
}

private extension JumpButtonPosition {
    var alignment: Alignment {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .middleTrailing: return .trailing
        case .topTrailing: return .topTrailing
        case .center: return .bottom
        case .bottomLeading: return .bottomLeading
        case .middleLeading: return .leading
        case .topLeading: return .topLeading
        }
    }

    var sitsAtBottom: Bool { alignment.vertical == .bottom }
}
