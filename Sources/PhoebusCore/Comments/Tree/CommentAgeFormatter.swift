import Foundation

/// What a comment's byline age counts from. Phoebus-only (not in Apollo or
/// Reborn), inspired by RedReader's comment age setting.
public enum CommentAgeMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Time since the comment was posted ("3h"), Apollo's label.
    case sincePosted
    /// Time between the post and the comment ("+3h").
    case relativeToPost
    /// Time between the parent comment and the reply ("2m later");
    /// top-level comments count from the post.
    case relativeToParent

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .sincePosted: return "Since Posted"
        case .relativeToPost: return "Relative to Post"
        case .relativeToParent: return "Relative to Parent"
        }
    }

    /// Falls back to `.sincePosted` for unrecognized raw values.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CommentAgeMode(rawValue: raw) ?? .sincePosted
    }
}

public enum CommentAgeFormatter {
    /// The byline age for a comment. Each mode falls back to the next
    /// simpler one when its reference time is unknown: a reply without a
    /// loaded parent counts from the post, and without the post the label
    /// is the plain age.
    public static func label(created: Date, postCreated: Date?, parentCreated: Date?,
                             mode: CommentAgeMode, now: Date = Date()) -> String {
        if mode == .relativeToParent, let parentCreated {
            return "\(Date.apolloCompactDuration(created.timeIntervalSince(parentCreated))) later"
        }
        if mode != .sincePosted, let postCreated {
            return "+\(Date.apolloCompactDuration(created.timeIntervalSince(postCreated)))"
        }
        let elapsed = now.timeIntervalSince(created)
        return elapsed < 60 ? "now" : Date.apolloCompactDuration(elapsed)
    }

    /// `label` for a comment in a loaded thread. `parent` is the comment
    /// it replies to, or nil for a top-level comment.
    public static func label(comment: RedditComment, post: RedditPost?, parent: RedditComment?,
                             mode: CommentAgeMode, now: Date = Date()) -> String {
        label(created: comment.created, postCreated: post?.created, parentCreated: parent?.created,
              mode: mode, now: now)
    }

    /// Every loaded comment by fullname, for looking up a reply's parent
    /// (`parentID` is the parent's fullname, or the post's for top-level).
    public static func commentsByFullname(_ roots: [CommentTreeNode]) -> [String: RedditComment] {
        var byName: [String: RedditComment] = [:]
        for node in roots.flatMap({ $0.flattenedAll() }) {
            byName[node.comment.name] = node.comment
        }
        return byName
    }
}
