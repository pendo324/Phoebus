import Foundation

/// Phoebus-only "Local Saved" (not in Apollo or Reborn): every save made
/// in the app keeps a small local snapshot, so an item Reddit later drops
/// from the Saved listing (removed or deleted) can still be found under
/// "Kept Locally".
public struct LocalSavedRecord: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case post, comment
    }

    /// `onReddit` until a complete Saved listing no longer has it.
    public enum State: String, Codable, Sendable {
        case onReddit, keptLocally
    }

    public var id: String { fullname }
    public var fullname: String
    public var kind: Kind
    /// The post's title; for a comment, the title of the post it is on.
    public var title: String
    /// The start of the post's text or the comment's body.
    public var snippet: String
    public var subreddit: String
    public var author: String
    public var permalink: String
    /// The thread's bare id: the post's own, or the comment's post.
    public var postID: String
    /// A link post's destination and thumbnail.
    public var url: String?
    public var thumbnail: String?
    public var created: Date
    public var savedAt: Date
    public var state: State
    /// When a reconcile first found it missing from Saved.
    public var missingSince: Date?

    public static let snippetLength = 300

    public init(fullname: String, kind: Kind, title: String, snippet: String, subreddit: String,
                author: String, permalink: String, postID: String, url: String? = nil,
                thumbnail: String? = nil, created: Date, savedAt: Date = Date(),
                state: State = .onReddit, missingSince: Date? = nil) {
        self.fullname = fullname
        self.kind = kind
        self.title = title
        self.snippet = String(snippet.prefix(Self.snippetLength))
        self.subreddit = subreddit
        self.author = author
        self.permalink = permalink
        self.postID = postID
        self.url = url
        self.thumbnail = thumbnail
        self.created = created
        self.savedAt = savedAt
        self.state = state
        self.missingSince = missingSince
    }

    public init(post: RedditPost, savedAt: Date = Date()) {
        let thumbnail = post.thumbnail.flatMap { $0.hasPrefix("http") ? $0 : nil }
        self.init(fullname: post.name, kind: .post, title: post.title, snippet: post.selftext ?? "",
                  subreddit: post.subreddit, author: post.author, permalink: post.permalink, postID: post.id,
                  url: post.isSelf ? nil : post.url, thumbnail: thumbnail, created: post.created, savedAt: savedAt)
    }

    public init(comment: RedditComment, savedAt: Date = Date()) {
        let postID = comment.linkID.hasPrefix("t3_") ? String(comment.linkID.dropFirst(3)) : comment.linkID
        let subreddit = comment.subreddit ?? ""
        let permalink = subreddit.isEmpty ? comment.permalinkPath
            : "/r/\(subreddit)/comments/\(postID)/_/\(comment.id)/"
        self.init(fullname: comment.name, kind: .comment, title: comment.linkTitle ?? "", snippet: comment.body,
                  subreddit: subreddit, author: comment.author, permalink: permalink, postID: postID,
                  created: comment.created, savedAt: savedAt)
    }

    /// A snapshot of a post or comment; nil for an item known only by
    /// fullname (an inbox reply), which has nothing to keep.
    public static func snapshot(of item: some Votable, savedAt: Date = Date()) -> LocalSavedRecord? {
        if let post = item as? RedditPost { return LocalSavedRecord(post: post, savedAt: savedAt) }
        if let comment = item as? RedditComment { return LocalSavedRecord(comment: comment, savedAt: savedAt) }
        return nil
    }

    /// The comment's bare id, for the archive and the focused thread.
    public var commentID: String? {
        kind == .comment ? String(fullname.dropFirst(3)) : nil
    }
}

/// How a kept item looks on Reddit now, for its badge.
public enum LocalSavedLiveStatus: Equatable, Sendable {
    case removed, deleted
    /// Reddit returned nothing for it.
    case unavailable
    /// Intact but no longer saved, e.g. unsaved on another device.
    case notInSaved

    public var label: String {
        switch self {
        case .removed: return "Removed"
        case .deleted: return "Deleted"
        case .unavailable: return "Unavailable"
        case .notInSaved: return "Not in Saved"
        }
    }

    /// Classifies Reddit's current copy (`/api/info`), nil when it has none.
    public static func classify(_ live: ProfileItem?) -> LocalSavedLiveStatus {
        switch live {
        case nil:
            return .unavailable
        case .post(let post):
            guard RemovedPostClassifier.isRemoved(post) else { return .notInSaved }
            return RemovedPostClassifier.reason(for: post) == .userDeleted ? .deleted : .removed
        case .comment(let comment):
            guard DeletedCommentsClassifier.bodyLooksDeletedOrRemoved(comment.body)
                    || RemovedPostClassifier.isPlaceholder(comment.author) else { return .notInSaved }
            return DeletedCommentsClassifier.bodyLooksUserDeleted(comment.body) ? .deleted : .removed
        }
    }

    /// Whether the live body is gone, so the archive is worth asking.
    public var bodyIsGone: Bool { self == .removed || self == .deleted }
}

/// The pure rules for keeping and reconciling records.
public enum LocalSavedPolicy {
    /// Reddit's listings stop after this many items, so a listing that
    /// long can end with older saves still unseen.
    public static let listingCeiling = 1000

    /// Whether a walk of Saved can show that a record is gone: Reddit said
    /// there are no more pages and the listing is under its ceiling.
    public static func isListingComplete(after: String?, itemCount: Int) -> Bool {
        (after ?? "").isEmpty && itemCount < listingCeiling
    }

