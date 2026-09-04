import Foundation

/// Reddit's "more comments" continuation stub (`kind: "more"` in the raw
/// comments listing): represents truncated replies at a given depth that
/// must be lazily fetched via `/api/morechildren`.
public struct MoreStub: Identifiable, Sendable, Equatable {
    /// Reddit's own "more" object id (e.g. "t1_abc123" or a
    /// synthetic "_" root placeholder for very large threads).
    public let id: String
    /// Number of additional replies this stub represents. Zero for a
    /// "Continue thread…" stub, which stands for an unknown number of
    /// replies below Reddit's depth limit.
    public let count: Int
    /// Child comment IDs to resolve via `/api/morechildren`.
    public let children: [String]
    /// Fullname of the parent comment/post this stub is nested under.
    public let parentID: String
    public let depth: Int

    /// Whether this is Reddit's depth-limit continuation rather than a
    /// resolvable list of ids. These have no ids to ask for, so the thread
    /// has to be re-requested rooted at `parentID`.
    ///
    /// Apollo shows these as "Continue thread..." rather than "N more replies".
    public var isContinueThread: Bool { children.isEmpty }

    public init(id: String, count: Int, children: [String], parentID: String, depth: Int) {
        self.id = id
        self.count = count
        self.children = children
        self.parentID = parentID
        self.depth = depth
    }
}

/// A single row in a flattened, render-ready comment stream: either a
/// real comment or a "N more replies" continuation stub that must be
/// resolved via `/api/morechildren` before it can be expanded.
public enum CommentDisplayValue: Identifiable, Sendable {
    case comment(CommentTreeNode)
    case more(MoreStub)

    public var id: String {
        switch self {
        case .comment(let node): return node.id
        case .more(let stub): return stub.id
        }
    }
}

/// Recursive comment tree node.
///
/// Value type by design: under Swift 6 strict concurrency a mutable reference
/// type can't safely conform to Sendable, and collapse toggling replaces the
/// tree rather than mutating shared references.
public struct CommentTreeNode: Identifiable, Sendable, Equatable {
    public let comment: RedditComment
    public let depth: Int
    public var children: [CommentTreeNode]
    public var isCollapsed: Bool
    /// A trailing "N more replies" continuation stub among this
    /// node's own children, if Reddit truncated the thread here.
    public var moreStub: MoreStub?

    public var id: String { comment.id }

    public init(comment: RedditComment, depth: Int, children: [CommentTreeNode] = [], isCollapsed: Bool = false, moreStub: MoreStub? = nil) {
        self.comment = comment
        self.depth = depth
        self.children = children
        self.isCollapsed = isCollapsed
        self.moreStub = moreStub
    }

    public static func == (lhs: CommentTreeNode, rhs: CommentTreeNode) -> Bool {
        lhs.id == rhs.id && lhs.isCollapsed == rhs.isCollapsed && lhs.children == rhs.children && lhs.moreStub == rhs.moreStub
    }

    /// Flattened depth-first traversal respecting collapse state: what a
    /// SwiftUI List/LazyVStack should render.
    public func visibleFlattened() -> [CommentTreeNode] {
        var result = [self]
        if !isCollapsed {
            for child in children {
                result.append(contentsOf: child.visibleFlattened())
            }
        }
        return result
    }

    /// Every descendant regardless of collapse state. Share as Image needs a
    /// comment's ancestors resolvable even when part of the thread above it is
    /// collapsed.
    public func flattenedAll() -> [CommentTreeNode] {
        [self] + children.flatMap { $0.flattenedAll() }
    }

    /// Like `visibleFlattened()`, but also yields this node's trailing `moreStub`
    /// (if any) as a `.more` item right after its own children.
    public func visibleFlattenedWithMore() -> [CommentDisplayValue] {
        guard !isCollapsed else { return [.comment(self)] }
        var result: [CommentDisplayValue] = [.comment(self)]
        for child in children {
            result.append(contentsOf: child.visibleFlattenedWithMore())
        }
        if let moreStub {
            result.append(.more(moreStub))
        }
        return result
    }

    /// Every comment ID in this subtree regardless of collapse state; used
    /// by `NewCommentsTracker` to diff the full comment set between visits.
    /// The comment plus every reply under it, counting replies Reddit has not
    /// sent yet (each `more` stub's `count`): Apollo's collapsed badge.
    public var threadCount: Int {
        1 + children.reduce(0) { $0 + $1.threadCount } + (moreStub?.count ?? 0)
    }

