import Foundation
import PhoebusCore

/// Comment entry points into `ContentActions`.
public enum CommentVoting {
    @MainActor
    public static func vote(comment: RedditComment, direction: Int, repository: RedditRepository) async {
        await ContentActions.vote(comment, direction: direction, repository: repository)
    }

    @MainActor
    public static func toggle(comment: RedditComment, direction: Int, repository: RedditRepository) async {
        await ContentActions.toggleVote(comment, tapped: direction, repository: repository)
    }

    @MainActor
    public static func toggleSave(comment: RedditComment, repository: RedditRepository) async {
        await ContentActions.toggleSave(comment, repository: repository)
    }
}
