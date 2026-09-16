import SwiftUI
import PhoebusCore

/// Full-text post search, scoped to a subreddit when opened from its feed, or
/// site-wide when opened from Home.
public struct PostSearchScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let subreddit: String
    let repository: RedditRepository

    @State private var query: String
    @State private var sort = "relevance"
    @State private var posts: [RedditPost] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    // See `JumpDestination`: SwiftUI dispatches `.navigationDestination(item:)` by
    // value type, not binding identity, so separate `String?` destinations collide.
    @State private var jumpDestination: JumpDestination?
    @State private var selectedPost: RedditPost?
    @State private var replyTarget: RedditPost?
    @State private var shareTarget: RedditPost?
    /// Uses the Posts swipe-action store (`SwipeActionStore(for: .posts)`), shared
    /// with `FeedScreen`; search results are not a separate section in Apollo's
    /// Gestures screen.
    @Setting(SwipeActionStore.storage(for: .posts)) private var swipeSettings

    private static let sorts = ["relevance", "hot", "top", "new", "comments"]

    public init(subreddit: String, repository: RedditRepository, initialQuery: String = "") {
        self.subreddit = subreddit
        self.repository = repository
        _query = State(initialValue: initialQuery)
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            // Loading and empty states distinguish an in-flight search from one that found
            // nothing.
            if posts.isEmpty && errorMessage == nil {
                if isLoading {
                    ApolloLoadingCell()
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("search.loading")
                } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("No results")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("search.empty")
                }
            }
            ForEach(posts) { post in
                // Same nested-tap handling as FeedScreen's row: a `NavigationLink` label swallows
                // taps like a `Button`, so the subreddit/author `.highPriorityGesture` taps need a
                // plain `.onTapGesture`.
                PostRow(post: post, repository: repository, displayStyle: generalSettings.postDisplayStyle, onSubredditTap: {
                    jumpDestination = .subreddit(post.subreddit)
                }, onAuthorTap: {
                    jumpDestination = .user(post.author)
                })
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPost = post
                }
                .apolloSwipeActions(settings: swipeSettings, subject: SwipeSubject(post: post)) { action in
                    Task { await handleSwipeAction(action, on: post) }
                }
            }
        }
        .navigationDestination(item: $jumpDestination) { destination in
            switch destination {
            case .subreddit(let name):
                FeedScreen(subreddit: name, repository: repository)
            case .user(let username):
                UserProfileScreen(username: username, repository: repository)
            }
        }
        .apolloTracksForwardNavigation($jumpDestination)
        .navigationDestination(item: $selectedPost) { post in
            PostDetailScreen(post: post, repository: repository)
        }
        .apolloTracksForwardNavigation($selectedPost)
        .apolloOpensRedditTargetsHere()
        .apolloPostSwipePresenters(replyTarget: $replyTarget, shareTarget: $shareTarget,
                                   repository: repository)
        .apolloForwardSwipe()
        // A scoped query page, not a filter over visible content, so it keeps the top
        // field like the Search tab's root (see `GlassSearchField`). Pinned, as in
        // `SubredditSearchScreen`: a bare `.searchable` hides its field until the list is
        // pulled down.
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: subreddit.isEmpty ? "Search all of Reddit" : "Search r/\(subreddit)")
        .onSubmit(of: .search) {
            Task { await search() }
        }
        .task {
            if !query.isEmpty { await search() }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Each row gets its per-sort icon and the active row a checkmark, as in Apollo's
                // "Sort by…" sheet. The toolbar glyph stays fixed: a label that changes with
                // state makes the nav bar jump.
                Menu {
                    ForEach(Self.sorts, id: \.self) { s in
                        Button {
                            sort = s
                            Task { await search() }
                        } label: {
                            // Icon rows carry no checkmark; only icon-less rows get one, as in Apollo's glass
                            // sort menu.
                            Label { Text(s.capitalized) } icon: { ApolloIconImage(FeedScreen.iconName(forSort: s)) }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                    .accessibilityLabel("Sort")
                }
            }
        }
    }

    private func search() async {
        // Clears a failure from a previous attempt.
        errorMessage = nil
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            posts = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        // Only the answer to the latest query and sort lands; a slower earlier search
        // must not overwrite a newer one.
        let asked = (query, sort)
        do {
            let listing = try await repository.searchPosts(query: query, subreddit: subreddit.isEmpty ? nil : subreddit, sort: sort)
            let found = await listing.postsInBackground()
            guard asked == (query, sort) else { return }
            posts = found
        } catch {
            guard asked == (query, sort) else { return }
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func handleSwipeAction(_ action: SwipeAction, on post: RedditPost) async {
        await ContentActions.perform(action, on: post, repository: repository, hooks: SwipeActionHooks(
            onReply: { replyTarget = post },
            onShare: { shareTarget = post },
            onHide: { posts.removeAll { $0.id == post.id } },
            author: post.author, subreddit: post.subreddit
        ))
    }
}