    public func allIDs() -> [String] {
        [id] + children.flatMap { $0.allIDs() }
    }

    /// Returns a new tree with `reply` added as the first child of the
    /// node whose fullname is `parentFullname` (Reddit shows a fresh
    /// reply at the top of its parent). Nil when the parent is not here.
    public func inserting(reply: RedditComment, under parentFullname: String) -> CommentTreeNode? {
        if comment.name == parentFullname {
            var copy = self
            copy.children.insert(CommentTreeNode(comment: reply, depth: depth + 1), at: 0)
            copy.isCollapsed = false
            return copy
        }
        for (index, child) in children.enumerated() {
            if let updated = child.inserting(reply: reply, under: parentFullname) {
                var copy = self
                copy.children[index] = updated
                return copy
            }
        }
        return nil
    }

    /// Returns a new tree with the node matching `id` toggled; callers replace
    /// their stored root array with the result.
    public func togglingCollapse(id: String) -> CommentTreeNode {
        if self.id == id {
            var copy = self
            copy.isCollapsed.toggle()
            return copy
        }
        var copy = self
        copy.children = children.map { $0.togglingCollapse(id: id) }
        return copy
    }

    /// Returns a new tree with every node at or below `collapsed` set to
    /// the same state. Backs "Collapse Child Comments" / "Expand Child
    /// Comments", which acts on the whole tree. Only children collapse,
    /// not the roots themselves.
    public func settingChildrenCollapsed(_ collapsed: Bool) -> CommentTreeNode {
        var copy = self
        copy.children = children.map { child in
            var updated = child
            updated.isCollapsed = collapsed
            return updated.settingChildrenCollapsed(collapsed)
        }
        return copy
    }

    /// Whether any node below this one is collapsed, so a menu row can
    /// show the right verb.
    public var hasCollapsedDescendant: Bool {
        children.contains { $0.isCollapsed || $0.hasCollapsedDescendant }
    }

    /// Replaces the `moreStub` matching `stubID` (found anywhere in this
    /// subtree) with freshly-fetched real children from
    /// `/api/morechildren`. Recurses into children so a deeply-nested
    /// stub resolves correctly.
    public func resolvingMoreStub(stubID: String, with newChildren: [CommentTreeNode]) -> CommentTreeNode {
        var copy = self
        if copy.moreStub?.id == stubID {
            copy.children.append(contentsOf: newChildren)
            copy.moreStub = nil
        } else {
            copy.children = copy.children.map { $0.resolvingMoreStub(stubID: stubID, with: newChildren) }
        }
        return copy
    }

    /// True if `id` is this node or any descendant's id; used by
    /// "Collapse Top" to find which top-level root a swiped-on nested
    /// reply belongs to.
    public func contains(id: String) -> Bool {
        self.id == id || children.contains { $0.contains(id: id) }
    }

    /// `HideBlockedUserComments`: removes this node (and its whole reply
    /// subtree) when its author is in `blockedAuthors`, reusing the same
    /// author list Filters & Blocks maintains. Non-blocked children of a
    /// kept node are recursed into individually. Case-insensitive on both
    /// sides.
    public func filteringBlockedAuthors(_ blockedAuthors: Set<String>) -> CommentTreeNode? {
        let lowercasedBlocked = Set(blockedAuthors.map { $0.lowercased() })
        guard !lowercasedBlocked.contains(comment.author.lowercased()) else { return nil }
        var copy = self
        copy.children = children.compactMap { $0.filteringBlockedAuthors(blockedAuthors) }
        return copy
    }
}

/// Forest-level convenience for `CommentTreeNode.filteringBlockedAuthors(_:)`.
public extension Array where Element == CommentTreeNode {
    func filteringBlockedAuthors(_ blockedAuthors: Set<String>) -> [CommentTreeNode] {
        guard !blockedAuthors.isEmpty else { return self }
        return compactMap { $0.filteringBlockedAuthors(blockedAuthors) }
    }

