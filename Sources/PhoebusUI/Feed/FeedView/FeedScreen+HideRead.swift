import SwiftUI
import PhoebusCore

/// Apollo's "Show Hide Read Button" and "Auto Hide Read Posts"
/// (Settings > General > Mark Read / Hiding Posts).
extension FeedScreen {
    var isSignedIn: Bool { FavoriteSubredditsAccountContext.currentUsernameProvider() != nil }

    /// The floating button: hides the read posts on screen, on Reddit too
    /// when "Hide Posts…" is Permanently.
    func hideReadPosts() {
        let read = ReadPostStore.readPosts(in: posts)
        guard !read.isEmpty else { return }
        let permanent = markReadSettings.hideReadPosts
        if permanent, !isSignedIn {
            downloadTitle = "Sign In to Hide"
            downloadMessage = "You need to be signed in to hide read posts."
            return
        }
        Haptics.light()
        let ids = Set(read.map(\.name))
        withAnimation { posts.removeAll { ids.contains($0.name) } }
        guard permanent else { return }
        Task {
            do {
                try await repository.hide(fullnames: read.map(\.name))
            } catch {
                downloadTitle = "Error hiding read posts"
                downloadMessage = UserFacingError.text(for: error)
            }
        }
    }

    /// Auto Hide: on a refresh, the read posts still in the feed are
    /// hidden on Reddit before the new page loads.
    func autoHideReadPostsBeforeRefresh() async {
        guard isSignedIn,
              ReadPostStore.autoHides(markReadSettings, isSpecificSubreddit: !isAggregateFeed) else { return }
        let read = ReadPostStore.readPosts(in: posts).map(\.name)
        guard !read.isEmpty else { return }
        try? await repository.hide(fullnames: read)
    }
}

/// Apollo's floating Hide Read button: an accent circle with the stock
/// crossed-out eye.
struct HideReadPostsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StockIcon("hide-read-posts-button-eye", size: CGSize(width: 44, height: 44))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.apolloAccent))
                .shadow(radius: 2)
        }
        .accessibilityLabel("Hide Read Posts")
        .accessibilityIdentifier("feed.hideReadPostsButton")
    }
}
