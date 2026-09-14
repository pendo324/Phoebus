import SwiftUI
import PhoebusCore

/// Reborn's "Recently Read Posts": a chronological list of posts you've opened,
/// surfaced from the Profile tab. Stores only a lightweight local snapshot (see
/// `RecentlyReadStore`); tapping a row re-fetches the current post via
/// `fetchPost` before opening `PostDetailScreen`, so votes/edits/deletions are
/// reflected.
public struct RecentlyReadScreen: View {
    let repository: RedditRepository
    @State private var entries: [RecentlyReadEntry] = RecentlyReadStore.load()
    @State private var loadingFullname: String?
    @State private var errorMessage: String?
    @Setting(RecentlyReadSettingsStore.storage) private var settings
    /// Appearance settings "Always Show Usernames" / "Show Subreddit at Top": Reborn
    /// reads these two flags to govern this row's layout. Loaded once and refreshed in
    /// `.onAppear` like `settings` above, since the Appearance screen can change them
    /// while this one is backgrounded.
    @Setting(AppearanceSettingsStore.storage) private var appearanceSettings
    /// Apollo shows a persistent "Search Recently Read" field directly under the nav
    /// bar.
    @State private var searchText = ""

    public init(repository: RedditRepository) {
        self.repository = repository
    }

    private var visibleEntries: [RecentlyReadEntry] {
        var result = settings.filterNSFW ? entries.filter { !$0.isNSFW } : entries
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.subreddit.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if visibleEntries.isEmpty {
                Text("No recently read posts yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleEntries) { entry in
                    Button {
                        Task { await open(entry) }
                    } label: {
                        HStack {
                            if settings.showThumbnails, let thumbnailURL = entry.thumbnailURL, let url = URL(string: thumbnailURL) {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.2)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            // Rows show the subreddit name (caption, gray) first, then the post title
                            // (body-size) below it, with no author/time detail line. With "Show Subreddit at
                            // Top" the subreddit line moves above the title with the author inline; off (the
                            // default) keeps it below the title, with an optional "by <author>" appended when
                            // "Always Show Usernames" is on.
                            if appearanceSettings.showSubredditAtTop {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("r/\(SubredditCapitalization.display(entry.subreddit))")
                                            .font(.subheadline.weight(.medium))
                                        if appearanceSettings.alwaysShowUsernames, !entry.author.isEmpty {
                                            Text("u/\(entry.author)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(entry.title).font(.body).lineLimit(2)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title).font(.body).lineLimit(2)
                                    HStack(spacing: 4) {
                                        Text("r/\(SubredditCapitalization.display(entry.subreddit))")
                                        if appearanceSettings.alwaysShowUsernames, !entry.author.isEmpty {
                                            Text("by \(entry.author)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if loadingFullname == entry.fullname {
                                ProgressView()
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        // Filters an already-loaded local list, so search is a bottom-bar affordance on
        // glass; see the HIG classification in `GlassSearchField`. The persistent pill
        // under the nav bar is stated explicitly so this screen does not follow a
        // changed default.
        .apolloGlassSearchField(
            text: $searchText,
            prompt: "Search Recently Read",
            alwaysVisible: true
        )
        .apolloFlatListAppearance()
        .navigationTitle("Recently Read")
        // Apollo's back/forward page swipes.
        .apolloForwardSwipe()
        .toolbar {
            // A one-tap trash-can icon in the top-right nav-bar position for "clear all", as
            // in Apollo, rather than a nested menu item.
            ToolbarItem(placement: .primaryAction) {
                if !entries.isEmpty {
                    Button(role: .destructive) {
                        RecentlyReadStore.clearAll()
                        entries = []
                    } label: {
                        Image(systemName: "trash")
                        .accessibilityLabel("Clear All")
                    }
                    .accessibilityIdentifier("recentlyRead.clearAll")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Reborn's title is "Hide NSFW in Recently Read" (`UDKeyFilterNSFWRecentlyRead`).
                    Toggle("Hide NSFW in Recently Read", isOn: $settings.filterNSFW)
                    Toggle("Recently Read Thumbnails", isOn: $settings.showThumbnails)
                    Menu("Recently Read Posts Limit") {
                        Button("Unlimited") { $settings.update { $0.maxCount = nil } }
                        ForEach([25, 50, 100, 200], id: \.self) { limit in
                            Button("\(limit)") { $settings.update { $0.maxCount = limit } }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Limit")
                }
            }
        }
        .onAppear {
        }
        .apolloTracksForwardNavigation($isShowingPost)
        .navigationDestination(isPresented: $isShowingPost) {
            if let navigationPost {
                PostDetailScreen(post: navigationPost, repository: repository)
            }
        }
    }


    @State private var navigationPost: RedditPost?
    @State private var isShowingPost = false

    private func open(_ entry: RecentlyReadEntry) async {
        loadingFullname = entry.fullname
        errorMessage = nil
        defer { loadingFullname = nil }
        let postID = entry.fullname.replacingOccurrences(of: "t3_", with: "")
        do {
            navigationPost = try await repository.fetchPost(subreddit: entry.subreddit, postID: postID)
            isShowingPost = true
        } catch {
            errorMessage = "Couldn't load post — it may have been deleted."
        }
    }
}
