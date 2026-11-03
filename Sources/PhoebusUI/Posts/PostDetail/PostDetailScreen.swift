import SwiftUI
import PhoebusCore

/// Post detail screen: the full post (title, selftext or media, vote controls)
/// above the comment tree.
public struct PostDetailScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    /// The post as the opener had it; `post` has this device's own changes
    /// laid over it (an edited body, comments it added).
    private let listedPost: RedditPost
    @ObservedObject private var changes = OwnPostChanges.shared
    private var post: RedditPost { changes.apply(to: listedPost) }
    let repository: RedditRepository
    @State private var returnOwner = ScrollReturnOwner()
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showingCrosspost = false
    @State private var showingOtherDiscussions = false
    @Setting(OtherDiscussionsSettings.self) private var otherDiscussionsSettings
    @State private var showingRemindMe = false
    @State private var showingReport = false
    @State private var showingModNotes = false
    @State private var showingShareAsImage = false
    /// Whether the signed-in user wrote this post: gates Insights, and the
    /// ••• menu's Edit Post and Delete Post.
    @State private var isOwnPost = false
    @State private var showingInsights = false
    @State private var showingTranslator = false
    @State private var showingAward = false
    @State private var commentSort: String
    @State private var showingCommentSortSheet = false
    @State private var showingReplyComposer = false
    @State private var isMuted = false
    /// Your own post: the header shows the inline editor and the deleted state.
    @State private var isEditingPost = false
    @State private var isPostDeleted = false
    @State private var confirmingPostDelete = false
    /// Gates `CommentRow`'s Approve/Remove/Mark Spam actions. See
    /// `CommentTreeScreen.isModerator`'s doc comment.
    @State private var isModerator = false
    /// What this screen's own moderator actions have changed on the post.
    @State var modDistinguished: Bool?
    @State var modStickied: Bool?
    @State var modLocked: Bool?
    @State var modMessage: String?
    /// Mark NSFW / Mark Spoiler changes since the post was loaded.
    @State private var markOverrides: [PostMark: Bool] = [:]
    @State private var signedInUsername: String?
    /// When a hold on the jump button fired, so its release is not also a tap.
    @State private var jumpLongPressFired: Date?
    /// Where the last New Comments jump landed, as the jump button's VoiceOver value.
    @State private var jumpPosition = ""

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
    /// "Remember Thread Position": tried once, when the comments first load.
    @State private var hasRestoredThreadPosition = false
    @State private var showingBackToTop = false
    @Environment(\.scenePhase) private var scenePhase

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
        self.listedPost = post
        self.repository = repository
        _isPostDeleted = State(initialValue: OwnPostChanges.shared.isDeleted(post.name))
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
                            .id(Self.findFieldRowID)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    header(scrollProxy: scrollProxy)
                        .id(Self.headerRowID)
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
            .task { signedInUsername = await CurrentUsernameCache.username(repository: repository) }
            .onReceive(NotificationCenter.default.publisher(for: .apolloPostMarkChanged)) { note in
                guard let change = PostMarkChange(note), change.fullname == post.name else { return }
                markOverrides[change.mark] = change.value
            }
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
                if restoreThreadPosition(scrollProxy: scrollProxy) { hasAutoScrolledToComments = true }
                guard startScrolledToComments, !hasAutoScrolledToComments, let firstRootID = newRoots.first?.id else { return }
                hasAutoScrolledToComments = true
                withAnimation { scrollProxy.scrollTo(commentStore.rowID(firstRootID), anchor: .top) }
            }
            .onAppear { commentStore.startThreadPositionAutosave() }
            .onDisappear {
                commentStore.stopLivePolling()
                commentStore.stopThreadPositionAutosave()
                aiSummary.pause()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { commentStore.saveThreadPosition() }
            }
            .threadPositionBackToTop(isPresented: $showingBackToTop,
                                     accessibilityIdentifier: "postDetail.threadPosition.backToTop") {
                withAnimation {
                    scrollProxy.scrollTo(showingFindInComments ? Self.headerRowID : Self.findFieldRowID, anchor: .top)
                }
            }
            // Same FOLLOW/READ approximation as `CommentTreeScreen`;
            // SwiftUI's `List` has no CADisplayLink-based edge detector.
            .onChange(of: commentSort, initial: true) { _, sort in commentStore.tracksLiveEdge = sort == "live" }
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
            .task {
                let username = await CurrentUsernameCache.username(repository: repository)
                isOwnPost = PostInsightsParser.isEligible(author: post.author, currentUsername: username)
            }
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
                    UserProfileScreen(username: username, repository: repository,
                                      community: post.subredditID.map { .init(name: post.subreddit, id: $0) })
                case .subreddit(let name):
                    FeedScreen(subreddit: name, repository: repository)
                }
            }
            .navigationDestination(isPresented: $showingOtherDiscussions) {
                OtherDiscussionsScreen(post: post, repository: repository)
            }
            .apolloTracksForwardNavigation($showingOtherDiscussions)
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
            .restoresPositionOnSecondScrollToTop(owner: returnOwner, shortensLongScrolls: true)
            .apolloScrollReturnButton(owner: returnOwner)
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
                // (default: on, bottom-right): scrolls to the next top-level comment,
                // or in Reborn's New Comments mode (CommentNavigationMode) to the next
                // new one, with a hold for the previous.
                VStack(spacing: 12) {
                    if !commentStore.roots.isEmpty {
                        let mode = generalSettings.commentNavigationMode
                        Button {
                            if let fired = jumpLongPressFired {
                                jumpLongPressFired = nil
                                if Date().timeIntervalSince(fired) < 5 { return }
                            }
                            Haptics.selection()
                            if mode == .newComments {
                                jumpToNewComment(direction: 1, scrollProxy: scrollProxy)
                                return
                            }
                            // Jumps to the comment after the one being read.
                            guard let targetID = commentStore.nextRootIDForJump() else { return }
                            withAnimation { scrollProxy.scrollTo(commentStore.rowID(targetID), anchor: .top) }
                        } label: {
                            CommentJumpButtonLabel(mode: mode)
                        }
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            guard mode == .newComments else { return }
                            jumpLongPressFired = Date()
                            Haptics.selection()
                            jumpToNewComment(direction: -1, scrollProxy: scrollProxy)
                        })
                        .accessibilityLabel(mode.jumpButtonAccessibilityLabel)
                        .accessibilityHint(mode.jumpButtonAccessibilityHint)
                        .accessibilityValue(mode == .newComments ? jumpPosition : "")
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
                    changes.recordCommentChange(fullname: post.name, listed: listedPost.numComments, delta: 1)
                    Task { await commentStore.fetch(subreddit: post.subreddit, postID: post.id, sort: commentSort, repository: repository, force: true) }
                },
                onPosted: { posted in
                    changes.recordCommentChange(fullname: post.name, listed: listedPost.numComments, delta: 1)
                    commentStore.insertPosted(commentStore.decoratingPosted(posted, post: post), parentFullname: post.name)
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
        .sheet(isPresented: $showingInsights) {
            PostInsightsSheet(post: post, repository: repository)
        }
        .sheet(item: $commentShareAsImage) { target in
            ShareAsImageScreen(post: post, comment: target.comment,
                               availableParents: target.parents, repository: repository)
        }
        .apolloTranslator(isPresented: $showingTranslator,
                          text: [post.title, post.selftext ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        .sheet(isPresented: $showingAward) {
            AwardPickerScreen(thingID: post.name, repository: repository) {
                showingAward = false
            }
        }
        .sheet(isPresented: $showingModNotes) {
            ModNotesSheet(subreddit: post.subreddit, user: post.author, repository: repository, attachTo: post.name)
        }
        .sheet(isPresented: $showingReport) {
            ReportSheet(fullname: post.name, repository: repository) {
                showingReport = false
            }
        }
        .sheet(isPresented: $showingAISummary) { aiSummarySheet }
        .alert("Delete Post?", isPresented: $confirmingPostDelete) {
            Button("Delete", role: .destructive) { Task { await deletePost() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
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
        VStack(spacing: 0) {
            postHeader(scrollProxy: scrollProxy)
            if OtherDiscussions.showsCountRow(count: commentStore.postDuplicateCount, post: post,
                                              settings: otherDiscussionsSettings),
               let count = commentStore.postDuplicateCount {
                OtherDiscussionsRow(count: count) { showingOtherDiscussions = true }
            }
        }
    }

    @ViewBuilder
    private func postHeader(scrollProxy: ScrollViewProxy) -> some View {
        PostDetailHeader(
            post: markedPost,
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
            aiSummary: aiSummary,
            overflowMenu: AnyView(postOverflowMenu),
            isEditing: $isEditingPost,
            isDeleted: $isPostDeleted
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
        .threadRowMarker(CommentTreeStore.headerRowID, tracker: commentStore.threadScroll,
                         enabled: commentStore.tracksRowMarkers)
    }

    private static let findFieldRowID = "postDetail.findFieldRow"
    private static let headerRowID = "postDetail.headerRow"

    /// "Remember Thread Position": lands on the saved comment the first
    /// time the comments load. Returns whether it scrolled.
    private func restoreThreadPosition(scrollProxy: ScrollViewProxy) -> Bool {
        guard !hasRestoredThreadPosition, !commentStore.roots.isEmpty else { return false }
        hasRestoredThreadPosition = true
        guard let target = commentStore.threadPositionRestoreTarget(focusedCommentID: nil) else { return false }
        commentStore.restoreThreadPosition(to: target) { scrollProxy.scrollTo($0, anchor: .top) }
        showingBackToTop = true
        return true
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

    /// The jump button's New Comments mode; see `CommentTreeStore.jumpToNewComment`.
    private func jumpToNewComment(direction: Int, scrollProxy: ScrollViewProxy) {
        Task {
            let outcome = await commentStore.jumpToNewComment(
                direction: direction, ownUsername: signedInUsername, repository: repository
            ) { rowID in
                withAnimation { scrollProxy.scrollTo(rowID, anchor: .top) }
            }
            switch outcome {
            case .landed(let ordinal, let total, let wrapped):
                // VoiceOver reads the button's value when it changes.
                jumpPosition = "\(wrapped ? (direction > 0 ? "Back to first · " : "Back to last · ") : "")New comment \(ordinal) of \(total)"
            case .noPreviousVisit:
                ApolloToast.showNotice("No previous visit recorded", detail: "Revisit this post later to jump to new comments.")
            case .nothingNew:
                ApolloToast.showNotice("No new comments found")
            case .moreRepliesToSearch:
                ApolloToast.showNotice("More replies to search", detail: "Tap the jump button again to continue.")
            case .busy:
                break
            }
        }
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
    /// The post "•••" menu, see `PostDetailActionMenuContent`. Extracted
    /// from the toolbar closure since inlining it exceeded the
    /// type-checker's budget.
    @ViewBuilder
    private var postOverflowMenu: some View {
        PostDetailActionMenuContent(facts: menuFacts, repository: repository) { performMenuAction($0) }
    }

    private var menuFacts: PostDetailMenuFacts {
        PostDetailMenuFacts(
            post: post, markedPost: markedPost, signedInUsername: signedInUsername, isModerator: isModerator,
            isOwnPost: isOwnPost, isPostDeleted: isPostDeleted, summariesEnabled: aiSettings.summariesEnabled,
            floatingTabsEnabled: floatingTabsSettings.enabled, isSaved: menuIsSaved, isMuted: isMuted,
            anyChildCollapsed: commentStore.roots.contains { $0.hasCollapsedDescendant },
            isKeptInFloatingTab: floatingPostTabsManager?.isKept(post) == true,
            liveActivityRunning: liveActivityRunning,
            deletedCommentsRecoveryActive: commentStore.deletedCommentsRecoveryActive,
            moderator: PostModeratorMenuState(
                distinguished: modDistinguished ?? (post.distinguished == "moderator"),
                stickied: modStickied ?? post.stickied,
                locked: modLocked ?? (post.locked ?? false)))
    }

    /// The post with this session's Mark NSFW / Mark Spoiler changes.
    private var markedPost: RedditPost {
        var marked = post
        for (mark, value) in markOverrides { mark.set(value, on: &marked) }
        return marked
    }

    private func performMenuAction(_ action: PostDetailMenuAction) {
        switch action {
        case .upvote:
            Task { await voteFromMenu(direction: menuVoteState == true ? 0 : 1) }
        case .downvote:
            Task { await voteFromMenu(direction: menuVoteState == false ? 0 : -1) }
        case .save:
            Task { await toggleSavedFromMenu() }
        case .reply:
            showingReplyComposer = true
        case .viewProfile:
            jumpDestination = .user(post.author)
        case .copyUsername:
            PasteboardHelper.copy(post.author)
        case .viewSubreddit:
            jumpDestination = .subreddit(post.subreddit)
        case .collapseChildren:
            let anyCollapsed = commentStore.roots.contains { $0.hasCollapsedDescendant }
            commentStore.setAllChildrenCollapsed(!anyCollapsed)
        case .selectText:
            showingSelectText = true
        case .shareImage:
            showingShareAsImage = true
        case .crosspost:
            showingCrosspost = true
        case .otherDiscussions:
            showingOtherDiscussions = true
        case .findInComments:
            showingFindInComments = true
        case .award:
            showingAward = true
        case .copyLink:
            PasteboardHelper.copy(url: post.shareURL())
        case .remindMe:
            showingRemindMe = true
        case .translate:
            showingTranslator = true
        case .copyText:
            PasteboardHelper.copy(post.selftext ?? "")
        case .edit:
            isEditingPost = true
        case .delete:
            confirmingPostDelete = true
        case .summarize:
            showingAISummary = true
            Task { await summarizeWithAI() }
        case .keepInFloatingTab:
            floatingPostTabsManager?.add(post: post)
        case .toggleMute:
            isMuted.toggle()
            MutedThreadsStore.setMuted(post.name, muted: isMuted)
        case .report:
            showingReport = true
        case .liveActivity:
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
        case .deletedComments:
            Task { await commentStore.toggleDeletedCommentsShortcut(postID: post.id) }
        case .insights:
            showingInsights = true
        case .moderator(let action):
            performModeratorAction(action)
        }
    }

    private func performModeratorAction(_ action: PostModeratorAction) {
        let distinguished = modDistinguished ?? (post.distinguished == "moderator")
        let stickied = modStickied ?? post.stickied
        let locked = modLocked ?? (post.locked ?? false)
        switch action {
        case .approve:
            moderate("Approved") { _ = try await repository.approve(fullname: post.name) }
        case .remove:
            moderate("Removed") { _ = try await repository.remove(fullname: post.name, isSpam: false) }
        case .spam:
            moderate("Marked as Spam") { _ = try await repository.remove(fullname: post.name, isSpam: true) }
        case .distinguish:
            moderate(distinguished ? "Undistinguished" : "Distinguished") {
                _ = try await repository.distinguish(fullname: post.name, asMod: !distinguished)
                modDistinguished = !distinguished
            }
        case .sticky:
            moderate(stickied ? "Unstickied" : "Stickied") {
                _ = try await repository.setSticky(fullname: post.name, sticky: !stickied)
                modStickied = !stickied
            }
        case .lock:
            moderate(locked ? "Comments Unlocked" : "Comments Locked") {
                _ = try await repository.setLocked(fullname: post.name, locked: !locked)
                modLocked = !locked
            }
        case .notes:
            showingModNotes = true
        }
    }

    private func deletePost() async {
        // Only on success, so a failed delete does not show the post as deleted.
        guard (try? await repository.delete(fullname: post.name)) != nil else { return }
        OwnPostChanges.shared.recordDeletion(fullname: post.name)
        isPostDeleted = true
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
