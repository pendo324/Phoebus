import SwiftUI
import PhoebusCore

/// The Posts preview: the feed's own `PostRow` for the sample post at the
/// current Post Size, with the sample's poll under it. Phoebus-only; neither
/// Apollo nor Reborn previews a post.
///
/// The row is the real one, so every Posts setting reaches it the way it
/// reaches the feed. It is shown as on an aggregate feed (subreddit icons, the
/// subreddit at the top and usernames all apply there), at the app-wide
/// Post Size: the per-subreddit sizes only matter inside a feed. A feed row
/// never draws a poll (the post screen does), so the poll is `PollView` under
/// the row.
struct PostsPreview: View {
    let repository: RedditRepository
    @Setting(GeneralSettings.self) private var general
    @State private var post = SettingsPreviewSample.post(imageURL: SettingsPreviewImage.url)

    var body: some View {
        let large = general.postDisplayStyle == .large
        VStack(alignment: .leading, spacing: 0) {
            PostRow(post: post, repository: repository, displayStyle: general.postDisplayStyle,
                    onSubredditTap: {}, onAuthorTap: {})
                .environment(\.postRowHeroHeight, 140)
                .padding(large ? EdgeInsets() : EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            if let poll = post.pollData {
                PollView(post: post, poll: poll, repository: repository, readOnly: !general.pollsEnabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .inertSettingsPreview(label: "Preview: a sample post as it appears in a feed, with a poll.")
        .accessibilityIdentifier("posts.preview")
    }
}