    /// "Blocked Users: Collapse" (Reddit's default): blocked users'
    /// comments start collapsed.
    func collapsingBlockedAuthors(_ blockedAuthors: Set<String>) -> [CommentTreeNode] {
        guard !blockedAuthors.isEmpty else { return self }
        let lowercased = Set(blockedAuthors.map { $0.lowercased() })
        func collapse(_ node: CommentTreeNode) -> CommentTreeNode {
            var copy = node
            if lowercased.contains(node.comment.author.lowercased()) { copy.isCollapsed = true }
            copy.children = node.children.map(collapse)
            return copy
        }
        return map(collapse)
    }

    /// Applies "Blocked Users": Hide removes their comments, Collapse
    /// starts them collapsed.
    func applyingBlockedUsers(_ blockedAuthors: Set<String>, hide: Bool) -> [CommentTreeNode] {
        hide ? filteringBlockedAuthors(blockedAuthors) : collapsingBlockedAuthors(blockedAuthors)
    }
}

extension RedditComment: Equatable {
    public static func == (lhs: RedditComment, rhs: RedditComment) -> Bool {
        lhs.id == rhs.id && lhs.score == rhs.score && lhs.body == rhs.body
    }
}

/// Builds a CommentTreeNode forest from Reddit's raw nested listing JSON
/// response for a comments endpoint. Reddit represents replies as either
/// an empty string "" (no replies) or a nested {kind: "Listing", data:
/// {children: [...]}} object, and "more comments" stubs as kind "more".
public enum CommentTreeBuilder {
    /// `autoCollapse` mirrors Apollo's "Auto Collapse Child Comments": every
    /// top-level comment with replies starts collapsed. `autoCollapsePinned`
    /// reimplements "Collapse Pinned Comments": every sticky/mod comment starts
    /// collapsed regardless of depth or replies.
    ///
    /// `parentID` is the fullname of the enclosing comment/post, needed
    /// to build a `MoreStub` for this level's trailing "more" object.
    /// `autoCollapseAutoModerator` reimplements "Collapse AutoModerator
    /// Comments": a comment whose author is exactly "AutoModerator" starts
    /// collapsed regardless of depth or stickied state.
    public static func build(from json: [JSONValue], depth: Int = 0, autoCollapse: Bool = false, autoCollapsePinned: Bool = false, autoCollapseAutoModerator: Bool = false, parentID: String = "") -> [CommentTreeNode] {
        buildLevel(from: json, depth: depth, autoCollapse: autoCollapse, autoCollapsePinned: autoCollapsePinned, autoCollapseAutoModerator: autoCollapseAutoModerator, parentID: parentID).nodes
    }

    /// Root-level entry point that also surfaces the top-level thread
    /// list's own trailing "more" stub (a sibling of the root comments,
    /// e.g. "15 more comments"); plain `build(from:)` drops this since
    /// most call sites only need the nodes.
    public static func buildRoots(from json: [JSONValue], postFullname: String, autoCollapse: Bool = false, autoCollapsePinned: Bool = false, autoCollapseAutoModerator: Bool = false) -> (roots: [CommentTreeNode], moreStub: MoreStub?) {
        let result = buildLevel(from: json, depth: 0, autoCollapse: autoCollapse, autoCollapsePinned: autoCollapsePinned, autoCollapseAutoModerator: autoCollapseAutoModerator, parentID: postFullname)
        return (result.nodes, result.moreStub)
    }

