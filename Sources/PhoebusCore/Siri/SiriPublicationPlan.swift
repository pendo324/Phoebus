import Foundation

/// Reborn "Siri & Spotlight" (#1299): what Core Spotlight is known to hold,
/// id to content signature, per account. Persisted so a relaunch neither
/// wipes and rebuilds the whole index nor republishes unchanged entities.
/// Written only after the index calls succeed; a stale checkpoint only
/// causes an idempotent re-upsert or delete.
public struct SiriPublishCheckpoint: Codable, Sendable, Equatable {
    public var account: String?
    public var posts: [String: String]
    public var subreddits: [String: String]

    public init(account: String?, posts: [String: String] = [:], subreddits: [String: String] = [:]) {
        self.account = account
        self.posts = posts
        self.subreddits = subreddits
    }

    /// 32-byte digest committed atomically with each Spotlight batch
    /// (CoreSpotlight's client-state contract; the limit is 250 bytes).
    public var clientState: Data {
        var material = Data((account ?? "-").utf8)
        for map in [posts, subreddits] {
            for key in map.keys.sorted() { material.append(Data("\(key)=\(map[key] ?? "")\n".utf8)) }
            material.append(0)
        }
        return Data(SHA256Digest.hash(material))
    }
}

/// The next incremental Spotlight publication: which records to upsert, which
/// ids to delete, and the checkpoint to save once it lands.
public struct SiriPublicationPlan: Sendable, Equatable {
    public let reset: Bool
    public let changedPosts: [SiriContentRecord]
    public let changedSubreddits: [SiriContentRecord]
    public let removedPostIDs: [String]
    public let removedSubredditIDs: [String]
    public let previous: SiriPublishCheckpoint
    public let next: SiriPublishCheckpoint

    /// Nothing to publish.
    public var isEmpty: Bool {
        !reset && changedPosts.isEmpty && changedSubreddits.isEmpty
            && removedPostIDs.isEmpty && removedSubredditIDs.isEmpty
    }

    /// Changes whenever indexed text changes. The week bucket re-upserts a
    /// still-observed record at most weekly so its Spotlight expiry keeps
    /// pace with catalogue retention, without republishing on every scroll.
    public static func signature(_ record: SiriContentRecord) -> String {
        let week = Int(record.observedAt.timeIntervalSince1970 / (7 * 24 * 60 * 60))
        let content = [record.title, record.text, record.author, record.subreddit, record.displayTitle ?? "",
                       record.score.map(String.init) ?? "", record.commentCount.map(String.init) ?? "",
                       record.linkDomain ?? "", String(week)]
            .joined(separator: "\u{1F}")
        return String(SHA256Digest.hex(Data(content.utf8)).prefix(24))
    }

    /// `account` is nil when indexing is off or nobody is signed in, which
    /// plans the removal of everything held. A different account, a missing
    /// checkpoint or `forceReset` rebuild from nothing.
    public static func make(checkpoint: SiriPublishCheckpoint?, account: String?, forceReset: Bool,
                            posts: [SiriContentRecord], subreddits: [SiriContentRecord]) -> SiriPublicationPlan {
        let reset = forceReset || checkpoint == nil || checkpoint?.account != account
        let previous = reset ? SiriPublishCheckpoint(account: account) : checkpoint ?? SiriPublishCheckpoint(account: account)
        let postSigs = Dictionary(posts.map { ($0.id, signature($0)) }, uniquingKeysWith: { first, _ in first })
        let subSigs = Dictionary(subreddits.map { ($0.id, signature($0)) }, uniquingKeysWith: { first, _ in first })
        return SiriPublicationPlan(
            reset: reset,
            changedPosts: posts.filter { previous.posts[$0.id] != postSigs[$0.id] },
            changedSubreddits: subreddits.filter { previous.subreddits[$0.id] != subSigs[$0.id] },
            removedPostIDs: previous.posts.keys.filter { postSigs[$0] == nil }.sorted(),
            removedSubredditIDs: previous.subreddits.keys.filter { subSigs[$0] == nil }.sorted(),
            previous: previous,
            next: SiriPublishCheckpoint(account: account, posts: postSigs, subreddits: subSigs))
    }
}
