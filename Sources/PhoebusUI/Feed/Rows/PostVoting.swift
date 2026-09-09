import Foundation
import PhoebusCore
#if canImport(SwiftUI)
import SwiftUI

/// `VoteStateStore` lives in PhoebusCore so its arithmetic is testable
/// on Linux, where Combine does not exist; it publishes changes through
/// a hand-rolled `objectWillChange`, and this is where it is declared
/// observable for SwiftUI.
extension VoteStateStore: @MainActor ObservableObject {}
#endif

/// The one place a post's vote is changed.
///
/// Every entry point goes through here (the arrow buttons, the Info Row
/// "tap score to upvote" action, and the swipe gestures) so they cannot
/// disagree about the resulting state.
/// Post entry points into `ContentActions`.
public enum PostVoting {
    @MainActor
    public static func vote(post: RedditPost, direction: Int, repository: RedditRepository) async {
        await ContentActions.vote(post, direction: direction, repository: repository)
    }

    @MainActor
    public static func toggle(post: RedditPost, direction: Int, repository: RedditRepository) async {
        await ContentActions.toggleVote(post, tapped: direction, repository: repository)
    }

    @MainActor
    public static func toggleSave(post: RedditPost, repository: RedditRepository) async {
        await ContentActions.toggleSave(post, repository: repository)
    }
}
