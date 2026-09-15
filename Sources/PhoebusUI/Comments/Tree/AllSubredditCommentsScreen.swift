import SwiftUI
import PhoebusCore

/// A subreddit-wide feed of recent comments across all posts (distinct from a
/// single post's comment tree).
public struct AllSubredditCommentsScreen: View {
    let subreddit: String
    let repository: RedditRepository

    @State private var comments: [RedditComment] = []
    @State private var errorMessage: String?

    public init(subreddit: String, repository: RedditRepository) {
        self.subreddit = subreddit
        self.repository = repository
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(comment.author).font(.caption.bold())
                        Text("\(comment.score) pts").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(RedditMarkdown.render(comment.body)).font(.body).lineLimit(4)
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("r/\(subreddit) Comments")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            comments = try await repository.fetchRecentComments(subreddit: subreddit)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
