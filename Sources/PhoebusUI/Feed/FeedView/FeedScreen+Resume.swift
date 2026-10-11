import SwiftUI
import PhoebusCore

/// "Resume Where I Left Off" for the Posts tab's feeds; see `ResumeCoordinator`.
extension FeedScreen {
    var resumeDestination: LastViewedSubredditStore.Destination {
        ResumePolicy.feedDestination(subreddit: subreddit, multiredditPath: multiredditPath,
                                     multiredditName: multiredditDisplayName)
    }

    /// The frontmost feed on the Posts tab is the one a save describes.
    func registerForResume() {
        guard resumeTracksFeeds, feedResume.tracksRows else { return }
        feedResume.destination = resumeDestination
        feedResume.sort = sort
        feedResume.listing = listing
        ResumeCoordinator.shared.currentFeed = feedResume
    }

    /// On a resumed launch: back to the saved post once the feed has
    /// loaded (fetching up to `ResumePolicy.maxPagesToFind` pages to find
    /// it, else staying at the top), then the post that was open.
    func restoreResumedPlace() async {
        guard resumeTracksFeeds, feedResume.tracksRows,
              let snapshot = ResumeCoordinator.shared.claimFeed(resumeDestination) else { return }
        feedResume.openPost = snapshot.openPost
        if let target = snapshot.topPostID, snapshot.sort == nil || snapshot.sort == sort {
            feedResume.holdPosition(target)
            var pagesLoaded = 1
            while ResumePolicy.shouldLoadMore(toFind: target, loadedIDs: posts.map(\.id),
                                              pagesLoaded: pagesLoaded, reachedEnd: reachedEnd) {
                // A page already on its way (a row's infinite scroll) is
                // waited for and counted.
                let before = posts.count
                var waits = 0
                while isLoadingMore, waits < 100 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    waits += 1
                }
                if waits == 0 { await loadMore() }
                pagesLoaded += 1
                if posts.count == before { break }
            }
            if let scrollTarget = ResumePolicy.scrollTarget(for: snapshot, feedSort: sort,
                                                             loadedIDs: posts.map(\.id)) {
                await feedResume.restore(to: scrollTarget)
            } else {
                feedResume.releasePosition()
            }
        }
        guard let open = snapshot.openPost else { return }
        let post: RedditPost?
        if let loaded = posts.first(where: { $0.id == open.id }) {
            post = loaded
        } else {
            post = try? await repository.fetchPost(subreddit: open.subreddit, postID: open.id)
        }
        guard let post, selectedPost == nil else { return }
        jumpToCommentsOnOpen = false
        selectedPost = post
    }
}
