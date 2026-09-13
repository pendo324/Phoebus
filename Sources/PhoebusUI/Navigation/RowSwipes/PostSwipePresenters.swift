import SwiftUI
import PhoebusCore

extension View {
    /// The Reply and Share targets a post list's swipe actions open:
    /// Reply pushes the post with its composer open, Share opens the share
    /// sheet with the host-aware link.
    func apolloPostSwipePresenters(replyTarget: Binding<RedditPost?>,
                                   shareTarget: Binding<RedditPost?>,
                                   repository: RedditRepository) -> some View {
        self
            .navigationDestination(item: replyTarget) { post in
                PostDetailScreen(post: post, repository: repository,
                                 startScrolledToComments: true, startComposingReply: true)
            }
            .apolloTracksForwardNavigation(replyTarget)
            .sheet(item: shareTarget) { post in
                ActivityShareSheet(items: [post.shareText()])
            }
    }
}
