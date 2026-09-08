import Foundation

/// Apollo's modmail inbox has 5 tabs, each with its own empty-state
/// string, rather than a single flat conversation list.
public enum ModmailInboxTab: Int, CaseIterable, Sendable, Identifiable {
    case notifications, modDiscussions, highlighted, archived, inProgress

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .modDiscussions: return "Mod Discussions"
        case .highlighted: return "Highlighted"
        case .archived: return "Archived"
        case .inProgress: return "In Progress"
        }
    }

    /// Per-tab empty-state strings.
    public var emptyStateText: String {
        switch self {
        case .notifications: return "No notification messages"
        case .modDiscussions: return "No mod discussions"
        case .highlighted: return "No highlighted messages"
        case .archived: return "No archived messages"
        case .inProgress: return "No in progress messages"
        }
    }

    /// The `/api/mod/conversations` `state` query value backing this tab.
    /// "Mod Discussions" (moderator-only chatter) maps to `mod`; "In Progress"
    /// maps to `inprogress`.
    public var apiState: String {
        switch self {
        case .notifications: return "notifications"
        case .modDiscussions: return "mod"
        case .highlighted: return "highlighted"
        case .archived: return "archived"
        case .inProgress: return "inprogress"
        }
    }
}


/// Apollo's modmail sort orders: relevance, user, mod, unread, recent.
public enum ModmailSortOption: String, CaseIterable, Sendable, Identifiable {
    case recent, unread, mod, user, relevance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recent: return "Most Recent"
        case .unread: return "Unread"
        case .mod: return "Mod"
        case .user: return "User"
        case .relevance: return "Relevance"
        }
    }

    /// Apollo's per-sort icon name.
    public var apolloIconName: String {
        switch self {
        case .recent: return "option-sort-new"
        case .unread: return "option-sort-unread"
        case .mod: return "option-moderator"
        case .user: return "option-author"
        case .relevance: return "option-sort-relevance"
        }
    }

    /// The GraphQL `sort` value. `RELEVANCE` is search-only in Reddit's own
    /// client, so it falls back to `RECENT` for a plain mailbox listing.
    public var graphQLValue: String {
        switch self {
        case .recent, .relevance: return "RECENT"
        case .unread: return "UNREAD"
        case .mod: return "MOD"
        case .user: return "USER"
        }
    }
    /// The OAuth API's `sort` (`recent`, `mod`, `reply`, `unread`).
    public var restValue: String {
        switch self {
        case .recent, .relevance: return "recent"
        case .unread: return "unread"
        case .mod: return "mod"
        case .user: return "reply"
        }
    }
}

/// A moderator-mail thread, distinct from regular private messages.
public struct ModmailConversation: Decodable, Sendable, Identifiable {
    public let id: String
    public let subject: String
    public let lastUpdated: String?
    public let isAuto: Bool
    public let numMessages: Int
    public let state: Int
    /// The subreddit this conversation belongs to, matching Apollo's
    /// subreddit-selector filter; Reddit nests this under an `owner`
    /// object.
    public let subredditName: String?
    /// Drives the highlight/unhighlight quick action.
    public let isHighlighted: Bool
    /// Drives archive/unarchive.
    public let isArchived: Bool
    /// `nil` when the conversation has never been read. Apollo's
    /// mark-unread action sets this back.
    public let lastUnread: String?
    /// False for archived or otherwise closed threads, where the
    /// reply box must not be offered.
    public let isRepliable: Bool
    /// The ordered message ids. A modmail conversation's messages
    /// arrive as an unordered dictionary, so this list is the ONLY
    /// source of display order.
    public let messageIDs: [String]
    /// The user the conversation is with.
    public let participantName: String?

    /// Reddit reports unread via `lastUnread` being present, not a boolean.
    public var isUnread: Bool { lastUnread != nil }

    /// Parsed `lastUpdated` for merge-sorting against `RedditMessage.created`
    /// when `GeneralSettings.unifyModmailInInbox` is on. Reddit's modmail
    /// API returns this as an ISO-8601 string, unlike the inbox message
    /// API's UTC-seconds `created_utc`.
    public var lastUpdatedDate: Date? {
        guard let lastUpdated else { return nil }
        return ISO8601DateFormatter().date(from: lastUpdated)
    }

    enum CodingKeys: String, CodingKey {
        case id, subject, state, lastUpdated, isAuto, numMessages, owner
        case isHighlighted, isArchived, lastUnread, isRepliable
        case objIds, participant
    }

    enum OwnerCodingKeys: String, CodingKey {
        case displayName
    }

    enum ParticipantCodingKeys: String, CodingKey {
        case name
    }

    /// One entry of the `objIds` list: `{"id": "...", "key": "messages"}`.
    struct ObjID: Decodable {
        let id: String
        let key: String?
    }

