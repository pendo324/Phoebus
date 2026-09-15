import SwiftUI
import PhoebusCore

/// r/<sub>'s public moderator list, reached from the subreddit "•••" menu's "View
/// Moderators" row.
public struct SubredditModeratorsScreen: View {
    let subredditName: String
    let repository: RedditRepository

    @State private var moderators: [ModeratorListedUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let showAvatars = GeneralSettingsStore.load().showUserProfilePictures

    public init(subredditName: String, repository: RedditRepository) {
        self.subredditName = subredditName
        self.repository = repository
    }

    public var body: some View {
        List {
            if isLoading {
                ApolloLoadingCell()
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if moderators.isEmpty {
                Text("No moderators listed.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(moderators) { moderator in
                    SettingsLink {
                        UserProfileScreen(username: moderator.name, repository: repository)
                    } label: {
                        HStack(spacing: 12) {
                            // Reborn "Moderator Avatars": follows Show
                            // User Avatars (ShowUserAvatars), 32pt.
                            if showAvatars {
                                AvatarView(username: moderator.name, repository: repository, size: 32)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("u/\(moderator.name)")
                                // Reddit returns a mod's flair-ish note in
                                // the same `note` field the ban lists use.
                                if let note = moderator.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("subredditModerators.row.\(moderator.name)")
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Moderators")
        // Apollo's back/forward page swipes.
        .apolloForwardSwipe()
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            moderators = try await repository.fetchPublicModerators(subreddit: subredditName)
        } catch {
            errorMessage = "Couldn't load moderators. \(error.localizedDescription)"
        }
    }
}
