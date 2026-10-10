import SwiftUI
import PhoebusCore

/// Other Discussions: the other posts of a link, in feed rows, each
/// opening its thread. A Phoebus addition (see `OtherDiscussions`).
public struct OtherDiscussionsScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let post: RedditPost
    let repository: RedditRepository

    @State private var posts: [RedditPost] = []
    @State private var after: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    // See `JumpDestination`: SwiftUI dispatches `.navigationDestination(item:)` by
    // value type, not binding identity, so separate `String?` destinations collide.
    @State private var jumpDestination: JumpDestination?
    @State private var selectedPost: RedditPost?
    @State private var replyTarget: RedditPost?
    @State private var shareTarget: RedditPost?
    @Setting(SwipeActionStore.storage(for: .posts)) private var swipeSettings

    public init(post: RedditPost, repository: RedditRepository) {
        self.post = post
        self.repository = repository
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if posts.isEmpty && errorMessage == nil {
                if !hasLoaded {
                    ApolloLoadingCell()
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("otherDiscussions.loading")
                } else {
                    Text("No other discussions")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("otherDiscussions.empty")
                }
            }
            ForEach(posts) { other in
                // Same nested-tap handling as `PostSearchScreen`'s rows.
                PostRow(post: other, repository: repository, displayStyle: generalSettings.postDisplayStyle, onSubredditTap: {
                    jumpDestination = .subreddit(other.subreddit)
                }, onAuthorTap: {
                    jumpDestination = .user(other.author)
                })
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPost = other
                }
                .accessibilityIdentifier("otherDiscussions.row.\(other.id)")
                .apolloSwipeActions(settings: swipeSettings, subject: SwipeSubject(post: other)) { action in
                    Task { await handleSwipeAction(action, on: other) }
                }
                .onAppear {
                    if other.id == posts.last?.id { Task { await load() } }
                }
            }
            if isLoading, !posts.isEmpty {
                ApolloLoadingCell()
                    .listRowSeparator(.hidden)
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
        .navigationDestination(item: $selectedPost) { other in
            PostDetailScreen(post: other, repository: repository)
        }
        .apolloTracksForwardNavigation($selectedPost)
        .apolloOpensRedditTargetsHere()
        .apolloPostSwipePresenters(replyTarget: $replyTarget, shareTarget: $shareTarget,
                                   repository: repository)
        .apolloForwardSwipe()
        .refreshable { await load(reset: true) }
        .task { if !hasLoaded { await load() } }
        .apolloFlatListAppearance()
        .navigationTitle("Other Discussions")
        .accessibilityIdentifier("otherDiscussions.screen")
    }

    private func load(reset: Bool = false) async {
        guard !isLoading, reset || !hasLoaded || after != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repository.fetchOtherDiscussions(postID: post.id, after: reset ? nil : after)
            posts = reset ? page.posts : OtherDiscussions.appending(page.posts, to: posts)
            after = page.after
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        hasLoaded = true
    }

    private func handleSwipeAction(_ action: SwipeAction, on other: RedditPost) async {
        await ContentActions.perform(action, on: other, repository: repository, hooks: SwipeActionHooks(
            onReply: { replyTarget = other },
            onShare: { shareTarget = other },
            onHide: { posts.removeAll { $0.id == other.id } },
            author: other.author, subreddit: other.subreddit
        ))
    }
}

/// "N Other Discussions" under a link post's header, from the count the
/// comments response already carries, so it costs no extra request.
struct OtherDiscussionsRow: View {
    let count: Int
    let onTap: () -> Void
    @Environment(\.apolloTheme) private var apolloTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text(OtherDiscussions.countLabel(count))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .apolloFont(size: 14)
            .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.apolloSeparator(colorScheme: colorScheme))
                .frame(height: 1.0 / 3.0)
        }
        .accessibilityIdentifier("postDetail.otherDiscussionsRow")
    }
}
