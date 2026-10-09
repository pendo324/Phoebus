import Foundation

extension CommentTreeNode {
    /// Returns a new tree with the comment `id` changed by `change`. Nil when
    /// it is not in this subtree.
    public func editing(id: String, _ change: (inout RedditComment) -> Void) -> CommentTreeNode? {
        if self.id == id {
            var edited = comment
            change(&edited)
            return CommentTreeNode(comment: edited, depth: depth, children: children,
                                   isCollapsed: isCollapsed, moreStub: moreStub)
        }
        for (index, child) in children.enumerated() {
            if let updated = child.editing(id: id, change) {
                var copy = self
                copy.children[index] = updated
                return copy
            }
        }
        return nil
    }
}

extension Array where Element == CommentTreeNode {
    /// The forest with the comment `id` changed by `change`; unchanged when
    /// it is not in it.
    public func editingComment(id: String, _ change: (inout RedditComment) -> Void) -> [CommentTreeNode] {
        for (index, root) in enumerated() {
            if let updated = root.editing(id: id, change) {
                var copy = self
                copy[index] = updated
                return copy
            }
        }
        return self
    }

    /// A comment after its author saved an edit.
    public func settingBody(of id: String, to body: String) -> [CommentTreeNode] {
        editingComment(id: id) {
            $0.body = body
            $0.bodyHTML = nil
        }
    }

    /// A comment after its author deleted it: what Reddit lists in its place.
    public func markingDeleted(_ id: String) -> [CommentTreeNode] {
        editingComment(id: id) {
            $0.body = "[deleted]"
            $0.bodyHTML = nil
            $0.author = "[deleted]"
            $0.authorFlairText = nil
            $0.authorFlairRichtext = nil
        }
    }
}

/// What a comment the user just posted is missing until the thread reloads:
/// Reddit's answer to the post carries neither the "OP" mark nor the poster's
/// flair in every transport.
public enum PostedCommentContext {
    /// `comment` with the OP mark set when its author wrote the post, and the
    /// author's flair filled in from what is already loaded: the post, when
    /// the author wrote it, or an earlier comment by the same author. A
    /// flair Reddit sent is kept. With no source the flair stays empty;
    /// nothing is fetched.
    public static func decorate(_ comment: RedditComment, post: RedditPost?, roots: [CommentTreeNode]) -> RedditComment {
        var result = comment
        let author = comment.author
        guard !author.isEmpty, author != "[deleted]" else { return result }
        let wroteThePost = post.map { $0.author.caseInsensitiveCompare(author) == .orderedSame } ?? false
        if wroteThePost { result.isSubmitter = true }
        guard result.authorFlairText?.isEmpty ?? true, result.authorFlairRichtext?.isEmpty ?? true else { return result }
        if wroteThePost, let post, let text = post.authorFlairText, !text.isEmpty {
            result.authorFlairText = text
            result.authorFlairBackgroundColor = post.authorFlairBackgroundColor
            result.authorFlairTextColorRaw = post.authorFlairTextColorRaw
            return result
        }
        let earlier = roots.lazy.flatMap { $0.flattenedAll() }.map(\.comment).first {
            $0.author.caseInsensitiveCompare(author) == .orderedSame && !($0.authorFlairText?.isEmpty ?? true)
        }
        if let earlier {
            result.authorFlairText = earlier.authorFlairText
            result.authorFlairBackgroundColor = earlier.authorFlairBackgroundColor
            result.authorFlairTextColorRaw = earlier.authorFlairTextColorRaw
            result.authorFlairRichtext = earlier.authorFlairRichtext
        }
        return result
    }
}