    /// Memberwise init, so the web-session (GraphQL) transport can produce the
    /// same model as the REST transport.
    public init(
        id: String,
        subject: String,
        lastUpdated: String?,
        isAuto: Bool = false,
        numMessages: Int,
        state: Int = 0,
        subredditName: String?,
        isHighlighted: Bool = false,
        isArchived: Bool = false,
        lastUnread: String?,
        isRepliable: Bool = true,
        messageIDs: [String] = [],
        participantName: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.lastUpdated = lastUpdated
        self.isAuto = isAuto
        self.numMessages = numMessages
        self.state = state
        self.subredditName = subredditName
        self.isHighlighted = isHighlighted
        self.isArchived = isArchived
        self.lastUnread = lastUnread
        self.isRepliable = isRepliable
        self.messageIDs = messageIDs
        self.participantName = participantName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)
        lastUpdated = try? container.decode(String.self, forKey: .lastUpdated)
        isAuto = (try? container.decode(Bool.self, forKey: .isAuto)) ?? false
        numMessages = (try? container.decode(Int.self, forKey: .numMessages)) ?? 0
        state = (try? container.decode(Int.self, forKey: .state)) ?? 0
        if let ownerContainer = try? container.nestedContainer(keyedBy: OwnerCodingKeys.self, forKey: .owner) {
            subredditName = try? ownerContainer.decode(String.self, forKey: .displayName)
        } else {
            subredditName = nil
        }
        isHighlighted = (try? container.decode(Bool.self, forKey: .isHighlighted)) ?? false
        isArchived = (try? container.decode(Bool.self, forKey: .isArchived)) ?? false
        lastUnread = try? container.decode(String.self, forKey: .lastUnread)
        // Defaults to true: a conversation Reddit did not mark otherwise is
        // repliable, and false would hide the reply box on threads whose
        // response omits the key.
        isRepliable = (try? container.decode(Bool.self, forKey: .isRepliable)) ?? true
        // `objIds` mixes messages and mod actions; only the message
        // entries order the thread.
        let objIDs = (try? container.decode([ObjID].self, forKey: .objIds)) ?? []
        messageIDs = objIDs.filter { $0.key == nil || $0.key == "messages" }.map(\.id)
        if let participantContainer = try? container.nestedContainer(keyedBy: ParticipantCodingKeys.self, forKey: .participant) {
            participantName = try? participantContainer.decode(String.self, forKey: .name)
        } else {
            participantName = nil
        }
    }
}

/// A single message within a modmail conversation thread.
///
/// JSON keys: `bodyMarkdown`, `participant`, `authors`, `isInternal`; the
/// date format is `yyyy-MM-dd'T'HH:mm:ss.SSSZ` in `en_US_POSIX`.
public struct ModmailMessage: Decodable, Sendable, Identifiable {
    public let id: String
    /// The key is `bodyMarkdown`, not `body`: Reddit also returns pre-rendered
    /// HTML, but the markdown is what the app's renderer wants.
    public let body: String
    public let author: ModmailAuthor?
    public let date: String?
    /// A moderator-only note, invisible to the user the conversation
    /// is with. Shown distinctly, because mistaking a private mod
    /// note for a user-visible reply is the kind of error that matters.
    public let isInternal: Bool

    public struct ModmailAuthor: Decodable, Sendable {
        public let name: String
        public let isMod: Bool
        /// Reddit hides the author of some participant messages.
        public let isHidden: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case isMod
            case isHidden = "isAuthorHidden"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            isMod = (try? c.decode(Bool.self, forKey: .isMod)) ?? false
            isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false
        }

        public init(name: String, isMod: Bool, isHidden: Bool = false) {
            self.name = name
            self.isMod = isMod
            self.isHidden = isHidden
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bodyMarkdown
        case body
        case author
        case date
        case isInternal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        // Prefer `bodyMarkdown`, falling back to `body` so a response shape
        // change shows something rather than an empty message.
        body = (try? c.decode(String.self, forKey: .bodyMarkdown))
            ?? (try? c.decode(String.self, forKey: .body))
            ?? ""
        author = try? c.decode(ModmailAuthor.self, forKey: .author)
        date = try? c.decode(String.self, forKey: .date)
        isInternal = (try? c.decode(Bool.self, forKey: .isInternal)) ?? false
    }

    public init(id: String, body: String, author: ModmailAuthor?, date: String?, isInternal: Bool = false) {
        self.id = id
        self.body = body
        self.author = author
        self.date = date
        self.isInternal = isInternal
    }

    /// Parsed `date` (`yyyy-MM-dd'T'HH:mm:ss.SSSZ`), in `en_US_POSIX` since a
    /// non-Gregorian device calendar would otherwise break the parse.
    public var parsedDate: Date? {
        guard let date else { return nil }
        return ModmailMessage.dateFormatter.date(from: date)
            ?? ISO8601DateFormatter().date(from: date)
    }

    nonisolated(unsafe) private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()
}

/// A full modmail conversation: the thread plus its messages.
///
/// Response envelope: `conversation`, `messages`, `modActions`. `messages`
/// is a dictionary keyed by id, with display order carried separately by
/// the conversation's `objIds` list.
public struct ModmailConversationDetail: Sendable {
    public let conversation: ModmailConversation
    /// Messages in display order.
    public let messages: [ModmailMessage]

    public init(conversation: ModmailConversation, messages: [ModmailMessage]) {
        self.conversation = conversation
        self.messages = messages
    }

    /// Decodes the envelope, restoring display order from `objIds`. A
    /// dictionary has no order, so `.values` alone would show a thread in
    /// arbitrary order.
    public static func decode(from data: Data) throws -> ModmailConversationDetail {
        struct Envelope: Decodable {
            let conversation: ModmailConversation
            let messages: [String: ModmailMessage]?
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let byID = envelope.messages ?? [:]
        var ordered: [ModmailMessage] = []
        var seen = Set<String>()
        for objID in envelope.conversation.messageIDs where !seen.contains(objID) {
            if let message = byID[objID] {
                seen.insert(objID)
                ordered.append(message)
            }
        }
        // Anything Reddit returned but did not list stays visible,
        // sorted by date, rather than being silently dropped.
        let leftovers = byID.values
            .filter { !seen.contains($0.id) }
            .sorted { ($0.parsedDate ?? .distantPast) < ($1.parsedDate ?? .distantPast) }
        return ModmailConversationDetail(
            conversation: envelope.conversation,
            messages: ordered + leftovers
        )
    }
}
