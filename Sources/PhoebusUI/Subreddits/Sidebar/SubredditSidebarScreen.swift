import SwiftUI
import PhoebusCore

/// Subreddit sidebar: description and rules.
public struct SubredditSidebarScreen: View {
    let subredditName: String
    let repository: RedditRepository

    @State private var subreddit: RedditSubreddit?
    @State private var rules: [SubredditRule] = []
    @State private var errorMessage: String?
    @State private var isSubscribedOverride: Bool?
    @State private var moderators: [ModeratorListedUser] = []
    @State private var viewerURL: URL?
    /// Gates showing a "Manage Moderators" entry point to
    /// `ModeratorInviteScreen` (invite/accept/decline/remove-invite
    /// flow), separate from the flat read-only moderator list below.
    @State private var isModerator = false

    public init(subredditName: String, repository: RedditRepository) {
        self.subredditName = subredditName
        self.repository = repository
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let subreddit {
                // Reborn's full-screen "View Banner"/"View Icon" actions: tap either image to see
                // it fullscreen.
                if subreddit.bannerImage != nil || subreddit.iconImage != nil {
                    Section {
                        HStack(spacing: 12) {
                            if let bannerURLString = subreddit.bannerImage, let url = URL(string: bannerURLString) {
                                Button { viewerURL = url } label: {
                                    CachedAsyncImage(url: url)
                                        .frame(height: 60)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                            if let iconURLString = subreddit.iconImage, let url = URL(string: iconURLString) {
                                Button { viewerURL = url } label: {
                                    CachedAsyncImage(url: url)
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section {
                    Text(subreddit.title).font(.headline)
                    if let description = subreddit.publicDescription, !description.isEmpty {
                        Text(RedditMarkdown.render(description)).font(.body)
                    }
                    // The header is two stats: Subscribers and Active.
                    HStack(spacing: 16) {
                        if let subscribers = subreddit.subscribers {
                            Label(subscribers.apolloCounted("subscriber", "subscribers"), systemImage: "person.3")
                        }
                        if let active = subreddit.activeUserCount {
                            Label("\(active.apolloAbbreviated) active", systemImage: "circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button {
                        Task { await toggleSubscribe() }
                    } label: {
                        Label(
                            currentlySubscribed(subreddit) ? "Unsubscribe" : "Subscribe",
                            systemImage: currentlySubscribed(subreddit) ? "checkmark.circle.fill" : "plus.circle"
                        )
                    }
                    SettingsLink {
                        AllSubredditCommentsScreen(subreddit: subredditName, repository: repository)
                    } label: {
                        Label("Recent Comments", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
            // Apollo's sidebar does not list rules inline; it has a Rules button top-right,
            // added in the toolbar below. `rules` is still fetched because the button is only
            // meaningful when the subreddit has any.

            if !moderators.isEmpty {
                // The public moderator list, visible to anyone.
                Section("Moderators") {
                    if isModerator {
                        SettingsLink {
                            ModeratorInviteScreen(subreddit: subredditName, repository: repository, isViewedByMod: true)
                        } label: {
                            Label("Manage Moderators", systemImage: "person.badge.plus")
                        }
                    }
                    ForEach(moderators) { mod in
                        SettingsLink {
                            UserProfileScreen(username: mod.name, repository: repository)
                        } label: {
                            // Reborn: shows each moderator's avatar in the Mods list, reusing the inline
                            // user-avatars cache.
                            HStack(spacing: 10) {
                                AvatarView(username: mod.name, repository: repository, size: 24)
                                Text("u/\(mod.name)")
                            }
                        }
                    }
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("r/\(subredditName)")
        // Apollo's back/forward page swipes.
        .apolloForwardSwipe()
        // Rules button, top-right. Hidden when the subreddit publishes no rules.
        .toolbar {
            if !rules.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        SubredditRulesScreen(subredditName: subredditName, repository: repository)
                    } label: {
                        Text("Rules")
                    }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $viewerURL.isPresent()) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let viewerURL {
                    CachedAsyncImage(url: viewerURL)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .onTapGesture { viewerURL = nil }
        }
    }

    private func load() async {
        do {
            async let subredditTask = repository.fetchSubredditInfo(name: subredditName)
            async let rulesTask = repository.fetchSubredditRules(name: subredditName)
            async let modsTask = repository.fetchPublicModerators(subreddit: subredditName)
            let subredditInfo = try await subredditTask
            subreddit = subredditInfo
            isModerator = subredditInfo.userIsModerator == true
            rules = try await rulesTask
            moderators = (try? await modsTask) ?? []
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func currentlySubscribed(_ subreddit: RedditSubreddit) -> Bool {
        isSubscribedOverride ?? (subreddit.userIsSubscriber ?? false)
    }

    private func toggleSubscribe() async {
        guard let subreddit else { return }
        let newValue = !currentlySubscribed(subreddit)
        isSubscribedOverride = newValue
        do {
            try await repository.subscribe(subredditFullname: subreddit.name, subscribe: newValue)
        } catch {
            isSubscribedOverride = !newValue
        }
    }
}
