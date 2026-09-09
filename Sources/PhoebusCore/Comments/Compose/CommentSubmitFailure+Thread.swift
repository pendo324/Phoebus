import Foundation

/// Step two of "say why a comment didn't post" (Reborn #1275): when Reddit's
/// answer doesn't say, re-read the thread (the post, the comment being replied
/// to, the subreddit) and name what blocks it: a removed post and where the
/// moderators' reason is, a locked or archived thread, a removed or locked
/// parent, a ban or approved-users-only commenting. Only states that really
/// block a comment are claimed: a deleted post can still take replies, and
/// moderators can comment on removed and locked threads.
public extension CommentSubmitFailure {
    struct ThreadState {
        public var post: [String: Any]?
        public var parent: [String: Any]?
        public var subredditAbout: [String: Any]?
        /// A stickied moderator comment on the post reads like a removal reason.
        public var moderatorCommented = false
        public var username: String?

        public init(post: [String: Any]? = nil, parent: [String: Any]? = nil, subredditAbout: [String: Any]? = nil,
                    moderatorCommented: Bool = false, username: String? = nil) {
            self.post = post
            self.parent = parent
            self.subredditAbout = subredditAbout
            self.moderatorCommented = moderatorCommented
            self.username = username
        }
    }

    static func explain(state: ThreadState) -> Explanation? {
        func string(_ d: [String: Any]?, _ k: String) -> String? {
            (d?[k] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        func bool(_ d: [String: Any]?, _ k: String) -> Bool { (d?[k] as? Bool) ?? ((d?[k] as? NSNumber)?.boolValue ?? false) }
        func make(_ title: String, _ reason: String, _ hint: String? = nil) -> Explanation {
            Explanation(title: title, message: hint.map { "\(reason) \($0)" } ?? reason)
        }

        let post = state.post, parent = state.parent
        let subreddit = string(post, "subreddit") ?? string(parent, "subreddit")
        let moderators = subreddit.map { "the moderators of r/\($0)" } ?? "the moderators"
        let Moderators = subreddit.map { "The moderators of r/\($0)" } ?? "The moderators"
        let author = string(post, "author")
        let ownPost = author != nil && state.username != nil
            && author!.caseInsensitiveCompare(state.username!) == .orderedSame
        let thePost = ownPost ? "Your post" : "This post"
        let canModerate = bool(post, "can_mod_post") || bool(state.subredditAbout, "user_is_moderator")
        let reasonHint: String? = state.moderatorCommented
            ? "They left a comment on it explaining why (pull to refresh if you don't see it)."
            : ownPost ? "If they sent a reason, it's in your inbox." : nil

        if post != nil {
            if let removedBy = string(post, "removed_by_category"), removedBy != "deleted", removedBy != "author", !canModerate {
                switch removedBy {
                case "moderator":
                    return make("Post Removed", "\(thePost) was removed by \(moderators), so it can't take new comments.", reasonHint)
                case "automod_filtered":
                    return make("Post Awaiting Approval",
                                "\(thePost) was held by AutoModerator for \(moderators) to review, so it can't take comments until they approve it.",
                                state.moderatorCommented ? reasonHint : nil)
                case "reddit":
                    return make("Post Removed", "\(thePost) was removed by Reddit's filters, so it can't take new comments.")
                case "anti_evil_ops", "community_ops", "legal_operations", "copyright_takedown", "content_takedown":
                    return make("Post Removed", "\(thePost) was removed by Reddit, so it can't take new comments.")
                default:
                    return make("Post Removed", "\(thePost) was removed, so it can't take new comments.")
                }
            }
            if bool(post, "locked"), !canModerate {
                return make("Comments Locked", "\(Moderators) locked this thread, so it can't take new comments.")
            }
            if bool(post, "archived") {
                return make("Post Archived", "This post is archived, so it can't take new comments.")
            }
        }
        if parent != nil, !canModerate {
            if string(parent, "body") == "[removed]" {
                return make("Comment Removed", "The comment you're replying to was removed by \(moderators), so it can't take replies.")
            }
            if bool(parent, "locked") {
                return make("Replies Locked", "\(Moderators) locked the comment you're replying to, so it can't take replies.")
            }
        }
        if let about = state.subredditAbout, let subreddit {
            if bool(about, "user_is_banned") {
                return make("Banned from r/\(subreddit)", "You're banned from r/\(subreddit), so you can't comment there.")
            }
            if bool(about, "restrict_commenting"), !bool(about, "user_is_contributor"), !bool(about, "user_is_moderator") {
                return make("Commenting Restricted", "Only approved users can comment in r/\(subreddit).")
            }
        }
        return nil
    }

    /// A stickied moderator comment from the ModTeam account, or one that talks
    /// about removal.
    static func hasRemovalComment(_ commentsListing: [String: Any]?) -> Bool {
        let children = ((commentsListing?["data"] as? [String: Any])?["children"] as? [[String: Any]]) ?? []
        return children.contains { child in
            guard let comment = child["data"] as? [String: Any],
                  (comment["stickied"] as? Bool) == true, comment["distinguished"] as? String == "moderator" else { return false }
            let author = comment["author"] as? String ?? ""
            let body = comment["body"] as? String ?? ""
            return author.hasSuffix("-ModTeam") || body.range(of: "remov", options: .caseInsensitive) != nil
        }
    }

    /// Whether re-reading the thread can help: a comment on a post or comment,
    /// and a refusal the thread could explain; not a server error, a rate limit
    /// or a sign-in problem, which already say what happened.
    static func shouldLookUp(parentFullname: String, error: Error) -> Bool {
        guard parentFullname.hasPrefix("t3_") || parentFullname.hasPrefix("t1_") else { return false }
        if let rejected = error as? CommentRejectedError {
            return !["RATELIMIT", "THREAD_LOCKED", "TOO_OLD", "DELETED_LINK", "DELETED_COMMENT"].contains(rejected.code.uppercased())
        }
        if let api = error as? RedditAPIError {
            switch api {
            case .httpError(let status, _): return status < 500 && status != 429 && status != 401
            case .notAuthenticated, .sessionExpired: return false
            case .decodingFailed: return true
            }
        }
        return false
    }
}

public extension RedditRepository {
    /// Why a comment under `parentFullname` failed: the thread's own state when
    /// re-reading it explains the refusal, else Reddit's answer. The lookups get
    /// 5 s in all.
    func explainCommentFailure(_ error: Error, parentFullname: String) async -> CommentSubmitFailure.Explanation {
        guard CommentSubmitFailure.shouldLookUp(parentFullname: parentFullname, error: error) else {
            return CommentSubmitFailure.explain(error)
        }
        let fromThread = await withTaskGroup(of: CommentSubmitFailure.Explanation?.self) { group in
            group.addTask { await self.threadExplanation(parentFullname: parentFullname) }
            group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return fromThread ?? CommentSubmitFailure.explain(error)
    }

    private func threadExplanation(parentFullname: String) async -> CommentSubmitFailure.Explanation? {
        func object(_ data: Data?) -> Any? { data.flatMap { try? JSONSerialization.jsonObject(with: $0) } }
        func firstChild(_ listing: Any?) -> [String: Any]? {
            (((listing as? [String: Any])?["data"] as? [String: Any])?["children"] as? [[String: Any]])?.first?["data"] as? [String: Any]
        }
        var state = CommentSubmitFailure.ThreadState()
        state.username = try? await fetchIdentity().name
        var link = parentFullname
        if parentFullname.hasPrefix("t1_") {
            state.parent = firstChild(object(try? await client.get(path: "/api/info", parameters: ["id": parentFullname])))
            link = state.parent?["link_id"] as? String ?? ""
        }
        if link.hasPrefix("t3_") {
            // One read gives the post and its first top-level comments,
            // where a stickied removal reason sits.
            let listings = object(try? await client.get(path: "/comments/\(link.dropFirst(3))",
                                                        parameters: ["limit": "3", "depth": "1"])) as? [Any]
            state.post = firstChild(listings?.first)
            state.moderatorCommented = CommentSubmitFailure.hasRemovalComment(listings?.dropFirst().first as? [String: Any])
        }
        if CommentSubmitFailure.explain(state: state) == nil,
           let subreddit = (state.post?["subreddit"] ?? state.parent?["subreddit"]) as? String {
            state.subredditAbout = (object(try? await client.get(path: "/r/\(subreddit)/about")) as? [String: Any])?["data"] as? [String: Any]
        }
        return CommentSubmitFailure.explain(state: state)
    }
}
