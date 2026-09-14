import SwiftUI
import Foundation
import PhoebusCore

/// Reborn's own-profile "Hidden Posts" browser: the signed-in user's
/// `/user/<me>/hidden` listing, with unhide.
public struct HiddenPostsScreen: View {
    let username: String
    let repository: RedditRepository

    @State private var posts: [RedditPost] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    public init(username: String, repository: RedditRepository) {
        self.username = username
        self.repository = repository
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if posts.isEmpty && !isLoading && errorMessage == nil {
                Text("No hidden posts")
                    .foregroundStyle(.secondary)
            } else if posts.isEmpty && isLoading {
                // Separate case so the fetch shows a spinner instead of
                // "No hidden posts" flashing before results arrive.
                ApolloLoadingCell()
                    .listRowSeparator(.hidden)
            }
            ForEach(posts) { post in
                SettingsLink {
                    PostDetailScreen(post: post, repository: repository)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.title)
                        Text(SubredditCapitalization.display(post.subreddit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Unhide") {
                        Task {
                            try? await repository.unhide(fullname: post.name)
                            posts.removeAll { $0.id == post.id }
                        }
                    }
                }
                .accessibilityIdentifier("hiddenPosts.row.\(post.id)")
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Hidden Posts")
        .apolloForwardSwipe()
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        // A failure shown from an earlier attempt goes as this one starts.
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let listing = try await repository.fetchUserHidden(username: username)
            posts = await listing.postsInBackground()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
