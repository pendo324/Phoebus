import Foundation

/// The labels Reddit lets a moderator attach to a user note
/// (`POST /api/mod/notes`).
public enum ModNoteLabel: String, CaseIterable, Sendable {
    case botBan = "BOT_BAN"
    case permaBan = "PERMA_BAN"
    case ban = "BAN"
    case abuseWarning = "ABUSE_WARNING"
    case spamWarning = "SPAM_WARNING"
    case spamWatch = "SPAM_WATCH"
    case solidContributor = "SOLID_CONTRIBUTOR"
    case helpfulUser = "HELPFUL_USER"

    public var title: String {
        switch self {
        case .botBan: return "Bot Ban"
        case .permaBan: return "Permaban"
        case .ban: return "Ban"
        case .abuseWarning: return "Abuse Warning"
        case .spamWarning: return "Spam Warning"
        case .spamWatch: return "Spam Watch"
        case .solidContributor: return "Solid Contributor"
        case .helpfulUser: return "Helpful User"
        }
    }

    /// Reddit's chip colour for the label, as RRGGBB hex: red for bans,
    /// orange for warnings, yellow for a watch, green for good standing.
    public var colorHex: String {
        switch self {
        case .botBan, .permaBan, .ban: return "E5484D"
        case .abuseWarning, .spamWarning: return "F76B15"
        case .spamWatch: return "D9A500"
        case .solidContributor, .helpfulUser: return "30A46C"
        }
    }
}

/// What kind of entry a mod note row is: a hand-written note or one of
/// the moderator actions Reddit records against the user.
public enum ModNoteType: String, CaseIterable, Sendable {
    case note = "NOTE"
    case approval = "APPROVAL"
    case removal = "REMOVAL"
    case ban = "BAN"
    case mute = "MUTE"
    case invite = "INVITE"
    case spam = "SPAM"
    case contentChange = "CONTENT_CHANGE"
    case modAction = "MOD_ACTION"
    /// A type this version doesn't know.
    case unknown = "UNKNOWN"

    public var title: String {
        switch self {
        case .note: return "Note"
        case .approval: return "Approval"
        case .removal: return "Removal"
        case .ban: return "Ban"
        case .mute: return "Mute"
        case .invite: return "Invite"
        case .spam: return "Spam"
        case .contentChange: return "Content Change"
        case .modAction: return "Mod Action"
        case .unknown: return "Other"
        }
    }
}

/// The filter choices on the notes list: everything, or one type.
public enum ModNoteFilter: String, CaseIterable, Sendable {
    case all = "ALL"
    case note = "NOTE"
    case approval = "APPROVAL"
    case removal = "REMOVAL"
    case ban = "BAN"
    case mute = "MUTE"
    case invite = "INVITE"
    case spam = "SPAM"
    case contentChange = "CONTENT_CHANGE"
    case modAction = "MOD_ACTION"

    public var title: String {
        switch self {
        case .all: return "All"
        case .note: return "Notes"
        case .approval: return "Approvals"
        case .removal: return "Removals"
        case .ban: return "Bans"
        case .mute: return "Mutes"
        case .invite: return "Invites"
        case .spam: return "Spam"
        case .contentChange: return "Content Changes"
        case .modAction: return "Mod Actions"
        }
    }
}

