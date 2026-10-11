import Foundation

/// One named comment filter (Settings → Filters & Blocks → Comment Filters):
/// a score range, words and users to exclude, and whether a match hides the
/// comment or starts it collapsed. Apollo and Reborn have no comment filters;
/// this is Phoebus's own.
public struct CommentFilter: Codable, Sendable, Equatable, Identifiable {
    public enum DisplayMode: String, Codable, Sendable, CaseIterable {
        /// Removes the comment and every reply under it.
        case hide
        /// Starts the comment collapsed with a "Filtered: ..." line.
        case collapse

        public var displayName: String {
            switch self {
            case .hide: return "Hide"
            case .collapse: return "Collapse"
            }
        }
    }

    public var id: UUID
    public var name: String
    /// Comments scoring below this are filtered. Nil for no minimum.
    public var minScore: Int?
    /// Comments scoring above this are filtered. Nil for no maximum.
    public var maxScore: Int?
    /// Matched case-insensitively anywhere in the comment's body, so "spoil"
    /// also catches "spoiler".
    public var excludedWords: [String]
    /// Usernames without `u/`, matched case-insensitively.
    public var excludedUsers: [String]
    public var displayMode: DisplayMode
    /// Subreddit names without `r/`. Empty means every subreddit.
    public var subreddits: [String]

    public init(id: UUID = UUID(), name: String = "", minScore: Int? = nil, maxScore: Int? = nil,
                excludedWords: [String] = [], excludedUsers: [String] = [],
                displayMode: DisplayMode = .collapse, subreddits: [String] = []) {
        self.id = id
        self.name = name
        self.minScore = minScore
        self.maxScore = maxScore
        self.excludedWords = excludedWords
        self.excludedUsers = excludedUsers
        self.displayMode = displayMode
        self.subreddits = subreddits
    }

    enum CodingKeys: String, CodingKey {
        case id, name, minScore, maxScore, excludedWords, excludedUsers, displayMode, subreddits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        minScore = try? c.decodeIfPresent(Int.self, forKey: .minScore)
        maxScore = try? c.decodeIfPresent(Int.self, forKey: .maxScore)
        excludedWords = (try? c.decodeIfPresent([String].self, forKey: .excludedWords)) ?? []
        excludedUsers = (try? c.decodeIfPresent([String].self, forKey: .excludedUsers)) ?? []
        displayMode = (try? c.decodeIfPresent(DisplayMode.self, forKey: .displayMode)) ?? .collapse
        subreddits = (try? c.decodeIfPresent([String].self, forKey: .subreddits)) ?? []
    }

    /// Whether the filter is in force in `subreddit`.
    public func applies(in subreddit: String) -> Bool {
        subreddits.isEmpty || subreddits.contains { $0.caseInsensitiveCompare(subreddit) == .orderedSame }
    }

    /// Why `comment` matches, as the collapsed row's reason line, or nil.
    /// Score bounds skip comments whose score Reddit hides, and pinned
    /// (stickied) comments, which sit at the top whatever their votes.
    public func matchReason(for comment: RedditComment) -> String? {
        if !comment.scoreHidden, !comment.stickied {
            if let minScore, comment.score < minScore { return "Filtered: score below \(minScore)" }
            if let maxScore, comment.score > maxScore { return "Filtered: score above \(maxScore)" }
        }
        let body = comment.body.lowercased()
        for word in excludedWords {
            let needle = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !needle.isEmpty, body.contains(needle) { return "Filtered: contains \u{201c}\(needle)\u{201d}" }
        }
        for user in excludedUsers {
            let name = Self.normalizedUsername(user)
            if !name.isEmpty, name.caseInsensitiveCompare(comment.author) == .orderedSame { return "Filtered: u/\(comment.author)" }
        }
        return nil
    }

    /// Trims and drops a leading `u/` or `/u/`.
    public static func normalizedUsername(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/") { value.removeFirst() }
        if value.lowercased().hasPrefix("u/") { value.removeFirst(2) }
        return value
    }

    /// Trims, lowercases and drops a leading `r/` or `/r/`.
    public static func normalizedSubreddit(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("/") { value.removeFirst() }
        if value.hasPrefix("r/") { value.removeFirst(2) }
        return value
    }
}

/// The comment filters, as one JSON array. Phoebus-only, so the key is ours;
/// its prefix puts it in settings backups.
public enum CommentFilterStore {
    public static let storage = SettingsStore<[CommentFilter]>(
        key: "com.pendo324.Phoebus.commentFilters") { [] }

    public static func load() -> [CommentFilter] { storage.load() }

    public static func save(_ filters: [CommentFilter]) { storage.save(filters) }
}

public enum CommentFilterVerdict: Equatable, Sendable {
    case show
    case collapse(reason: String)
    case hide
}

/// Decides what the comment filters do to one comment.
public enum CommentFilterPolicy {
    /// Your own comments and the comment a link pointed at are never filtered.
    /// When several filters match, Hide wins over Collapse, and the reason is
    /// the first collapsing filter's.
    public static func verdict(for comment: RedditComment, subreddit: String, ownUsername: String?,
                               focusedCommentID: String?, filters: [CommentFilter]) -> CommentFilterVerdict {
        if let ownUsername, !ownUsername.isEmpty,
           ownUsername.caseInsensitiveCompare(comment.author) == .orderedSame { return .show }
        if let focusedCommentID, focusedCommentID == comment.id || focusedCommentID == comment.name { return .show }
        var collapseReason: String?
        for filter in filters where filter.applies(in: subreddit) {
            guard let reason = filter.matchReason(for: comment) else { continue }
            if filter.displayMode == .hide { return .hide }
            if collapseReason == nil { collapseReason = reason }
        }
        return collapseReason.map { .collapse(reason: $0) } ?? .show
    }
}

public extension Array where Element == CommentTreeNode {
    /// Applies the comment filters: a hidden comment goes with its replies, a
    /// collapsed one starts collapsed carrying its reason. A linked comment's
    /// ancestors are kept too, or hiding one would take the linked comment
    /// with it.
    func applyingCommentFilters(_ filters: [CommentFilter], subreddit: String, ownUsername: String?,
                                focusedCommentID: String?) -> [CommentTreeNode] {
        let active = filters.filter { $0.applies(in: subreddit) }
        guard !active.isEmpty else { return self }
        func apply(_ node: CommentTreeNode) -> CommentTreeNode? {
            var copy = node
            let leadsToFocus = focusedCommentID.map { node.contains(id: $0) } ?? false
            let verdict = leadsToFocus ? .show : CommentFilterPolicy.verdict(
                for: node.comment, subreddit: subreddit, ownUsername: ownUsername,
                focusedCommentID: focusedCommentID, filters: active)
            switch verdict {
            case .hide:
                return nil
            case .collapse(let reason):
                copy.isCollapsed = true
                copy.filterReason = reason
            case .show:
                break
            }
            copy.children = node.children.compactMap(apply)
            return copy
        }
        return compactMap(apply)
    }
}