    /// Like `buildRoots(from:postFullname:...)`, but for resolving a "more
    /// replies" stub at an arbitrary nesting depth rather than the tree's
    /// root.
    ///
    /// Reddit's `/api/morechildren` response is a flat list of `t1`
    /// comment objects (no comment carries a populated `replies` field,
    /// even ones that are parents of others in the same list); each
    /// carries its own `parent_id` instead. This reconstructs the tree
    /// from those `parent_id` links, computing each comment's depth as an
    /// offset from `stub.depth` by walking the parent chain within the
    /// same flat batch.
    public static func buildResolved(from json: [JSONValue], stub: MoreStub, autoCollapse: Bool = false, autoCollapsePinned: Bool = false, autoCollapseAutoModerator: Bool = false) -> (roots: [CommentTreeNode], moreStub: MoreStub?) {
        var comments: [String: RedditComment] = [:]
        var order: [String] = []
        var moreStub: MoreStub?
        for value in json {
            guard case .object(let thing) = value,
                  case .string(let kind)? = thing["kind"],
                  case .object(let data)? = thing["data"] else { continue }
            if kind == "more" {
                // A further-truncated continuation within this same resolved
                // batch belongs at the same level as the flat batch's
                // shallowest comments (`stub.depth`).
                moreStub = decodeMoreStub(from: data, parentID: stub.parentID, depth: stub.depth)
                continue
            }
            guard kind == "t1", let comment = decodeComment(from: data) else { continue }
            comments[comment.name] = comment
            order.append(comment.name)
        }

        // Depth (as an offset from `stub.depth`) for a comment in this flat
        // batch is however many parent hops within THIS batch only; a
        // comment whose parent_id is not in `comments` sits at offset 0.
        func relativeDepth(of name: String) -> Int {
            var depth = 0
            var current = name
            var guardCount = 0
            while let comment = comments[current], comments[comment.parentID] != nil, guardCount < 64 {
                current = comment.parentID
                depth += 1
                guardCount += 1
            }
            return depth
        }

        var childrenByParent: [String: [String]] = [:]
        var roots: [String] = []
        for name in order {
            guard let comment = comments[name] else { continue }
            if comments[comment.parentID] != nil {
                childrenByParent[comment.parentID, default: []].append(name)
            } else {
                roots.append(name)
            }
        }

        func makeNode(_ name: String) -> CommentTreeNode? {
            guard let comment = comments[name] else { return nil }
            let children = (childrenByParent[name] ?? []).compactMap { makeNode($0) }
            let depth = stub.depth + relativeDepth(of: name)
            // "Auto collapse replies to top-level comments": the top-level comment
            // stays readable and each reply to it is folded.
            let topLevelAutoCollapse = autoCollapse && depth == 1
            let pinnedAutoCollapse = autoCollapsePinned && comment.stickied
            let autoModeratorAutoCollapse = autoCollapseAutoModerator && comment.author == "AutoModerator"
            return CommentTreeNode(comment: comment, depth: depth, children: children, isCollapsed: topLevelAutoCollapse || pinnedAutoCollapse || autoModeratorAutoCollapse, moreStub: nil)
        }

        let resultRoots = roots.compactMap { makeNode($0) }
        return (resultRoots, moreStub)
    }

    private static func buildLevel(from json: [JSONValue], depth: Int, autoCollapse: Bool, autoCollapsePinned: Bool, autoCollapseAutoModerator: Bool, parentID: String) -> (nodes: [CommentTreeNode], moreStub: MoreStub?) {
        var nodes: [CommentTreeNode] = []
        var levelMoreStub: MoreStub?
        for value in json {
            guard case .object(let thing) = value,
                  case .string(let kind)? = thing["kind"],
                  case .object(let data)? = thing["data"] else { continue }

            if kind == "more" {
                levelMoreStub = decodeMoreStub(from: data, parentID: parentID, depth: depth)
                continue
            }
            guard kind == "t1" else { continue }

            // A comment that won't decode keeps its place (and its
            // replies) as a placeholder, rather than taking its whole
            // subtree with it.
            guard let comment = decodeComment(from: data) ?? placeholderComment(from: data, parentID: parentID) else { continue }

            var children: [CommentTreeNode] = []
            var childMoreStub: MoreStub?
            if case .object(let replies)? = data["replies"],
               case .object(let repliesData)? = replies["data"],
               case .array(let repliesChildren)? = repliesData["children"] {
                let result = buildLevel(from: repliesChildren, depth: depth + 1, autoCollapse: autoCollapse, autoCollapsePinned: autoCollapsePinned, autoCollapseAutoModerator: autoCollapseAutoModerator, parentID: comment.name)
                children = result.nodes
                childMoreStub = result.moreStub
            }

            // "Auto collapse replies to top-level comments": the top-level comment
            // stays readable and each reply to it is folded.
            let topLevelAutoCollapse = autoCollapse && depth == 1
            let pinnedAutoCollapse = autoCollapsePinned && comment.stickied
            // Applies to the AutoModerator comment itself regardless of depth
            // or replies, unlike the two rules above; checks the author
            // directly since not all its comments are stickied.
            let autoModeratorAutoCollapse = autoCollapseAutoModerator && comment.author == "AutoModerator"
            let collapsed = topLevelAutoCollapse || pinnedAutoCollapse || autoModeratorAutoCollapse
            nodes.append(CommentTreeNode(comment: comment, depth: depth, children: children, isCollapsed: collapsed, moreStub: childMoreStub))
        }
        return (nodes, levelMoreStub)
    }

