import Foundation

/// Reborn's Deleted Comments feature: recovers removed/deleted comment
/// bodies from an archive. The mode is a Off / Always Show / Passive
/// (Per-Thread) picker plus a "Tap to Show Deleted Comments" sub-toggle
/// shown only in Always mode.
///
/// Reborn persists the mode as two booleans, so `DeletedCommentsMode`
/// maps onto them and settings backups round-trip unchanged:
///   Off     -> ShowDeletedComments = NO,  PassiveDeletedComments = NO
///   Always  -> ShowDeletedComments = YES, PassiveDeletedComments = NO
///   Passive -> ShowDeletedComments = NO,  PassiveDeletedComments = YES
public enum DeletedCommentsMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case alwaysShow
    case passive

    public var id: String { rawValue }

    /// Picker titles as Reborn words them.
    public var title: String {
        switch self {
        case .off: return "Off"
        case .alwaysShow: return "Always Show"
        case .passive: return "Passive (Per-Thread)"
        }
    }
}

/// Backs `UDKeyShowDeletedComments`, `UDKeyPassiveDeletedComments` and
/// `UDKeyTapToRevealDeletedComments`.
public struct DeletedCommentsSettings: Codable, Sendable, Equatable {
    public var mode: DeletedCommentsMode
    /// `UDKeyTapToRevealDeletedComments`; only shown in `.alwaysShow` mode.
    public var tapToReveal: Bool

    public static let `default` = DeletedCommentsSettings(mode: .off, tapToReveal: false)

    public init(mode: DeletedCommentsMode, tapToReveal: Bool) {
        self.mode = mode
        self.tapToReveal = tapToReveal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? container.decodeIfPresent(DeletedCommentsMode.self, forKey: .mode)) ?? .off
        tapToReveal = (try? container.decodeIfPresent(Bool.self, forKey: .tapToReveal)) ?? false
    }
}

/// Classifies a body as deleted/removed by exact match against Reddit's
/// placeholder strings; the API never sends a truly empty body for these.
public enum DeletedCommentsClassifier {
    private static let exactMatches: Set<String> = [
        "[deleted]", "[removed]", "deleted", "removed",
        "removed by moderator", "removed by mod", "removed by reddit",
        "comment removed by moderator", "comment removed by reddit",
        "user deleted comment :(", "user deleted comment",
    ]

    /// True when `body` is Reddit's own deleted/removed placeholder rather
    /// than real content; triggers archive recovery.
    public static func bodyLooksDeletedOrRemoved(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        return exactMatches.contains(trimmed)
    }

    /// Reborn's `ReasonForCurrentBody`: Reddit's own placeholder says
    /// "[deleted]" (or "user deleted comment") only when the author
    /// deleted it; anything else is a removal.
    public static func bodyLooksUserDeleted(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "[deleted]" || trimmed == "deleted" || trimmed.contains("user deleted comment")
    }
}

/// User-deleted vs. moderator-removed; drives the tap-to-reveal chip label.
public enum DeletedCommentReason: String, Sendable, Equatable {
    case userDeleted
    case moderatorRemoved

    /// Chip text as Reborn words it.
    public var displayLabel: String {
        switch self {
        case .userDeleted: return "DELETED BY USER"
        case .moderatorRemoved: return "REMOVED BY MOD"
        }
    }
}

/// One archived comment recovered from the Arctic Shift community
/// archive (see `ArcticShiftClient`).
extension ArchivedComment {
    /// The same archived comment with its reason taken from Reddit's
    /// current body, which Reborn prefers over the archive's
    /// `removal_type`: a "[deleted]" body means the user deleted it.
    public func classified(byCurrentBody body: String) -> ArchivedComment {
        let reason: DeletedCommentReason = DeletedCommentsClassifier.bodyLooksUserDeleted(body) ? .userDeleted : self.reason
        return ArchivedComment(fullname: fullname, author: author, body: self.body, score: score, reason: reason)
    }
}

public struct ArchivedComment: Sendable, Equatable {
    public let fullname: String
    public let author: String?
    public let body: String
    public let score: Int?
    public let reason: DeletedCommentReason

    public init(fullname: String, author: String?, body: String, score: Int?, reason: DeletedCommentReason) {
        self.fullname = fullname
        self.author = author
        self.body = body
        self.score = score
        self.reason = reason
    }
}

public enum DeletedCommentsSettingsStore {
    private static let key = "com.pendo324.Phoebus.deletedCommentsSettings"

    public static let storage = SettingsStore<DeletedCommentsSettings>(key: key) { DeletedCommentsSettings.default }

    public static func load() -> DeletedCommentsSettings { storage.load() }

    public static func save(_ settings: DeletedCommentsSettings) { storage.save(settings) }
}

extension DeletedCommentsSettings: StoredSettingsModel {
    public static var store: SettingsStore<DeletedCommentsSettings> { DeletedCommentsSettingsStore.storage }
}