    /// Records a fresh save at the front, replacing an older snapshot of
    /// the same item, then trims to `cap`: oldest records still on Reddit
    /// go first, since Reddit holds them anyway.
    public static func inserting(_ record: LocalSavedRecord, into records: [LocalSavedRecord],
                                 cap: Int) -> [LocalSavedRecord] {
        var result = records.filter { $0.fullname != record.fullname }
        result.insert(record, at: 0)
        while result.count > cap {
            if let index = result.lastIndex(where: { $0.state == .onReddit }) {
                result.remove(at: index)
            } else {
                result.removeLast()
            }
        }
        return result
    }

    /// Compares records with the fullnames Saved returned. Present ones are
    /// on Reddit (again); absent ones are kept locally, but only when the
    /// listing is complete and they were saved before it was fetched (a
    /// save made meanwhile may not be listed yet). Otherwise unchanged.
    public static func reconcile(_ records: [LocalSavedRecord], present: Set<String>, listingComplete: Bool,
                                 listingStartedAt: Date, now: Date = Date()) -> [LocalSavedRecord] {
        records.map { record in
            var record = record
            if present.contains(record.fullname) {
                record.state = .onReddit
                record.missingSince = nil
            } else if listingComplete, record.savedAt < listingStartedAt {
                record.state = .keptLocally
                record.missingSince = record.missingSince ?? now
            }
            return record
        }
    }

    /// The "Kept Locally" list, newest save first.
    public static func keptLocally(_ records: [LocalSavedRecord]) -> [LocalSavedRecord] {
        records.filter { $0.state == .keptLocally }.sorted { $0.savedAt > $1.savedAt }
    }
}

/// Backs "Keep Local Copies of Saved Items".
public struct LocalSavedSettings: Codable, Sendable, Equatable {
    public var keepLocalCopies: Bool

    public static let `default` = LocalSavedSettings(keepLocalCopies: true)

    public init(keepLocalCopies: Bool) {
        self.keepLocalCopies = keepLocalCopies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keepLocalCopies = (try? container.decodeIfPresent(Bool.self, forKey: .keepLocalCopies)) ?? true
    }
}

/// Apollo never had this setting, so the key is Phoebus's own.
public enum LocalSavedSettingsStore {
    private static let key = "com.pendo324.Phoebus.localSavedSettings"

    public static let storage = SettingsStore<LocalSavedSettings>(key: key) { LocalSavedSettings.default }

    public static func load() -> LocalSavedSettings { storage.load() }

    public static func save(_ settings: LocalSavedSettings) { storage.save(settings) }
}

extension LocalSavedSettings: StoredSettingsModel {
    public static var store: SettingsStore<LocalSavedSettings> { LocalSavedSettingsStore.storage }
}

/// The records, one JSON list per account in defaults, so the settings
/// backup (which snapshots the app's defaults keys) carries them. Capped,
/// since a record is a few hundred bytes.
public enum LocalSavedStore {
    public static let cap = 2000
    static let keyPrefix = "com.pendo324.Phoebus.localSaved."

    public static func key(account: String) -> String {
        keyPrefix + account.lowercased()
    }

    /// The signed-in account, or nil when signed out (nothing is kept).
    public static var currentAccount: String? {
        FavoriteSubredditsAccountContext.currentUsernameProvider().flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func load(account: String, defaults: UserDefaults = .standard) -> [LocalSavedRecord] {
        guard let data = defaults.data(forKey: key(account: account)),
              let records = try? JSONDecoder().decode([LocalSavedRecord].self, from: data) else { return [] }
        return records
    }

    public static func save(_ records: [LocalSavedRecord], account: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key(account: account))
        NotificationCenter.default.post(name: .localSavedChanged, object: nil)
    }

    public static func record(_ record: LocalSavedRecord, account: String, defaults: UserDefaults = .standard) {
        save(LocalSavedPolicy.inserting(record, into: load(account: account, defaults: defaults), cap: cap),
             account: account, defaults: defaults)
    }

    public static func remove(fullname: String, account: String, defaults: UserDefaults = .standard) {
        let records = load(account: account, defaults: defaults)
        guard records.contains(where: { $0.fullname == fullname }) else { return }
        save(records.filter { $0.fullname != fullname }, account: account, defaults: defaults)
    }

    @discardableResult
    public static func reconcile(present: Set<String>, listingComplete: Bool, listingStartedAt: Date,
                                 account: String, defaults: UserDefaults = .standard) -> [LocalSavedRecord] {
        let records = load(account: account, defaults: defaults)
        let reconciled = LocalSavedPolicy.reconcile(records, present: present, listingComplete: listingComplete,
                                                    listingStartedAt: listingStartedAt)
        if reconciled != records { save(reconciled, account: account, defaults: defaults) }
        return reconciled
    }

    public static func keptLocally(account: String, defaults: UserDefaults = .standard) -> [LocalSavedRecord] {
        LocalSavedPolicy.keptLocally(load(account: account, defaults: defaults))
    }
}

public extension Notification.Name {
    static let localSavedChanged = Notification.Name("PhoebusLocalSavedChanged")
}

extension RedditListing {
    /// Every child's fullname, including ones the typed models can't decode.
    public var fullnames: [String] {
        data.children.compactMap { child in
            if case .string(let name)? = child.data.raw["name"], !name.isEmpty { return name }
            return nil
        }
    }
}