    private static func decodeMoreStub(from raw: [String: JSONValue], parentID: String, depth: Int) -> MoreStub? {
        guard case .string(let id)? = raw["id"] else { return nil }
        let count: Int
        if case .number(let n)? = raw["count"] { count = Int(n) } else { count = 0 }
        var childIDs: [String] = []
        if case .array(let arr)? = raw["children"] {
            childIDs = arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }
        // Reddit has two kinds of `more` object: the familiar kind lists
        // ids and is resolved with `/api/morechildren`; the other
        // (`id: "_"`, `count: 0`, no children) means the thread is deeper
        // than the response's depth limit, and must be re-requested rooted
        // at that comment rather than fetched by id.
        //
        // Apollo renders that case as "Continue thread...".
        guard !childIDs.isEmpty || isContinueThread(id: id, count: count) else { return nil }
        return MoreStub(id: childIDs.isEmpty ? "\(parentID)-continue" : "t1_\(id)",
                        count: count,
                        children: childIDs,
                        parentID: parentID,
                        depth: depth)
    }

    /// Reddit's depth-limit continuation marker: literal id `_`, no
    /// children. `count` is 0 for it.
    private static func isContinueThread(id: String, count: Int) -> Bool {
        id == "_" && count == 0
    }

    /// Stands in for an undecodable comment: same id and place, no text.
    private static func placeholderComment(from raw: [String: JSONValue], parentID: String) -> RedditComment? {
        guard case .string(let id)? = raw["id"] else { return nil }
        let linkID: String
        if case .string(let link)? = raw["link_id"] { linkID = link } else { linkID = parentID }
        let stub: [String: Any] = [
            "id": id, "name": "t1_\(id)", "author": "[unknown]",
            "body": "[This comment couldn't be displayed]",
            "score": 0, "created_utc": 0, "parent_id": parentID, "link_id": linkID,
            "saved": false, "score_hidden": true, "stickied": false,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: stub) else { return nil }
        return try? JSONDecoder.reddit.decode(RedditComment.self, from: data)
    }

    private static func decodeComment(from raw: [String: JSONValue]) -> RedditComment? {
        // Without `replies`: `RedditComment` doesn't read it, and re-serialising
        // every comment's reply subtree would cost O(comments x depth).
        var raw = raw
        raw["replies"] = nil
        let plain = raw.mapValues { $0.plain }
        guard let data = try? JSONSerialization.data(withJSONObject: plain) else { return nil }
        return try? JSONDecoder.reddit.decode(RedditComment.self, from: data)
    }
}

/// Reddit refused a comment: `json.errors[0]` as `[code, message, field]`.
public struct CommentRejectedError: Error, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// Why a comment didn't post, in words (Reborn #1275): Reddit's refusal codes
/// get Reborn's copy, anything else quotes what Reddit said.
public enum CommentSubmitFailure {
    public struct Explanation: Equatable, Sendable {
        public let title: String
        public let message: String

        public init(title: String, message: String) {
            self.title = title
            self.message = message
        }
    }

    public static func explain(_ error: Error) -> Explanation {
        guard let rejected = error as? CommentRejectedError else {
            if let api = error as? RedditAPIError, case .httpError(let status, _) = api, status >= 500 {
                return Explanation(title: "Reddit Had a Hiccup",
                                   message: "Reddit had a problem posting your comment (HTTP \(status)). Try again in a moment.")
            }
            return Explanation(title: "Couldn't Post Comment", message: error.localizedDescription)
        }
        switch rejected.code.uppercased() {
        case "THREAD_LOCKED":
            return Explanation(title: "Comments Locked", message: "This thread is locked, so it can't take new comments.")
        case "TOO_OLD":
            return Explanation(title: "Post Archived", message: "This post is archived, so it can't take new comments.")
        case "DELETED_LINK":
            return Explanation(title: "Post Deleted", message: "This post was deleted, so it can't take new comments.")
        case "DELETED_COMMENT":
            return Explanation(title: "Comment Deleted",
                               message: "The comment you're replying to was deleted, so it can't take replies.")
        case "RATELIMIT":
            return Explanation(title: "Posting Too Often", message: sentence(rejected.message))
        default:
            let said = sentence(rejected.message)
            return Explanation(title: "Comment Rejected",
                               message: said.isEmpty ? "Reddit didn't accept this comment." : "Reddit said: \u{201C}\(said)\u{201D}")
        }
    }

