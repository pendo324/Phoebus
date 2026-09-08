import Foundation

/// A modmail conversation from Reddit's Shreddit GraphQL endpoint
/// (`modmailConversationsV2`), the only modmail surface reachable over
/// a cookie/web session.
///
/// Kept separate from `ModmailConversation` (the REST
/// `/api/mod/conversations` shape): GraphQL returns prefixed ids
/// (`ModmailConversation_3q3cd2`), microsecond ISO-8601 timestamps, a
/// `type` enum, and the last message inline, while REST returns a bare
/// id and messages in a separate dictionary.
public struct ModmailWebConversation: Sendable, Identifiable, Equatable {
    /// The prefixed id, e.g. `ModmailConversation_3q3cd2`, kept as-is
    /// since mutations require the prefix.
    public let id: String
    public let subject: String
    public let numMessages: Int
    /// Known values: `INTERNAL` (mod-to-own-subreddit); `SrSr` / `SrUser`
    /// variants exist for created conversations.
    public let type: String?
    public let isArchived: Bool
    public let isHighlighted: Bool
    public let isFiltered: Bool
    public let isAppeal: Bool
    public let isJoinRequest: Bool
    /// Non-nil means unread, same rule as the REST shape's `lastUnread`.
    public let lastUnreadAt: Date?
    public let lastModUpdateAt: Date?
    public let lastUserUpdateAt: Date?
    public let subredditName: String?
    public let subredditPrefixedName: String?
    public let subredditID: String?
    /// The participant this conversation is with, when it is not an
    /// internal mod discussion.
    public let participantName: String?
    public let lastMessageMarkdown: String?
    public let lastMessageAuthor: String?
    public let lastMessageAuthorIconURL: URL?

    public var isUnread: Bool { lastUnreadAt != nil }

    /// The bare id, for display and for building `/mail/...` links.
    public var bareID: String {
        id.hasPrefix("ModmailConversation_")
            ? String(id.dropFirst("ModmailConversation_".count))
            : id
    }

    /// Newest activity, for sorting a merged inbox.
    public var lastUpdated: Date? {
        [lastUserUpdateAt, lastModUpdateAt].compactMap { $0 }.max()
    }

    public init?(node: [String: Any]) {
        guard let id = node["id"] as? String else { return nil }
        self.id = id
        subject = node["subject"] as? String ?? ""
        numMessages = node["numMessages"] as? Int ?? 0
        type = node["type"] as? String
        isArchived = node["isArchived"] as? Bool ?? false
        isHighlighted = node["isHighlighted"] as? Bool ?? false
        isFiltered = node["isFiltered"] as? Bool ?? false
        isAppeal = node["isAppeal"] as? Bool ?? false
        isJoinRequest = node["isJoinRequest"] as? Bool ?? false
        lastUnreadAt = ModmailWebDate.parse(node["lastUnreadAt"] as? String)
        lastModUpdateAt = ModmailWebDate.parse(node["lastModUpdateAt"] as? String)
        lastUserUpdateAt = ModmailWebDate.parse(node["lastUserUpdateAt"] as? String)

        let subredditInfo = (node["subredditOrProfileInfo"] as? [String: Any])?["subredditInfo"] as? [String: Any]
        subredditName = subredditInfo?["name"] as? String
        subredditPrefixedName = subredditInfo?["prefixedName"] as? String
        subredditID = subredditInfo?["id"] as? String

        let participant = node["participant"] as? [String: Any]
        participantName = (participant?["redditorInfo"] as? [String: Any])?["name"] as? String

        let lastMessage = node["lastMessage"] as? [String: Any]
        lastMessageMarkdown = (lastMessage?["body"] as? [String: Any])?["markdown"] as? String
        let author = lastMessage?["authorInfo"] as? [String: Any]
        lastMessageAuthor = author?["name"] as? String
        if let iconString = (author?["icon"] as? [String: Any])?["url"] as? String {
            lastMessageAuthorIconURL = URL(string: iconString)
        } else {
            lastMessageAuthorIconURL = nil
        }
    }
}

