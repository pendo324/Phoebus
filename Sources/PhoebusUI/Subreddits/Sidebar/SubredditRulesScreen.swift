import SwiftUI
import PhoebusCore

/// Apollo's "Subreddit Rules" screen, reachable from the subreddit-level "•••"
/// action sheet (`RedditRepository.fetchSubredditRules`).
public struct SubredditRulesScreen: View {
    let subredditName: String
    let repository: RedditRepository

    @State private var rules: [SubredditRule] = []
    @State private var errorMessage: String?

    public init(subredditName: String, repository: RedditRepository) {
        self.subredditName = subredditName
        self.repository = repository
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(index + 1). \(rule.shortName)")
                        .font(.headline)
                    Text(RedditMarkdown.render(rule.description))
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("r/\(subredditName) Rules")
        // Apollo's back/forward page swipes.
        .apolloForwardSwipe()
        .task {
            do {
                rules = try await repository.fetchSubredditRules(name: subredditName)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}
