import Foundation

/// A comment the reader collapsed or expanded by hand.
public struct CollapseChoice: Codable, Sendable, Equatable {
    public var id: String
    public var collapsed: Bool

    public init(id: String, collapsed: Bool) {
        self.id = id
        self.collapsed = collapsed
    }
}

/// What the reader collapsed or expanded in one thread, kept so reopening it
/// looks as they left it. Apollo's `CollapsedCommentsTracker` holds collapsed
/// comment ids per post; Phoebus keeps it across launches, in both directions,
/// and records only hand choices, never what auto-collapse decided, so a changed
/// Auto Collapse setting still applies to comments left alone.
public struct ThreadCollapseChoices: RememberedPosition {
    public var postID: String
    /// Set by Collapse/Expand Child Comments: every reply (depth 1 and below)
    /// not chosen individually since is collapsed or expanded. Keeps a bulk
    /// action from needing one entry per comment.
    public var allReplies: Bool?
    /// Oldest first; a comment chosen again moves to the end.
    public var choices: [CollapseChoice]

    public var key: String { postID }
    public var isEmpty: Bool { allReplies == nil && choices.isEmpty }

    /// Choices kept per thread before the oldest are dropped.
    public static let maxChoices = 150

    public init(postID: String, allReplies: Bool? = nil, choices: [CollapseChoice] = []) {
        self.postID = postID
        self.allReplies = allReplies
        self.choices = choices
    }

    public func choosing(_ id: String, collapsed: Bool) -> Self {
        var updated = self
        updated.choices.removeAll { $0.id == id }
        updated.choices.append(CollapseChoice(id: id, collapsed: collapsed))
        if updated.choices.count > Self.maxChoices {
            updated.choices.removeFirst(updated.choices.count - Self.maxChoices)
        }
        return updated
    }

    /// A bulk action covers every reply, so only the top-level comments'
    /// own choices (which the action leaves alone) still count.
    public func choosingAllReplies(_ collapsed: Bool, topLevelIDs: Set<String>) -> Self {
        Self(postID: postID, allReplies: collapsed, choices: choices.filter { topLevelIDs.contains($0.id) })
    }
}

public extension Array where Element == CommentTreeNode {
    /// Puts the reader's choices over a freshly built tree, after the
    /// auto-collapse rules and comment filters so a hand choice wins. The
    /// linked comment and its ancestors are left as built, or the link
    /// would open on a collapsed row. `includingAllReplies` is false for
    /// replies loaded later, which the bulk action never touched.
    func applyingCollapseChoices(_ saved: ThreadCollapseChoices?, includingAllReplies: Bool = true,
                                 focusedCommentID: String? = nil) -> [CommentTreeNode] {
        guard let saved, !saved.isEmpty else { return self }
        let chosen = Dictionary(saved.choices.map { ($0.id, $0.collapsed) }, uniquingKeysWith: { _, latest in latest })
        let bulk = includingAllReplies ? saved.allReplies : nil
        let linked = focusedCommentID.map { $0.hasPrefix("t1_") ? String($0.dropFirst(3)) : $0 }
        let untouched = linked.flatMap { id in
            ThreadPositionPolicy.ancestorPath(to: id, in: self).map { Set($0 + [id]) }
        } ?? []
        func apply(_ node: CommentTreeNode) -> CommentTreeNode {
            var copy = node
            if !untouched.contains(node.id) {
                if let collapsed = chosen[node.id] {
                    copy.isCollapsed = collapsed
                } else if node.depth >= 1, let bulk {
                    copy.isCollapsed = bulk
                }
            }
            copy.children = node.children.map(apply)
            return copy
        }
        return map(apply)
    }

    /// Whether the comment is collapsed now; nil when it isn't in the tree.
    func collapsedState(of id: String) -> Bool? {
        for node in self {
            if node.id == id { return node.isCollapsed }
            if let below = node.children.collapsedState(of: id) { return below }
        }
        return nil
    }
}

/// Saved collapse choices, per account (signed out is its own bucket) and
/// thread, persisted as one JSON blob. Phoebus-only; neither Apollo nor Reborn
/// writes them to `UserDefaults`.
public enum CommentCollapseStore {
    static let key = "com.pendo324.Phoebus.collapsedComments"

    /// Threads each account keeps before the least recently changed is dropped.
    public static let threadCapacity = 50

    typealias Book = [String: RememberedPositions<ThreadCollapseChoices>]

    /// The bucket for `username`; nil (signed out) maps to "".
    public static func bucket(for username: String?) -> String {
        username?.lowercased() ?? ""
    }

    private static func load(from defaults: UserDefaults) -> Book {
        guard let data = defaults.data(forKey: key),
              let book = try? JSONDecoder().decode(Book.self, from: data) else { return [:] }
        return book
    }

    /// `username` as passed (`.some(nil)` is signed out), or the active
    /// account when omitted.
    private static func bucketKey(_ username: String??) -> String {
        switch username {
        case .some(let name): return bucket(for: name)
        case .none: return bucket(for: FavoriteSubredditsAccountContext.currentUsernameProvider())
        }
    }

    public static func choices(postID: String, username: String?? = nil,
                               in defaults: UserDefaults = .standard) -> ThreadCollapseChoices? {
        load(from: defaults)[bucketKey(username)]?.entry(for: postID)
    }

    /// The reader collapsed or expanded one comment.
    public static func record(postID: String, commentID: String, collapsed: Bool, username: String?? = nil,
                              in defaults: UserDefaults = .standard) {
        update(postID: postID, username: username, in: defaults) {
            $0.choosing(commentID, collapsed: collapsed)
        }
    }

    /// The reader collapsed or expanded every reply at once.
    public static func recordAllReplies(postID: String, collapsed: Bool, topLevelIDs: Set<String>,
                                        username: String?? = nil, in defaults: UserDefaults = .standard) {
        update(postID: postID, username: username, in: defaults) {
            $0.choosingAllReplies(collapsed, topLevelIDs: topLevelIDs)
        }
    }

    /// Forgets one account's choices; other accounts keep theirs.
    public static func clear(username: String?? = nil, in defaults: UserDefaults = .standard) {
        var book = load(from: defaults)
        book[bucketKey(username)] = nil
        save(book, to: defaults)
    }

    private static func update(postID: String, username: String??, in defaults: UserDefaults,
                               _ change: (ThreadCollapseChoices) -> ThreadCollapseChoices) {
        guard !postID.isEmpty else { return }
        let bucket = bucketKey(username)
        var book = load(from: defaults)
        let current = book[bucket] ?? RememberedPositions()
        let updated = change(current.entry(for: postID) ?? ThreadCollapseChoices(postID: postID))
        book[bucket] = current.recording(updated, capacity: threadCapacity)
        save(book, to: defaults)
    }

    private static func save(_ book: Book, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: key)
    }
}