/// One entry in a modmail thread. Reddit interleaves messages and
/// moderator actions in a single `messagesAndActions` connection,
/// discriminated by `__typename`; modelling only messages would drop
/// the inline audit trail ("highlighted by u/x").
public struct ModmailWebThreadEntry: Sendable, Identifiable, Equatable {
    public enum Kind: Sendable, Equatable {
        case message
        /// Known values: `HIGHLIGHTED`, `UNHIGHLIGHTED`; the mutation set
        /// implies ARCHIVED / UNARCHIVED / FILTERED / UNFILTERED too.
        case action(String)
    }

    public let id: String
    public let kind: Kind
    public let createdAt: Date?
    public let authorName: String?
    public let authorIconURL: URL?
    /// Message body markdown. `nil` for actions.
    public let markdown: String?
    /// A moderator-only note, invisible to the conversation's
    /// participant (same meaning as REST's `isInternal`).
    public let isInternal: Bool
    public let isAuthorHidden: Bool
    public let participatingAs: String?

    public var isMessage: Bool { if case .message = kind { return true }; return false }

    public init?(node: [String: Any]?) {
        guard let node, let id = node["id"] as? String else { return nil }
        let typename = node["__typename"] as? String
        switch typename {
        case "ModmailMessage":
            kind = .message
        case "ModmailAction":
            kind = .action(node["actionType"] as? String ?? "UNKNOWN")
        default:
            return nil
        }
        self.id = id
        createdAt = ModmailWebDate.parse(node["createdAt"] as? String)
        let author = node["authorInfo"] as? [String: Any]
        authorName = author?["name"] as? String
        if let iconString = (author?["icon"] as? [String: Any])?["url"] as? String {
            authorIconURL = URL(string: iconString)
        } else {
            authorIconURL = nil
        }
        markdown = (node["body"] as? [String: Any])?["markdown"] as? String
        isInternal = node["isInternal"] as? Bool ?? false
        isAuthorHidden = node["isAuthorHidden"] as? Bool ?? false
        participatingAs = node["participatingAs"] as? String
    }
}

/// Parses Reddit's modmail timestamps, which have fractional seconds and
/// a `+0000` offset with no colon (`2026-09-14T13:53:06.414000+0000`).
/// `ISO8601DateFormatter`'s default options fail on that, so the fractional
/// option is set explicitly with a non-fractional fallback.
public enum ModmailWebDate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}

// MARK: - Bridging to the REST-shaped model

extension ModmailWebConversation {
    /// Projects the GraphQL shape onto `ModmailConversation`, so
    /// `ModmailListScreen` works identically under either sign-in
    /// method. The id keeps its `ModmailConversation_` prefix since
    /// quick actions round-trip it straight into a mutation.
    public var asModmailConversation: ModmailConversation {
        ModmailConversation(
            id: id,
            subject: subject,
            lastUpdated: lastUpdated.map(ModmailWebDate.string(from:)),
            numMessages: numMessages,
            subredditName: subredditName,
            isHighlighted: isHighlighted,
            isArchived: isArchived,
            lastUnread: lastUnreadAt.map(ModmailWebDate.string(from:)),
            participantName: participantName
        )
    }
}

extension ModmailWebThreadEntry {
    /// Projects a thread MESSAGE onto `ModmailMessage`. Returns nil for
    /// mod actions, which have no equivalent in the REST model and are
    /// rendered separately rather than faked as empty messages.
    public var asModmailMessage: ModmailMessage? {
        guard isMessage else { return nil }
        return ModmailMessage(
            id: id,
            body: markdown ?? "",
            author: authorName.map {
                ModmailMessage.ModmailAuthor(
                    name: $0,
                    isMod: participatingAs == "MODERATOR",
                    isHidden: isAuthorHidden
                )
            },
            date: createdAt.map(ModmailWebDate.string(from:)),
            isInternal: isInternal
        )
    }
}

extension ModmailWebDate {
    /// Re-serializes to the same fractional ISO-8601 form Reddit sends,
    /// so a bridged value parses back identically through the REST
    /// model's own date handling.
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
