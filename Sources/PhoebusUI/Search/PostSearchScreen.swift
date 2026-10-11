import SwiftUI
import PhoebusCore

/// Full-text post search, scoped to a subreddit when opened from its feed, or
/// site-wide when opened from Home.
public struct PostSearchScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let subreddit: String
    let repository: RedditRepository

    @State private var query: String
    @State private var sort: String
    /// Reddit's `t` for the Top and Comments sorts.
    @State private var time: String
    /// What the current results are for, which "Save Search" pins.
    @State private var searchedQuery = ""
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

    public init(subreddit: String, repository: RedditRepository, initialQuery: String = "",
                initialSort: String = "relevance", initialTime: String? = nil) {
        self.subreddit = subreddit
        self.repository = repository
        _query = State(initialValue: initialQuery)
        _sort = State(initialValue: initialSort)
        _time = State(initialValue: initialTime ?? "all")
    }

    private var currentSavedSearch: SavedSearch {
        SavedSearch(query: searchedQuery, subreddit: subreddit, sort: sort, time: time)
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            // Phoebus addition: this scope's recent and saved searches before typing.
            if query.isEmpty {
                RecentSearchesSection(subreddit: subreddit) { entry in
                    run(query: entry.query)
                }
                SavedSearchesSection(subreddit: subreddit) { saved in
                    run(query: saved.query, sort: saved.sort, time: saved.time)
                }
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
        // Clearing the field goes back to recent and saved searches.
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty {
                posts = []
                searchedQuery = ""
                errorMessage = nil
            }
        }
        .task {
            if !query.isEmpty { await search() }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Search")
        .toolbar {
            if !searchedQuery.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    SaveSearchButton(search: currentSavedSearch)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Each row gets its per-sort icon and the active row a checkmark, as in Apollo's
                // "Sort by…" sheet. The toolbar glyph stays fixed: a label that changes with
                // state makes the nav bar jump.
                Menu {
                    ForEach(Self.sorts, id: \.self) { s in
                        if SavedSearch.sortsWithTime.contains(s) {
                            Menu {
                                ForEach(FeedScreen.timeframes, id: \.value) { option in
                                    Button(option.label) {
                                        sort = s
                                        time = option.value
                                        Task { await search() }
                                    }
                                }
                            } label: {
                                Label { Text(s.capitalized) } icon: { ApolloIconImage(FeedScreen.iconName(forSort: s)) }
                            }
                        } else {
                            Button {
                                sort = s
                                Task { await search() }
                            } label: {
                                // Icon rows carry no checkmark; only icon-less rows get one, as in Apollo's glass
                                // sort menu.
                                Label { Text(s.capitalized) } icon: { ApolloIconImage(FeedScreen.iconName(forSort: s)) }
                            }
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
            searchedQuery = ""
            return
        }
        isLoading = true
        defer { isLoading = false }
        searchedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        SearchHistoryStore.record(query: searchedQuery, subreddit: subreddit)
        // Only the answer to the latest query, sort and time lands; a slower earlier
        // search must not overwrite a newer one.
        let asked = [query, sort, time]
        do {
            let listing = try await repository.searchPosts(query: query, subreddit: subreddit.isEmpty ? nil : subreddit, sort: sort,
                                                           time: SavedSearch.sortsWithTime.contains(sort) ? time : nil)
            let found = await listing.postsInBackground()
            guard asked == [query, sort, time] else { return }
            posts = found
        } catch {
            guard asked == [query, sort, time] else { return }
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func run(query newQuery: String, sort newSort: String? = nil, time newTime: String? = nil) {
        query = newQuery
        if let newSort { sort = newSort }
        if let newTime { time = newTime }
        Task { await search() }
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

/// "Save Search" / "Remove from Saved" for a results screen's toolbar.
private struct SaveSearchButton: View {
    @Setting(SearchHistoryStore.storage) private var history
    let search: SavedSearch

    var body: some View {
        let isSaved = SearchHistoryStore.lists(in: history).isSaved(search)
        Button {
            if isSaved {
                SearchHistoryStore.unsave(search)
            } else {
                SearchHistoryStore.save(search)
            }
        } label: {
            Image(systemName: isSaved ? "star.fill" : "star")
        }
        .accessibilityLabel(isSaved ? "Remove from Saved Searches" : "Save Search")
        .accessibilityIdentifier("search.saveSearch")
    }
}
