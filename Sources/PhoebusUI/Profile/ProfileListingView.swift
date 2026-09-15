import SwiftUI
import PhoebusCore

struct ProfileListingView: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let username: String
    let repository: RedditRepository
    let tab: UserProfileScreen.ProfileTab
    var isOwnProfile: Bool = false
    /// Rows drawn above the listing: the profile screen's own header and
    /// menu, with its Overview listing inline below them as Apollo's.
    var header: AnyView? = nil

    /// Posts and comments together, in Reddit's order.
    @State private var items: [ProfileItem] = []
    /// The next page's cursor; nil once the listing has ended.
    @State private var after: String?
    @State private var isLoadingMore = false
    @State private var moreFailed = false
    @State private var selectedComment: CommentLink?

    struct CommentLink: Hashable {
        let subreddit: String
        let postID: String
        let commentID: String
    }
    @State private var authorTarget: String?
    /// Which segment's data `posts`/`comments`/etc currently hold, so a
    /// reappear does not refetch what is already loaded.
    @State private var loadedTab: UserProfileScreen.ProfileTab?
    @State private var trophies: [RedditTrophy] = []
    @State private var multireddits: [RedditMultireddit] = []
    @State private var managingSubredditsMultireddit: RedditMultireddit?
    @State private var badgeUser: RedditUser?
    @State private var earnedBadges: [EarnedBadge] = []
    @State private var errorMessage: String?
    @State private var categories: [SavedCategory] = SavedCategoryStore.loadCategories()
    @State private var selectedCategory: String?
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    /// Bumped whenever a category assignment changes, to force the
    /// filtered list to recompute (assignments live in UserDefaults,
    /// not observable SwiftUI state on their own).
    @State private var assignmentVersion = 0
    /// Lets a tap on a post row's subreddit label (see `PostRow`'s `onSubredditTap`)
    /// navigate to that subreddit, as in Apollo.
    @State private var jumpTarget: String?
    @State private var selectedPost: RedditPost?
    /// Independent swipe-action configuration for "Profile Posts" and "Profile
    /// Comments" (`SwipeActionStore(for: .profilePosts)` / `.profileComments`),
    /// loaded once per screen instance like `FeedScreen.swipeSettings`.
    @Setting(SwipeActionStore.storage(for: .profilePosts)) private var postSwipeSettings
    @Setting(SwipeActionStore.storage(for: .profileComments)) private var commentSwipeSettings
    /// Profile Comments' default right-long-swipe action is Reply
    /// (`SwipeActionSettings.profileCommentsDefault`), opening the full-screen
    /// `CommentComposerScreen`.
    @State private var replyTarget: RedditComment?
    @State private var postReplyTarget: RedditPost?
    @State private var shareTarget: RedditPost?
    @State private var shareCommentTarget: RedditComment?

    var body: some View {
        List {
            if let header {
                header
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("profile.error")
            }
            // Listings can legitimately be empty (no posts, a private/suspended account, a
            // filtered saved category); the empty state tells that apart from a failed fetch.
            if isEmptyState {
                Text(emptyStateText)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("profile.emptyState")
            }
            if tab == .saved && !categories.isEmpty && generalSettings.allowSaveCategories {
                // Saved-category filter ("Show saved items for category…"), gated on
                // `AllowSaveCategories` (see `SavedCategoryMenuModifier`) so turning the feature
                // off hides both the assignment menu and this filter.
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(String?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(String?.some(category.name))
                    }
                }
                .pickerStyle(.menu)
            }
            if tab == .trophies {
                // Trophy Case as a browsable grid of Reddit trophy data.
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 16) {
                        ForEach(trophies) { trophy in
                            BadgeBookCell(trophy: trophy)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding()
                }
            } else if tab == .badges {
                // Badge Book: the Achievements catalog (79 entries in 5 categories) as a
                // browsable reference, since per-user earned status needs a WKWebView scrape this
                // app does not do, plus locally computed account-milestone badges with
                // earned/locked state from public API data. See `AchievementCatalog`.
                ForEach(AchievementCatalog.categories, id: \.self) { category in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 16) {
                            ForEach(AchievementCatalog.achievements(inCategory: category)) { achievement in
                                AchievementCell(achievement: achievement)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .padding()
                    } header: {
                        Text(category)
                            .apolloSectionHeader()
                    }
                }
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 16) {
                        ForEach(earnedBadges) { badge in
                            EarnedBadgeCell(badge: badge)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding()
                } header: {
                    Text("Account Milestones")
                        .apolloSectionHeader()
                } footer: {
                    Text("\(earnedBadges.filter(\.isEarned).count) of \(earnedBadges.count) milestones earned, computed locally from your account's public data.")
                    .apolloSectionFooter()
                }
            } else if tab == .multireddits {
                // User multireddits: another user's public ones only; private ones are not
                // visible via this endpoint.
                ForEach(multireddits) { multi in
                    SettingsLink(multi.displayName) {
                        FeedScreen(multireddit: multi, repository: repository)
                    }
                    // Only for the signed-in user's own multireddits: add/remove subreddits from the
                    // profile's Multis tab.
                    .swipeActions(edge: .trailing) {
                        if isOwnProfile {
                            Button {
                                managingSubredditsMultireddit = multi
                            } label: {
                                Label("Subreddits", systemImage: "list.bullet")
                            }
                            .tint(.green)
                        }
                    }
                }
            } else {
                ForEach(visibleItems) { item in
                    itemRow(item)
                        .onAppear { loadMoreIfNeeded(after: item) }
                }
                if after != nil, !items.isEmpty {
                    HStack {
                        Spacer()
                        if moreFailed {
                            Button("Try Again") { Task { await loadMore() } }
                        } else {
                            ProgressView()
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .modifier(ApolloThemedListBackground())
        // Rows size themselves (the profile menu's are 44pt), whatever
        // minimum an ancestor list set.
        .environment(\.defaultMinListRowHeight, 1)
        // Unwinds with the rest of the Posts tab on a tab re-tap.
        .apolloPopsOnTabReselection(item: $jumpTarget)
        .navigationDestination(item: $jumpTarget) { name in
            FeedScreen(subreddit: name, repository: repository)
        }
        .apolloTracksForwardNavigation($jumpTarget)
        .navigationDestination(item: $selectedPost) { post in
            PostDetailScreen(post: post, repository: repository)
        }
        .apolloTracksForwardNavigation($selectedPost)
        // A comment opens its thread, focused on it.
        .navigationDestination(item: $selectedComment) { link in
            CommentTreeScreen(subreddit: link.subreddit, postID: link.postID,
                              repository: repository, focusedCommentID: link.commentID)
        }
        .apolloTracksForwardNavigation($selectedComment)
        .navigationDestination(item: $authorTarget) { name in
            UserProfileScreen(username: name, repository: repository)
        }
        .apolloTracksForwardNavigation($authorTarget)
        .apolloPopsOnTabReselection(item: $selectedPost)
        .apolloForwardSwipe()
        // `task(id: tab)` re-runs when the segment changes (must reload) and when the
        // screen reappears after a pop (must not). Remembering which tab's data is
        // loaded separates the two; `id: tab` alone cannot.
        .task(id: tab) {
            guard loadedTab != tab else { return }
            await load()
            loadedTab = tab
        }
        .alert("New Saved Category", isPresented: $showingAddCategory) {
            TextField("Category name", text: $newCategoryName)
            Button("Add") {
                if SavedCategoryStore.addCategory(named: newCategoryName) {
                    categories = SavedCategoryStore.loadCategories()
                }
                newCategoryName = ""
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
        .sheet(item: $managingSubredditsMultireddit) { multi in
            NavigationStack {
                MultiredditSubredditsScreen(multireddit: multi, repository: repository) {
                    managingSubredditsMultireddit = nil
                    Task { await load() }
                }
            }
        }
        .apolloPostSwipePresenters(replyTarget: $postReplyTarget, shareTarget: $shareTarget,
                                   repository: repository)
        .sheet(item: $shareCommentTarget) { comment in
            ActivityShareSheet(items: [comment.shareURL()])
        }
        .sheet(item: $replyTarget) { comment in
            CommentComposerScreen(
                parentFullname: comment.name,
                repository: repository,
                quotedPreview: (author: comment.author, snippet: comment.body, age: comment.created.apolloRelativeTime),
                subreddit: comment.subreddit,
                onSubmitted: { replyTarget = nil }
            )
        }
    }

    private var isEmptyState: Bool {
        // Not while the first page loads, or the row would stay behind as a band under
        // the navigation bar once later pages arrive.
        guard errorMessage == nil, loadedTab == tab else { return false }
        switch tab {
        case .trophies: return trophies.isEmpty
        case .badges: return earnedBadges.isEmpty
        case .multireddits: return multireddits.isEmpty
        default: return visibleItems.isEmpty
        }
    }

    private var emptyStateText: String {
        switch tab {
        case .comments: return "No comments"
        case .posts: return "No posts"
        case .saved: return "No saved items"
        case .multireddits: return "No multireddits"
        case .trophies: return "No trophies"
        default: return "Nothing here"
        }
    }

    /// Filters the saved-items list to the selected category, if any -
    /// mirrors "Show saved items for category…".
    private var visibleItems: [ProfileItem] {
        guard tab == .saved, let selectedCategory else { return items }
        _ = assignmentVersion // establish dependency for recomputation
        return items.filter { SavedCategoryStore.category(for: $0.id) == selectedCategory }
    }

    /// Author taps open the author, except where every row is by this
    /// profile's user (it would reopen the same profile).
    private var authorsVary: Bool {
        [.saved, .upvoted, .downvoted, .hidden].contains(tab)
    }

    @ViewBuilder
    private func itemRow(_ item: ProfileItem) -> some View {
        switch item {
        case .comment(let comment):
            ProfileCommentRow(comment: comment, repository: repository, onSubredditTap: { name in jumpTarget = name })
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedComment = CommentLink(subreddit: comment.subreddit ?? "",
                                                  postID: String(comment.linkID.dropFirst(3)), commentID: comment.id)
                }
                .modifier(SavedCategoryMenuModifier(
                    isSaved: tab == .saved, fullname: comment.name, categories: categories,
                    onAddCategory: { showingAddCategory = true },
                    onAssign: {
                        SavedCategoryStore.assign(fullname: comment.name, category: $0)
                        assignmentVersion += 1
                    }))
                .accessibilityIdentifier("profile.commentRow.\(comment.id)")
                .apolloSwipeActions(settings: commentSwipeSettings, subject: SwipeSubject(comment: comment)) { action in
                    Task { await handleCommentSwipeAction(action, on: comment) }
                }
        case .post(let post):
            PostRow(post: post, repository: repository, displayStyle: generalSettings.postDisplayStyle, onSubredditTap: {
                jumpTarget = post.subreddit
            }, onAuthorTap: authorsVary ? { authorTarget = post.author } : {})
            .contentShape(Rectangle())
            .onTapGesture { selectedPost = post }
            .modifier(SavedCategoryMenuModifier(
                isSaved: tab == .saved,
                fullname: post.name,
                categories: categories,
                onAddCategory: { showingAddCategory = true },
                onAssign: {
                    SavedCategoryStore.assign(fullname: post.name, category: $0)
                    assignmentVersion += 1
                }
            ))
            .apolloSwipeActions(settings: postSwipeSettings, subject: SwipeSubject(post: post)) { action in
                Task { await handlePostSwipeAction(action, on: post) }
            }
        }
    }

    /// The listing for this tab, one page at a time. nil for tabs that
    /// aren't post/comment listings.
    private func fetchPage(after: String?) async throws -> RedditListing? {
        switch tab {
        case .overview: return try await repository.fetchUserOverview(username: username, after: after)
        case .comments: return try await repository.fetchUserComments(username: username, after: after)
        case .posts: return try await repository.fetchUserSubmitted(username: username, after: after)
        case .saved: return try await repository.fetchSavedItems(username: username, after: after)
        case .upvoted: return try await repository.fetchUserUpvoted(username: username, after: after)
        case .downvoted: return try await repository.fetchUserDownvoted(username: username, after: after)
        case .hidden: return try await repository.fetchUserHidden(username: username, after: after)
        default: return nil
        }
    }

    /// Reddit's user listings page 25 at a time.
    private func loadMoreIfNeeded(after item: ProfileItem) {
        guard after != nil, !isLoadingMore, !moreFailed,
              let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 5 else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard let cursor = after, !isLoadingMore else { return }
        let loadingTab = tab
        isLoadingMore = true
        moreFailed = false
        defer { isLoadingMore = false }
        do {
            guard let listing = try await fetchPage(after: cursor), loadingTab == tab else { return }
            items = RedditListing.appending(await listing.profileItemsInBackground(), to: items)
            after = listing.data.after
        } catch {
            if loadingTab == tab { moreFailed = true }
        }
    }

    private func load() async {
        // Clears a failure from a previous attempt.
        errorMessage = nil
        do {
            switch tab {
            case .trophies:
                trophies = await fetchTrophiesTolerant()
            case .badges:
                async let userTask = repository.fetchUserProfile(username: username)
                let badgeTrophies = await fetchTrophiesTolerant()
                let user = try await userTask
                badgeUser = user
                let context = BadgeEvaluationContext.from(user: user, trophies: badgeTrophies)
                earnedBadges = BadgeBookEngine.evaluate(context: context)
            case .multireddits:
                multireddits = try await repository.fetchPublicMultireddits(username: username)
            case .overview, .comments, .posts, .saved, .upvoted, .downvoted, .hidden:
                let loadingTab = tab
                guard let listing = try await fetchPage(after: nil), loadingTab == tab else { break }
                // Deduped: Reddit can return the same item twice in one
                // response (Reborn #1005, `SavedItemsDeduplicator`).
                items = RedditListing.appending(await listing.profileItemsInBackground(), to: [])
                after = listing.data.after
                moreFailed = false
            case .friends:
                // Apollo's friends screen is a user list, not a post/comment listing; it is
                // handled by the dedicated `FriendsListView`.
                break
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// The trophies endpoint can be unavailable (Reborn's badge-book scraper treats it
    /// as unreliable), so a failure degrades to an empty trophy case rather than a raw
    /// HTTP error.
    private func fetchTrophiesTolerant() async -> [RedditTrophy] {
        (try? await repository.fetchTrophies(username: username, isOwnProfile: isOwnProfile)) ?? []
    }

    private func handlePostSwipeAction(_ action: SwipeAction, on post: RedditPost) async {
        await ContentActions.perform(action, on: post, repository: repository, hooks: SwipeActionHooks(
            onReply: { postReplyTarget = post },
            onShare: { shareTarget = post },
            onHide: { items.removeAll { $0.id == post.name } },
            author: post.author, subreddit: post.subreddit
        ))
    }

    private func handleCommentSwipeAction(_ action: SwipeAction, on comment: RedditComment) async {
        await ContentActions.perform(action, on: comment, repository: repository, hooks: SwipeActionHooks(
            onReply: { replyTarget = comment },
            onShare: { shareCommentTarget = comment },
            // Reddit cannot hide comments; the row leaves this list.
            onHide: { items.removeAll { $0.id == comment.name } },
            author: comment.author, subreddit: comment.subreddit,
            selectableText: (title: comment.author, body: comment.body)
        ))
    }
}

/// Adds a "Set Saved Category" context menu to saved-item rows only,
/// reimplementing Apollo's Set Saved Category action ("Saved to new
/// category!", "Categorize your saved items").
struct SavedCategoryMenuModifier: ViewModifier {
    let isSaved: Bool
    let fullname: String
    let categories: [SavedCategory]
    let onAddCategory: () -> Void
    let onAssign: (String?) -> Void

    func body(content: Content) -> some View {
        // `AllowSaveCategories` is the master switch for Saved Categories. When off, the
        // category-assignment menu is not offered; the plain save/unsave action is
        // unaffected.
        if isSaved && GeneralSettingsStore.load().allowSaveCategories {
            content.contextMenu {
                ForEach(categories) { category in
                    Button(category.name) { onAssign(category.name) }
                }
                if !categories.isEmpty {
                    Button("None", role: .destructive) { onAssign(nil) }
                }
                Button("New Category…") { onAddCategory() }
            }
        } else {
            content
        }
    }
}

/// A user-listing comment row (Overview / Comments / Saved tabs).
///
/// Apollo's profile comment row: the thread's byline (avatar, author, score in the
/// vote colour, •••, age), the comment in 15pt with no link cards, then the post
/// it was left on in a #1A1A1A box: the title in 15pt over the subreddit in grey.
struct ProfileCommentRow: View {
    let comment: RedditComment
    var repository: RedditRepository? = nil
    var onSubredditTap: (String) -> Void = { _ in }

    @Setting(GeneralSettings.self) private var general
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if general.showUserProfilePictures, let repository {
                    AvatarView(username: comment.author, repository: repository, size: 27)
                }
                Text(comment.author)
                    .apolloFont(size: 15, weight: .medium)
                    .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: themeColors))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    StockIcon("posts-points")
                        .rotationEffect(.degrees(comment.likes == false ? 180 : 0))
                    Text(comment.scoreHidden ? "\u{2014}" : comment.score.apolloAbbreviated)
                        .apolloFont(size: 13)
                }
                .foregroundStyle(comment.likes == true ? Color.orange
                                 : (comment.likes == false ? Color.blue : Color.apolloIdleVoteArrow))
                .padding(.leading, 4)
                Spacer(minLength: 0)
                StockIcon("inline-more-options")
                    .foregroundStyle(colorScheme == .dark ? Color(hex: "505256") : Color(hex: "C4C4C6"))
                TimestampLabel(comment.created)
                    .apolloFont(size: 13)
                    .foregroundStyle(Color.apolloTertiaryText(colorScheme: colorScheme, themeColors: themeColors))
                    .padding(.leading, 11)
                    .fixedSize()
            }
            InlineMediaBodyView(comment.body, mediaMetadata: comment.mediaMetadata, showsLinkCards: false)
                .apolloFont(size: 15)
                .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: themeColors))
            if let linkTitle = comment.linkTitle {
                VStack(alignment: .leading, spacing: 6) {
                    Text(linkTitle)
                        .apolloFont(size: 15)
                        .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: themeColors))
                        .lineLimit(2)
                    if let subreddit = comment.subreddit {
                        Text(subreddit)
                            .apolloFont(size: 15)
                            .foregroundStyle(Color.apolloTertiaryText(colorScheme: colorScheme, themeColors: themeColors))
                            .contentShape(Rectangle())
                            .onTapGesture { onSubredditTap(subreddit) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.apolloFlairFill(colorScheme: colorScheme)))
            }
        }
        .padding(.vertical, 4)
    }
}
