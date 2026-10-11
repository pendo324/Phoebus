import Foundation

/// Recognises the text Reddit puts in place of removed content: the bare
/// `[removed]`/`[deleted]`, and the "[ Removed by moderator ]" /
/// "[ Removed by Reddit ... ]" sentences left on a removal with a reason
/// or an admin takedown.
public enum RemovedPostClassifier {
    public static func isPlaceholder(_ text: String?) -> Bool {
        guard let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("[") else { return false }
        return trimmed == "[removed]" || trimmed == "[deleted]"
            || trimmed.hasPrefix("[ removed by reddit") || trimmed.hasPrefix("[ removed by moderator")
    }

    /// True when Reddit serves the post scrubbed: a placeholder title or
    /// body, a `removed_by_category`, or a deleted author.
    public static func isRemoved(title: String, selftext: String?, author: String, removedByCategory: String?) -> Bool {
        isPlaceholder(title) || isPlaceholder(selftext) || isPlaceholder(author)
            || !(removedByCategory ?? "").isEmpty
    }

    public static func isRemoved(_ post: RedditPost) -> Bool {
        isRemoved(title: post.title, selftext: post.selftext, author: post.author, removedByCategory: post.removedByCategory)
    }

    /// Deleted by its author (a "[deleted]" body or author, or Reddit's
    /// `deleted`/`author` category); anything else is a removal.
    public static func reason(selftext: String?, author: String, removedByCategory: String?) -> DeletedCommentReason {
        if let category = removedByCategory, !category.isEmpty {
            return category == "deleted" || category == "author" ? .userDeleted : .moderatorRemoved
        }
        let body = selftext?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return body == "[deleted]" || author == "[deleted]" ? .userDeleted : .moderatorRemoved
    }

    public static func reason(for post: RedditPost) -> DeletedCommentReason {
        reason(selftext: post.selftext, author: post.author, removedByCategory: post.removedByCategory)
    }
}

/// A removed post's archived copy from Arctic Shift's `api/posts/ids`.
/// Placeholder values are dropped, so every field present is original
/// content. Phoebus-only "Recover Removed Posts" (not in Apollo or Reborn).
public struct ArchivedPost: Sendable, Equatable {
    public let id: String
    public let title: String?
    public let body: String?
    /// A link post's destination; nil for a self post, or when the archived
    /// URL only points back at this post.
    public let url: URL?
    public let author: String?

    public init(id: String, title: String?, body: String?, url: URL?, author: String?) {
        self.id = id
        self.title = title
        self.body = body
        self.url = url
        self.author = author
    }

    /// Nil when the record holds nothing to give back (it was archived
    /// after Reddit had already scrubbed it).
    init?(archive raw: [String: Any], postID: String) {
        func text(_ key: String) -> String? {
            guard let value = raw[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !RemovedPostClassifier.isPlaceholder(value) else { return nil }
            return value
        }
        let id = (raw["id"] as? String) ?? postID
        guard id == postID else { return nil }
        let isSelf = (raw["is_self"] as? Bool) ?? false
        var body = text("selftext")
        var url: URL?
        if !isSelf {
            // A link post whose body is only its link reads as a link post.
            if let link = Self.soleLink(in: body) {
                url = link
                body = nil
            } else if let raw = text("url"), let candidate = URL(string: raw.replacingOccurrences(of: "&amp;", with: "&")),
                      let scheme = candidate.scheme?.lowercased(), scheme == "http" || scheme == "https",
                      !Self.pointsBack(candidate, at: postID) {
                url = candidate
            }
        }
        let title = text("title")
        guard title != nil || body != nil || url != nil else { return nil }
        self.init(id: postID, title: title, body: body, url: url, author: text("author"))
    }

    /// Reddit rewrites a removed post's URL to its own permalink or gallery
    /// page; neither is a destination worth recovering.
    static func pointsBack(_ url: URL, at postID: String) -> Bool {
        let segments = url.pathComponents
        for index in segments.indices.dropLast() where segments[index] == "comments" || segments[index] == "gallery" {
            if segments[index + 1] == postID { return true }
        }
        return false
    }

    /// The URL when `body` is exactly one bare URL or one `[text](url)` link.
    static func soleLink(in body: String?) -> URL? {
        guard let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let whole = NSRange(trimmed.startIndex..., in: trimmed)
        for pattern in [#"^\[[^\]]*\]\((https?://[^)\s]+)\)$"#, #"^(https?://\S+)$"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: whole),
                  let range = Range(match.range(at: 1), in: trimmed) else { continue }
            return URL(string: String(trimmed[range]))
        }
        return nil
    }
}

/// What a recovered post adds to what Reddit still shows: only the fields
/// that differ, so an archive copy matching the live post shows nothing.
public struct RecoveredPostDisplay: Sendable, Equatable {
    public let title: String?
    public let body: String?
    public let url: URL?
    public let author: String?

    public init?(archived: ArchivedPost, liveTitle: String, liveBody: String?, liveURL: String?, liveAuthor: String) {
        func differs(_ archived: String?, _ live: String?) -> String? {
            guard let archived else { return nil }
            let a = archived.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = (live ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return a == b ? nil : archived
        }
        title = differs(archived.title, liveTitle)
        body = differs(archived.body, liveBody)
        url = archived.url.flatMap { differs($0.absoluteString, liveURL) == nil ? nil : $0 }
        author = differs(archived.author, liveAuthor)
        guard title != nil || body != nil || url != nil || author != nil else { return nil }
    }

    public init?(archived: ArchivedPost, live post: RedditPost) {
        self.init(archived: archived, liveTitle: post.title, liveBody: post.selftext, liveURL: post.url, liveAuthor: post.author)
    }
}

/// When post detail recovers a removed post, following the Deleted
/// Comments mode: Always fetches on open, Passive offers a "Show Original
/// Post" row, Off does nothing.
public enum RemovedPostRecoveryTrigger: Sendable, Equatable {
    case none
    case automatic
    case onTap

    public init(mode: DeletedCommentsMode) {
        switch mode {
        case .off: self = .none
        case .alwaysShow: self = .automatic
        case .passive: self = .onTap
        }
    }
}

/// Session cache of `api/posts/ids` answers, including "not archived".
final class ArchivedPostCache: @unchecked Sendable {
    static let shared = ArchivedPostCache()

    struct Entry { let post: ArchivedPost? }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func value(for id: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[id]
    }

    func store(_ post: ArchivedPost?, for id: String) {
        lock.lock(); defer { lock.unlock() }
        entries[id] = Entry(post: post)
    }
}
