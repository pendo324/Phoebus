import Foundation

/// Reborn "Jump Button Navigation: New Comments" (`Apollo-Reborn#1506`): the
/// jump button steps through the comments that are new since the last visit,
/// next on a tap and previous on a hold, wrapping at either end. Only rows on
/// screen count, so a new reply inside a collapsed branch is skipped, and the
/// reader's own comments never count. An unloaded "N more replies" row is a
/// stop of its own: the caller loads it and asks again from the same anchor.
public enum NewCommentNavigator {
    /// One row of the displayed thread, in display order.
    public enum Row: Equatable, Sendable {
        case comment(id: String, author: String)
        /// `expandable` is false for a "Continue thread…" row, which opens a
        /// different screen instead of inserting replies in place.
        case more(id: String, expandable: Bool)

        public var id: String {
            switch self {
            case .comment(let id, _), .more(let id, _): return id
            }
        }
    }

    /// Where a search starts from; steps are strictly before or after it.
    public enum Anchor: Equatable, Sendable {
        case top
        case row(String)
        case end
    }

    public enum Step: Equatable, Sendable {
        case comment(id: String, ordinal: Int, total: Int, wrapped: Bool)
        case expand(stubID: String)
        case none
    }

    /// The rows `ForEach` draws: collapsed branches hide their replies, and each
    /// node's trailing "more" stub follows its replies.
    public static func rows(roots: [CommentTreeNode], rootMoreStub: MoreStub?) -> [Row] {
        var items = roots.flatMap { $0.visibleFlattenedWithMore() }
        if let rootMoreStub { items.append(.more(rootMoreStub)) }
        return items.map { item in
            switch item {
            case .comment(let node): return .comment(id: node.id, author: node.comment.author)
            case .more(let stub): return .more(id: stub.id, expandable: !stub.isContinueThread)
            }
        }
    }

    /// Where the reader is: the comment the last jump landed on while it is
    /// still at the top of the screen, otherwise the topmost row on screen.
    /// `onScreen` is nil when the list cannot be inspected, and the walk then
    /// carries on from the last landing.
    public static func anchor(rows: [Row], onScreen: Set<String>?, cursorID: String?) -> Anchor {
        guard let onScreen else {
            if let cursorID, rows.contains(where: { $0.id == cursorID }) { return .row(cursorID) }
            return .top
        }
        guard let top = rows.firstIndex(where: { onScreen.contains($0.id) }) else { return .top }
        if let cursorID, onScreen.contains(cursorID),
           let cursor = rows.firstIndex(where: { $0.id == cursorID }), abs(cursor - top) <= 1 {
            return .row(cursorID)
        }
        return .row(rows[top].id)
    }

    /// The next (`direction` > 0) or previous (< 0) stop from `anchor`.
    public static func step(rows: [Row], newIDs: Set<String>, ownUsername: String?, anchor: Anchor,
                            direction: Int, skippedStubs: Set<String> = []) -> Step {
        guard direction != 0 else { return .none }
        let targets = rows.indices.filter { index in
            switch rows[index] {
            case .comment(let id, let author):
                return newIDs.contains(id) && !isOwn(author, ownUsername)
            case .more(let id, let expandable):
                return expandable && !skippedStubs.contains(id)
            }
        }
        guard !targets.isEmpty else { return .none }

        let anchorIndex: Int
        switch anchor {
        case .top: anchorIndex = -1
        case .end: anchorIndex = rows.count
        case .row(let id):
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return .none }
            anchorIndex = index
        }
        let ahead = direction > 0 ? targets.first { $0 > anchorIndex } : targets.last { $0 < anchorIndex }
        let wrapped = ahead == nil
        guard let chosen = ahead ?? (direction > 0 ? targets.first : targets.last) else { return .none }

        if case .more(let id, _) = rows[chosen] { return .expand(stubID: id) }
        let comments = targets.filter { if case .comment = rows[$0] { return true } else { return false } }
        let ordinal = (comments.firstIndex(of: chosen) ?? 0) + 1
        return .comment(id: rows[chosen].id, ordinal: ordinal, total: comments.count, wrapped: wrapped)
    }

    private static func isOwn(_ author: String, _ username: String?) -> Bool {
        guard let username, !username.isEmpty, !author.isEmpty else { return false }
        return author.caseInsensitiveCompare(username) == .orderedSame
    }
}