/// One entry of a user's mod notes. A hand-written note carries
/// `note`/`label`; an action carries `action`/`details`/`actionDescription`.
public struct ModNote: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let created: Date
    public let type: ModNoteType
    public let subreddit: String
    public let user: String
    /// The moderator who wrote the note or took the action.
    public let `operator`: String
    public let cursor: String?
    public let note: String?
    public let label: ModNoteLabel?
    /// Fullname (`t3_…` or `t1_…`) of the post or comment the entry is about.
    public let redditID: String?
    public let action: String?
    public let details: String?
    public let actionDescription: String?

    enum CodingKeys: String, CodingKey {
        case id, type, subreddit, user, cursor
        case created = "created_at"
        case `operator`
        case userNoteData = "user_note_data"
        case modActionData = "mod_action_data"
    }

    struct UserNoteData: Decodable {
        let note: String?
        let label: String?
        let redditID: String?
        enum CodingKeys: String, CodingKey {
            case note, label
            case redditID = "reddit_id"
        }
    }

    struct ModActionData: Decodable {
        let action: String?
        let redditID: String?
        let details: String?
        let description: String?
        enum CodingKeys: String, CodingKey {
            case action, details, description
            case redditID = "reddit_id"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        created = Date(timeIntervalSince1970: try c.decodeIfPresent(Double.self, forKey: .created) ?? 0)
        type = ModNoteType(rawValue: try c.decodeIfPresent(String.self, forKey: .type) ?? "") ?? .unknown
        subreddit = try c.decodeIfPresent(String.self, forKey: .subreddit) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        `operator` = try c.decodeIfPresent(String.self, forKey: .operator) ?? ""
        cursor = try c.decodeIfPresent(String.self, forKey: .cursor)
        let userData = try? c.decodeIfPresent(UserNoteData.self, forKey: .userNoteData)
        let actionData = try? c.decodeIfPresent(ModActionData.self, forKey: .modActionData)
        note = userData?.note
        label = userData?.label.flatMap(ModNoteLabel.init(rawValue:))
        let linked = [userData?.redditID, actionData?.redditID].compactMap { $0 }.first { !$0.isEmpty }
        redditID = linked
        action = actionData?.action
        details = actionData?.details
        actionDescription = actionData?.description
    }

    /// Reddit only deletes hand-written notes; action rows mirror the mod log.
    public var isDeletable: Bool { type == .note }
}

/// One page of `GET /api/mod/notes`.
public struct ModNotePage: Decodable, Sendable {
    public let notes: [ModNote]
    /// Pass as `before` to fetch the next (older) page.
    public let endCursor: String?
    public let hasNextPage: Bool

    enum CodingKeys: String, CodingKey {
        case notes = "mod_notes"
        case endCursor = "end_cursor"
        case hasNextPage = "has_next_page"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = try c.decodeIfPresent([ModNote].self, forKey: .notes) ?? []
        endCursor = try c.decodeIfPresent(String.self, forKey: .endCursor)
        hasNextPage = try c.decodeIfPresent(Bool.self, forKey: .hasNextPage) ?? false
    }

    /// The cursor for the next page, nil once the last page was reached.
    public var nextCursor: String? { hasNextPage ? endCursor : nil }
}

/// Why a note request can't be made or was refused.
public enum ModNoteError: Error, Equatable, LocalizedError, Sendable {
    case empty
    case tooLong(Int)
    case badTarget
    /// Reddit refused the request: the account's token predates the
    /// `modnote` scope, or the user isn't a moderator with that access.
    case missingScope

    public var errorDescription: String? {
        switch self {
        case .empty: return "Write a note first."
        case .tooLong(let limit): return "Notes are limited to \(limit) characters."
        case .badTarget: return "A note can only be attached to a post or comment."
        case .missingScope: return "Reddit refused mod notes. Moderators need the Posts access permission, and accounts added before mod notes existed must sign in again to grant it."
        }
    }
}

/// Request building for the mod notes endpoints.
public enum ModNoteRequest {
    public static let characterLimit = 250
    public static let pageSize = 25

    public static func listParameters(subreddit: String, user: String, filter: ModNoteFilter = .all,
                                      limit: Int = pageSize, before: String? = nil) -> [String: String] {
        var parameters = ["subreddit": subreddit, "user": user, "limit": String(limit)]
        if filter != .all { parameters["filter"] = filter.rawValue }
        if let before, !before.isEmpty { parameters["before"] = before }
        return parameters
    }

    /// The trimmed note text, or the reason it can't be sent.
    public static func validatedNote(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ModNoteError.empty }
        if trimmed.count > characterLimit { throw ModNoteError.tooLong(characterLimit) }
        return trimmed
    }

    public static func createParameters(subreddit: String, user: String, note: String,
                                        label: ModNoteLabel?, redditID: String? = nil) throws -> [String: String] {
        var parameters = ["subreddit": subreddit, "user": user, "note": try validatedNote(note)]
        if let label { parameters["label"] = label.rawValue }
        if let redditID, !redditID.isEmpty {
            guard redditID.hasPrefix("t1_") || redditID.hasPrefix("t3_") else { throw ModNoteError.badTarget }
            parameters["reddit_id"] = redditID
        }
        return parameters
    }

    public static func deleteParameters(subreddit: String, user: String, noteID: String) -> [String: String] {
        ["subreddit": subreddit, "user": user, "note_id": noteID]
    }

    /// The note in a create response (`{"created": {…}}`).
    public static func decodeCreated(_ data: Data) -> ModNote? {
        struct Envelope: Decodable { let created: ModNote? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.created
    }
}
