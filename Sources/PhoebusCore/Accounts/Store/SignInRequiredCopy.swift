import Foundation

/// Apollo's "you have to be signed in to do that" alerts.
///
/// A signed-out action puts up a titled alert naming the action, matching
/// Apollo's copy:
///
///     Sign In to Upvote   / You need to be signed in to upvote.
///     Sign In to Downvote / You need to be signed in to downvote.
///     Sign In to Reply    / You need to be signed in to reply.
///
/// plus the same pattern for other gated actions
/// (`Sign In to Block`, `Sign In to Filter`,
/// `Sign In to Gift Awards`, `Sign In to Add Reminders`,
/// `Sign In to Use Notifications`, ...).
///
/// Without it, a signed-out vote is applied optimistically and reverted
/// when the request throws `RedditAPIError.notAuthenticated`, with no
/// explanation.
public enum SignInRequiredCopy {
    /// The actions Apollo names in these alerts.
    public enum Action: Sendable {
        case upvote
        case downvote
        case reply
        case save
        case block
        case filter

        /// Alert titles, verbatim.
        public var title: String {
            switch self {
            case .upvote: return "Sign In to Upvote"
            case .downvote: return "Sign In to Downvote"
            case .reply: return "Sign In to Reply"
            // Apollo has the MESSAGE for this one
            // ("You need to be signed in to save.") but no matching
            // title, so its alert is presented message-only rather
            // than inventing a title Apollo never shipped.
            case .save: return ""
            case .block: return "Sign In to Block"
            case .filter: return "Sign In to Filter"
            }
        }

        /// Alert messages, verbatim where Apollo ships one.
        public var message: String {
            switch self {
            case .upvote: return "You need to be signed in to upvote."
            case .downvote: return "You need to be signed in to downvote."
            case .reply: return "You need to be signed in to reply."
            // Verbatim; see the title note above.
            case .save: return "You need to be signed in to save."
            case .block: return "You need to be signed in to block users."
            case .filter: return "You need to be signed in to filter subreddits."
            }
        }
    }

    /// Maps a vote direction onto the action, so the alert names the
    /// direction the user actually swiped or tapped.
    public static func voteAction(direction: Int) -> Action {
        direction < 0 ? .downvote : .upvote
    }

    /// Whether `error` is the signed-out case this alert exists for. A pure
    /// function in PhoebusCore so the smoke tests can drive it directly.
    public static func isSignedOut(_ error: Error) -> Bool {
        if case RedditAPIError.notAuthenticated = error { return true }
        return false
    }
}