    /// Capitalised and ending in punctuation, as Reborn quotes it.
    static func sentence(_ text: String) -> String {
        var said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = said.first else { return "" }
        said = first.uppercased() + said.dropFirst()
        if !said.hasSuffix("."), !said.hasSuffix("!"), !said.hasSuffix("?") { said += "." }
        return said
    }
}

/// The comment Reddit returns from `/api/comment` with `api_type=json`:
/// `{"json": {"errors": [], "data": {"things": [{"kind": "t1", "data": {…}}]}}}`.
public enum PostedCommentResponse {
    /// With `api_type=json` Reddit reports a refused comment (rate
    /// limit, locked thread, deleted parent) as HTTP 200 with
    /// `json.errors`; this turns that into a thrown error.
    public static func throwIfRejected(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let json = root["json"] as? [String: Any],
              let errors = json["errors"] as? [[Any]], let first = errors.first else { return }
        let code = "\(first.first ?? "")"
        let message = first.count > 1 ? "\(first[1])" : code
        throw CommentRejectedError(code: code, message: message)
    }

    public static func comment(from data: Data) -> RedditComment? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let json = root["json"] as? [String: Any],
              (json["errors"] as? [Any])?.isEmpty ?? true,
              let payload = json["data"] as? [String: Any],
              let things = payload["things"] as? [[String: Any]],
              let first = things.first, first["kind"] as? String == "t1",
              let inner = first["data"],
              let body = try? JSONSerialization.data(withJSONObject: inner) else { return nil }
        return try? JSONDecoder.reddit.decode(RedditComment.self, from: body)
    }
}

/// A `/comments/<id>` response (`[postListing, commentListing]`), parsed
/// into the comment tree plus the post's own comment count.
public struct CommentsResponse: Sendable {
    public let roots: [CommentTreeNode]
    public let moreStub: MoreStub?
    public let postCommentCount: Int?
}

extension CommentTreeBuilder {
    /// Nil when the response isn't the expected two-listing array.
    public static func parseCommentsResponse(
        _ data: Data, postID: String,
        autoCollapse: Bool = false, autoCollapsePinned: Bool = false, autoCollapseAutoModerator: Bool = false
    ) throws -> CommentsResponse? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1,
              let commentsListing = json[1] as? [String: Any],
              let commentsData = commentsListing["data"] as? [String: Any],
              let children = commentsData["children"] as? [Any] else { return nil }
        let childrenData = try JSONSerialization.data(withJSONObject: children)
        let values = try JSONDecoder().decode([JSONValue].self, from: childrenData)
        let built = buildRoots(from: values, postFullname: "t3_\(postID)", autoCollapse: autoCollapse,
                               autoCollapsePinned: autoCollapsePinned, autoCollapseAutoModerator: autoCollapseAutoModerator)
        var count: Int?
        if let postListing = json.first as? [String: Any],
           let postData = postListing["data"] as? [String: Any],
           let postChildren = postData["children"] as? [[String: Any]],
           let first = postChildren.first?["data"] as? [String: Any] {
            count = first["num_comments"] as? Int
        }
        return CommentsResponse(roots: built.roots, moreStub: built.moreStub, postCommentCount: count)
    }

    /// `parseCommentsResponse` off the calling actor: the comment screen
    /// runs on the main actor, and Live re-parses every 10 seconds.
    public static func parseCommentsResponseInBackground(
        _ data: Data, postID: String,
        autoCollapse: Bool = false, autoCollapsePinned: Bool = false, autoCollapseAutoModerator: Bool = false
    ) async throws -> CommentsResponse? {
        try await Task.detached(priority: .userInitiated) {
            try parseCommentsResponse(data, postID: postID, autoCollapse: autoCollapse,
                                      autoCollapsePinned: autoCollapsePinned,
                                      autoCollapseAutoModerator: autoCollapseAutoModerator)
        }.value
    }
}
