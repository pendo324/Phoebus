import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reddit Chat, over Matrix.
///
/// Reddit's modern Chat is Matrix: the web client talks to a homeserver
/// at `matrix.redditspace.com`, and the account's `token_v2` cookie
/// value works directly as a plain OAuth bearer there (Apollo-Reborn's
/// finding), so Chat is reachable without a web view.
///
/// Neither the current (matrix-rust-components-swift) nor legacy
/// (matrix-ios-sdk) Matrix SDK is used: Reddit does not support sliding
/// sync, which the current SDK requires, and the legacy SDK's login
/// flow does not support Reddit's proprietary `com.reddit.token` type
/// and cannot cross-compile from Linux. Reddit Chat uses no
/// encryption, so an SDK's main value (E2E, device verification, key
/// backup) is moot here; this file just does plain HTTP and JSON.
public enum RedditChatClient {
    /// Homeserver.
    public static let homeserver = "https://matrix.redditspace.com"

    /// Safari persona for the token-mint request, so it looks like the session Reddit harvested.
    static let browserUserAgent = BrowserUserAgent.mobileSafari

    /// Sync filter for the room directory: room state, one message per room, `m.direct`, no presence.
    static let directorySyncFilter =
        #"{"room":{"timeline":{"limit":1,"types":["m.room.message"]},"#
        + #""state":{"lazy_load_members":false},"ephemeral":{"types":[]},"account_data":{"types":[]}},"#
        + #""presence":{"types":[]},"account_data":{"types":["m.direct"]}}"#

    /// Reddit's own badge counter keys.
    /// One Matrix id (`!room:server`, `$event`, `@user:server`) as a
    /// URL path segment: everything but letters and digits escaped.
    static func pathSegment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
    }

    public static let unreadCounterKey = "com.reddit.global_navigation_counter"
    public static let requestsCounterKey = "com.reddit.invites_counter"

    // MARK: Bearer

    public enum ChatError: Error, LocalizedError {
        case noWebSession
        case mintFailed
        case unauthorized
        case httpError(status: Int)

        public var errorDescription: String? {
            switch self {
            case .noWebSession:
                return "Reddit Chat needs a web session. Sign in without an API key, or add a web session under Accounts."
            case .mintFailed:
                return "Couldn't get a Chat token from your Reddit session."
            case .unauthorized:
                return "Reddit rejected the Chat token. Try again, or re-harvest your web session."
            case .httpError(let status):
                return "Reddit Chat returned HTTP \(status)."
            }
        }
    }

    /// Mints `token_v2` through a real browser page load. Reddit only
    /// re-issues the cookie to a browser: a plain `URLSession` GET with
    /// the same cookies and headers comes back without one (Reborn's
    /// finding; the client fingerprint is what differs). Installed by
    /// the app as an offscreen web view (`ChatTokenWebMinter`).
    nonisolated(unsafe) public static var browserMinter: (@Sendable (_ cookieHeader: String) async -> String?)?

    /// The session's own `token_v2`, when it is a bearer that is still
    /// good, so Chat needs no mint at all.
    public static func storedBearer(cookieHeader: String, now: Date = Date()) -> String? {
        guard let pair = cookieHeader.components(separatedBy: "; ").first(where: { $0.hasPrefix("token_v2=") }) else {
            return nil
        }
        let token = String(pair.dropFirst("token_v2=".count))
        guard expiry(ofJWT: token) != nil, !isExpired(token, now: now, margin: 120) else { return nil }
        return token
    }

    /// Mints a fresh Matrix bearer from a stored cookie header.
    ///
    /// Sends the session cookies MINUS `token_v2`; Reddit reliably
    /// issues a fresh one for a session presenting none. Keeping the
    /// stored token instead just echoes it back, expired.
    public static func mintBearer(cookieHeader: String, session: URLSession = .shared) async throws -> String {
        if let browserMinter {
            guard cookieHeader.components(separatedBy: "; ").contains(where: { !$0.hasPrefix("token_v2=") }) else {
                throw ChatError.noWebSession
            }
            if let token = await browserMinter(cookieHeader) { return token }
            throw ChatError.mintFailed
        }
        let withoutToken = cookieHeader
            .components(separatedBy: "; ")
            .filter { !$0.hasPrefix("token_v2=") }
            .joined(separator: "; ")
        guard !withoutToken.isEmpty else { throw ChatError.noWebSession }

        guard let url = URL(string: "https://www.reddit.com/chat/") else { throw ChatError.mintFailed }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue(withoutToken, forHTTPHeaderField: "Cookie")
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.mintFailed }
        guard let token = extractTokenV2(from: http) else { throw ChatError.mintFailed }
        return token
    }

    /// Pulls a `token_v2` out of a response's `Set-Cookie` headers.
    public static func extractTokenV2(from response: HTTPURLResponse) -> String? {
        // Comma-joined Set-Cookie headers can't be split on commas (Expires dates contain one).
        let combined = response.allHeaderFields
            .filter { ($0.key as? String)?.lowercased() == "set-cookie" }
            .compactMap { $0.value as? String }
            .joined(separator: "\n")
        return extractTokenV2(fromSetCookie: combined)
    }

    public static func extractTokenV2(fromSetCookie raw: String) -> String? {
        guard let range = raw.range(of: "token_v2=") else { return nil }
        let rest = raw[range.upperBound...]
        let value = rest.prefix { $0 != ";" && $0 != "," && $0 != "\n" && $0 != " " }
        return value.isEmpty ? nil : String(value)
    }

    /// Whether a JWT bearer is still valid, with a safety margin. Reads `exp` so a dead
    /// bearer is never sent instead of being re-minted per request.
    public static func expiry(ofJWT token: String) -> Date? {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    public static func isExpired(_ token: String, now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        guard let expiry = expiry(ofJWT: token) else { return false }
        return expiry.timeIntervalSince(now) <= margin
    }

    // MARK: Sync

    /// One `/sync` response, reduced to what a chat list needs.
    public struct SyncResult: Sendable, Equatable {
        /// Reddit's own pre-computed unread count.
        public let unreadCount: Int
        /// Pending chat requests.
        public let requestsCount: Int
        public let rooms: [ChatRoom]
        /// Incremental token for the next poll.
        public let nextBatch: String?
    }

    public static func sync(bearer: String, since: String? = nil, session: URLSession = .shared) async throws -> SyncResult {
        var components = URLComponents(string: homeserver + "/_matrix/client/v3/sync")
        var query = [
            URLQueryItem(name: "timeout", value: "0"),
            URLQueryItem(name: "set_presence", value: "offline"), // never advertise presence from a background poll
            URLQueryItem(name: "filter", value: directorySyncFilter),
        ]
        if let since, !since.isEmpty { query.append(URLQueryItem(name: "since", value: since)) }
        components?.queryItems = query
        guard let url = components?.url else { throw ChatError.mintFailed }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        // 401/403 means the bearer is dead and must be re-minted, not retried.
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200 else { throw ChatError.httpError(status: http.statusCode) }
        return try parseSync(data)
    }

    /// The live sync's filter: the directory's room data plus new
    /// timeline events (messages, reactions, redactions) and typing and
    /// receipt events.
    static let liveSyncFilter =
        #"{"room":{"timeline":{"limit":10,"types":["m.room.message","m.reaction","m.room.redaction"]},"#
        + #""state":{"lazy_load_members":false},"ephemeral":{"types":["m.typing","m.receipt"]},"account_data":{"types":[]}},"#
        + #""presence":{"types":[]},"account_data":{"types":["m.direct"]}}"#

    /// One raw `/sync` for `ChatLiveSync`. With `since` and a timeout the
    /// homeserver holds the request until something happens.
    public static func liveSync(bearer: String, since: String?, timeoutMilliseconds: Int,
                                session: URLSession = .shared) async throws -> Data {
        var components = URLComponents(string: homeserver + "/_matrix/client/v3/sync")
        var query = [
            URLQueryItem(name: "timeout", value: String(timeoutMilliseconds)),
            URLQueryItem(name: "set_presence", value: "offline"),
            URLQueryItem(name: "filter", value: liveSyncFilter),
        ]
        if let since, !since.isEmpty { query.append(URLQueryItem(name: "since", value: since)) }
        components?.queryItems = query
        guard let url = components?.url else { throw ChatError.mintFailed }
        // Longer than the server's hold, so the client never gives up first.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: TimeInterval(timeoutMilliseconds) / 1000 + 20)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw ChatError.unauthorized }
        guard status == 200 else { throw ChatError.httpError(status: status) }
        return data
    }

    /// Parses a `/sync` payload.
    public static func parseSync(_ data: Data) throws -> SyncResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatError.httpError(status: 0)
        }
        let unread = (root[unreadCounterKey] as? NSNumber)?.intValue ?? 0
        let requests = (root[requestsCounterKey] as? NSNumber)?.intValue ?? 0
        let nextBatch = root["next_batch"] as? String

        var rooms: [ChatRoom] = []
        let roomsRoot = root["rooms"] as? [String: Any] ?? [:]
        for (bucket, isInvite) in [("join", false), ("invite", true)] {
            guard let group = roomsRoot[bucket] as? [String: Any] else { continue }
            for (roomID, value) in group {
                guard let room = value as? [String: Any] else { continue }
                rooms.append(parseRoom(id: roomID, payload: room, isInvite: isInvite))
            }
        }
        // Newest first, the order a chat list is read in.
        rooms.sort { $0.lastMessageTimestamp > $1.lastMessageTimestamp }
        return SyncResult(unreadCount: unread, requestsCount: requests, rooms: rooms, nextBatch: nextBatch)
    }

    /// Parses one room's state, invite, and timeline event buckets.
    static func parseRoom(id: String, payload: [String: Any], isInvite: Bool) -> ChatRoom {
        var name: String?
        var chatType: String?
        var participants = Set<String>()
        var lastTimestamp: Double = 0
        var preview: String?
        var previewSender: String?

        // An invited room carries `invite_state`, not `state`.
        for bucket in ["state", "invite_state", "timeline"] {
            guard let holder = payload[bucket] as? [String: Any],
                  let events = holder["events"] as? [[String: Any]] else { continue }
            for event in events {
                let type = event["type"] as? String ?? ""
                let content = event["content"] as? [String: Any] ?? [:]
                switch type {
                case "m.room.name":
                    if let value = content["name"] as? String { name = value }
                case "com.reddit.chat.type":
                    if let value = content["type"] as? String { chatType = value }
                    if let list = content["participants"] as? [String] {
                        participants.formUnion(list)
                    }
                case "m.room.member":
                    let membership = content["membership"] as? String ?? ""
                    if let userID = event["state_key"] as? String,
                       membership == "join" || membership == "invite" {
                        participants.insert(userID)
                    }
                case "m.room.message":
                    // A redacted message has no content and must not become an empty preview.
                    if let unsigned = event["unsigned"] as? [String: Any],
                       unsigned["redacted_because"] != nil { break }
                    let ts = (event["origin_server_ts"] as? NSNumber)?.doubleValue ?? 0
                    if ts >= lastTimestamp {
                        lastTimestamp = ts
                        // An edit's top-level body is the legacy "* new text" fallback;
                        // prefer the real new content.
                        let newContent = content["m.new_content"] as? [String: Any]
                        preview = (newContent?["body"] as? String) ?? content["body"] as? String
                        previewSender = event["sender"] as? String
                    }
                default:
                    break
                }
            }
        }

        // The summary's heroes name an unnamed room's participants when member events weren't paged in.
        if let summary = payload["summary"] as? [String: Any],
           let heroes = summary["m.heroes"] as? [String] {
            participants.formUnion(heroes)
        }

        let notifications = payload["unread_notifications"] as? [String: Any] ?? [:]
        let notificationCount = (notifications["notification_count"] as? NSNumber)?.intValue ?? 0
        // Not every room with a notification_count feeds the global badge.
        // A room without the flag counts, as in Reborn's poller.
        let countsTowardBadge = (notifications["com.reddit.is_counted_in_global_navigation_counter"] as? NSNumber)?.boolValue ?? true

        return ChatRoom(
            id: id,
            name: name,
            chatType: chatType,
            participants: participants.sorted(),
            isInvite: isInvite,
            lastMessageTimestamp: lastTimestamp,
            preview: preview,
            previewSender: previewSender,
            notificationCount: notificationCount,
            countsTowardGlobalBadge: countsTowardBadge
        )
    }

    /// The signed-in account's own Matrix user id (`/account/whoami`).
    ///
    /// Needed because a direct room is titled by its OTHER participant; without knowing
    /// which one is you, every DM would be titled with your own name.
    public static func whoami(bearer: String, session: URLSession = .shared) async -> String? {
        guard let url = URL(string: homeserver + "/_matrix/client/v3/account/whoami") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await session.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["user_id"] as? String
    }

    // MARK: Room messages

    /// One message in a chat room.
    public struct ChatMessage: Sendable, Equatable, Identifiable {
        public let id: String
        public let sender: String
        public let body: String
        public let timestamp: Double
        /// Matrix `msgtype`, e.g. `m.text` / `m.image`.
        public let msgtype: String?
        /// Number of replies in this message's thread, from Matrix's
        /// bundled `m.relations["m.thread"].count`. Zero when the
        /// message has no thread.
        public let threadReplyCount: Int
        /// For `m.image`/`m.video`/`m.file`: the `mxc://` URI.
        public let mediaURI: String?
        /// Declared pixel size, for laying a bubble out before the
        /// image loads.
        public let mediaWidth: Int?
        public let mediaHeight: Int?
        /// Declared mimetype, which is how a GIF is told from a still
        /// (the URL has no extension).
        public let mimeType: String?
        /// True when a later `m.replace` event edited this message.
        public let isEdited: Bool
        /// Ids of the edit events folded into this message, since a reaction
        /// can annotate the EDIT rather than the original.
        public let editEventIDs: [String]

        /// Every event id that can carry reactions for this message.
        public var reactionEventIDs: [String] { [id] + editEventIDs }
        /// The sender's username, when Reddit bundled it.
        ///
        /// Reddit attaches a `com.reddit.profile` relation
        /// to messages carrying `username`, `displayname` and avatar
        /// URLs. That makes a per-participant `/profile` request
        /// unnecessary for any sender who has spoken in the room -
        /// which is most of them.
        public let senderUsername: String?
        public let senderAvatarURL: String?

        public var date: Date? {
            timestamp > 0 ? Date(timeIntervalSince1970: timestamp / 1000) : nil
        }

        /// True for a message whose content is media rather than text.
        ///
        /// Reddit serves chat media from the homeserver with no file
        /// extension, so the msgtype is the only reliable signal of
        /// what a message is; the URL cannot be sniffed.
        public var isMedia: Bool {
            mediaURI != nil && (msgtype == "m.image" || msgtype == "m.video" || msgtype == "m.file")
        }

        /// True for video, which needs a play affordance rather than a
        /// plain image view.
        public var isVideo: Bool {
            mediaURI != nil && msgtype == "m.video"
        }

        /// True for an animated GIF, which must be rendered by the
        /// animating image view rather than as a still.
        ///
        /// Detected by mimetype, since the URL carries no extension.
        public var isAnimatedGIF: Bool {
            mimeType?.lowercased() == "image/gif"
        }

        /// The HTTP URL for this message's media.
        public var mediaDownloadURL: URL? {
            mediaURI.flatMap { RedditChatClient.downloadURL(forMXC: $0) }
        }

        public init(
            id: String,
            sender: String,
            body: String,
            timestamp: Double,
            msgtype: String?,
            mediaURI: String? = nil,
            mediaWidth: Int? = nil,
            mediaHeight: Int? = nil,
            mimeType: String? = nil,
            isEdited: Bool = false,
            editEventIDs: [String] = [],
            threadReplyCount: Int = 0,
            senderUsername: String? = nil,
            senderAvatarURL: String? = nil
        ) {
            self.id = id
            self.sender = sender
            self.body = body
            self.timestamp = timestamp
            self.msgtype = msgtype
            self.mediaURI = mediaURI
            self.mediaWidth = mediaWidth
            self.mediaHeight = mediaHeight
            self.mimeType = mimeType
            self.isEdited = isEdited
            self.editEventIDs = editEventIDs
            self.threadReplyCount = threadReplyCount
            self.senderUsername = senderUsername
            self.senderAvatarURL = senderAvatarURL
        }
    }

    /// Fetches a room's recent messages.
    ///
    /// `dir=b` walks backwards from the most recent event, which is what a chat view wants.
    public static func messages(
        roomID: String,
        bearer: String,
        limit: Int = 50,
        session: URLSession = .shared
    ) async throws -> [ChatMessage] {
        let encoded = pathSegment(roomID)
        var components = URLComponents(string: homeserver + "/_matrix/client/v3/rooms/\(encoded)/messages")
        components?.queryItems = [
            URLQueryItem(name: "dir", value: "b"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else { throw ChatError.httpError(status: 0) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200 else { throw ChatError.httpError(status: http.statusCode) }
        return parseMessages(data)
    }

    /// Parses a `/messages` chunk into display order.
    public static func parseMessages(_ data: Data) -> [ChatMessage] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chunk = root["chunk"] as? [[String: Any]] else { return [] }
        // Edits arrive as separate m.replace events; fold them into their target first
        // so both the stale original and a stray edit line don't render.
        var edits: [String: String] = [:]
        var editIDs: [String: [String]] = [:]
        for event in chunk {
            let content = event["content"] as? [String: Any] ?? [:]
            guard let relation = content["m.relates_to"] as? [String: Any],
                  relation["rel_type"] as? String == "m.replace",
                  let targetID = relation["event_id"] as? String,
                  let newContent = content["m.new_content"] as? [String: Any],
                  let newBody = newContent["body"] as? String else { continue }
            edits[targetID] = newBody
            if let editID = event["event_id"] as? String {
                editIDs[targetID, default: []].append(editID)
            }
        }

        var messages: [ChatMessage] = []
        for event in chunk {
            guard event["type"] as? String == "m.room.message" else { continue }
            let content = event["content"] as? [String: Any] ?? [:]
            // A redacted message has its content stripped and gains `unsigned.redacted_because`.
            if (event["unsigned"] as? [String: Any])?["redacted_because"] != nil { continue }
            // The edit event itself must not render as its own message.
            if let relation = content["m.relates_to"] as? [String: Any],
               relation["rel_type"] as? String == "m.replace" { continue }
            guard let rawBody = content["body"] as? String else { continue }
            let eventID = event["event_id"] as? String
            let editedBody = eventID.flatMap { edits[$0] }
            let body = editedBody ?? rawBody
            // Matrix bundles a thread's reply count here; Reddit adds `com.reddit.profile`
            // with the sender's username and avatar.
            let relations = (event["unsigned"] as? [String: Any])?["m.relations"] as? [String: Any] ?? [:]
            let thread = relations["m.thread"] as? [String: Any]
            let profile = relations["com.reddit.profile"] as? [String: Any]
            messages.append(ChatMessage(
                id: eventID ?? UUID().uuidString,
                sender: event["sender"] as? String ?? "",
                body: body,
                timestamp: (event["origin_server_ts"] as? NSNumber)?.doubleValue ?? 0,
                msgtype: content["msgtype"] as? String,
                mediaURI: content["url"] as? String,
                mediaWidth: ((content["info"] as? [String: Any])?["w"] as? NSNumber)?.intValue,
                mediaHeight: ((content["info"] as? [String: Any])?["h"] as? NSNumber)?.intValue,
                mimeType: (content["info"] as? [String: Any])?["mimetype"] as? String,
                isEdited: editedBody != nil,
                editEventIDs: eventID.flatMap { editIDs[$0] } ?? [],
                threadReplyCount: (thread?["count"] as? NSNumber)?.intValue ?? 0,
                // Real keys: `username` is the handle; `displayname`
                // can be a chosen label ("MSI_Tech Support"), so the
                // handle is preferred for identity.
                senderUsername: profile?["username"] as? String ?? profile?["displayname"] as? String,
                senderAvatarURL: profile?["icon_url"] as? String
            ))
        }
        // The chunk arrives newest-first because of `dir=b`; flip it to oldest-first for reading.
        return messages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Fetches the replies in a message's thread.
    ///
    /// This uses `/v1`, not `/v3` like the other calls here: Matrix put the relations
    /// API in v1, and the room-level `/threads` listing endpoint (MSC3856) 404s, so
    /// threads are reachable per-message but not enumerable per-room.
    public static func threadReplies(
        roomID: String,
        eventID: String,
        bearer: String,
        limit: Int = 50,
        session: URLSession = .shared
    ) async throws -> [ChatMessage] {
        let room = pathSegment(roomID)
        let event = pathSegment(eventID)
        var components = URLComponents(
            string: homeserver + "/_matrix/client/v1/rooms/\(room)/relations/\(event)/m.thread"
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else { throw ChatError.httpError(status: 0) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200 else { throw ChatError.httpError(status: http.statusCode) }
        // Same chunk shape as /messages, so the same parse applies.
        return parseMessages(data)
    }

    // MARK: Sending

    /// Sends a text message into a room.
    ///
    /// The transaction id is the idempotency key: replaying the same txn id returns
    /// the same `event_id` (deduplicated) rather than a new one, so a retry must reuse
    /// the original id or a flaky network can deliver the message twice.
    ///
    /// Callers should not invent an id here; use `ChatSendQueue`, which
    /// assigns one at enqueue and persists it.
    public static func send(
        roomID: String,
        body: String,
        transactionID: String,
        bearer: String,
        session: URLSession = .shared
    ) async throws -> String {
        let room = pathSegment(roomID)
        let txn = pathSegment(transactionID)
        guard let url = URL(string: homeserver + "/_matrix/client/v3/rooms/\(room)/send/m.room.message/\(txn)") else {
            throw ChatError.httpError(status: 0)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "body": body,
            "msgtype": "m.text",
        ])

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200 else { throw ChatError.httpError(status: http.statusCode) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventID = object["event_id"] as? String else {
            throw ChatError.httpError(status: http.statusCode)
        }
        return eventID
    }

    /// Whether a failure is worth retrying, or should park the message for the user to decide about.
    ///
    /// Modelled on the Rust SDK's `EventSendState.sendingFailed(isRecoverable)`.
    public static func isRecoverable(_ error: Error) -> Bool {
        switch error {
        case ChatError.unauthorized:
            // A dead bearer is recoverable: re-mint and try again.
            return true
        case ChatError.httpError(let status):
            // Transport failure (0) or a server-side 5xx is transient; a 4xx rejects
            // this specific message, and retrying it just repeats the rejection.
            return status == 0 || status >= 500
        case ChatError.noWebSession, ChatError.mintFailed:
            return true
        default:
            return true
        }
    }

    /// Ephemeral room state: who is typing, and who has read what.
    ///
    /// "Ephemeral" is Matrix's own term; these live outside the timeline and
    /// are not persisted as events.
    public struct RoomEphemeral: Sendable, Equatable {
        /// Matrix user ids currently typing.
        public let typingUserIDs: [String]
        /// Newest event id each user has read.
        public let readReceipts: [String: String]

        public init(typingUserIDs: [String] = [], readReceipts: [String: String] = [:]) {
            self.typingUserIDs = typingUserIDs
            self.readReceipts = readReceipts
        }

        /// Whether anyone OTHER than you is typing.
        public func othersTyping(excluding selfUserID: String?) -> [String] {
            typingUserIDs.filter { $0 != selfUserID }
        }

        /// Whether someone other than you has read a given event.
        public func isReadByOthers(eventID: String, excluding selfUserID: String?) -> Bool {
            readReceipts.contains { $0.key != selfUserID && $0.value == eventID }
        }
    }

    /// Parses ephemeral events out of a `/sync` payload.
    public static func parseEphemeral(_ data: Data) -> [String: RoomEphemeral] {
        parseEphemeralEvents(data).reduce(into: [:]) { result, entry in
            let typing = entry.value.typing ?? []
            guard !typing.isEmpty || !entry.value.receipts.isEmpty else { return }
            result[entry.key] = RoomEphemeral(typingUserIDs: typing, readReceipts: entry.value.receipts)
        }
    }

    /// Per room: the typing list when an `m.typing` event was present
    /// (an empty list means everyone stopped), and the receipts carried.
    static func parseEphemeralEvents(_ data: Data) -> [String: (typing: [String]?, receipts: [String: String])] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let joined = (root["rooms"] as? [String: Any])?["join"] as? [String: Any] else { return [:] }
        var result: [String: (typing: [String]?, receipts: [String: String])] = [:]
        for (roomID, value) in joined {
            guard let room = value as? [String: Any],
                  let events = (room["ephemeral"] as? [String: Any])?["events"] as? [[String: Any]] else { continue }
            var typing: [String]?
            var receipts: [String: String] = [:]
            for event in events {
                let content = event["content"] as? [String: Any] ?? [:]
                switch event["type"] as? String {
                case "m.typing":
                    typing = content["user_ids"] as? [String] ?? []
                case "m.receipt":
                    // Real shape: keyed by EVENT id, then receipt type,
                    // then user. Inverted here to user -> event, which
                    // is how a UI asks the question ("has X read this?").
                    for (eventID, byType) in content {
                        guard let types = byType as? [String: Any],
                              let read = types["m.read"] as? [String: Any] else { continue }
                        for userID in read.keys { receipts[userID] = eventID }
                    }
                default:
                    break
                }
            }
            if typing != nil || !receipts.isEmpty { result[roomID] = (typing, receipts) }
        }
        return result
    }

    // MARK: Media

    /// Converts an `mxc://` URI to a downloadable HTTP URL.
    ///
    /// Uses the legacy unauthenticated media path; the newer authenticated variant
    /// 404s here, which also means image loading needs no bearer.
    public static func downloadURL(forMXC uri: String) -> URL? {
        guard uri.hasPrefix("mxc://") else { return nil }
        let path = uri.dropFirst("mxc://".count)
        guard !path.isEmpty else { return nil }
        return URL(string: homeserver + "/_matrix/media/v3/download/" + path)
    }

    /// A scaled thumbnail URL, for grid or preview use.
    public static func thumbnailURL(forMXC uri: String, width: Int = 800, height: Int = 800) -> URL? {
        guard uri.hasPrefix("mxc://") else { return nil }
        let path = uri.dropFirst("mxc://".count)
        return URL(string: homeserver
            + "/_matrix/media/v3/thumbnail/" + path
            + "?width=\(width)&height=\(height)&method=scale")
    }

    /// Uploads media and returns its `mxc://` URI.
    ///
    /// Reddit's limits: `m.upload.size` 20 MB, with a 100 MB ceiling for `image/gif`.
    public static func uploadMedia(
        data: Data,
        filename: String,
        mimeType: String,
        bearer: String,
        session: URLSession = .shared
    ) async throws -> String {
        var components = URLComponents(string: homeserver + "/_matrix/media/v3/upload")
        components?.queryItems = [URLQueryItem(name: "filename", value: filename)]
        guard let url = components?.url else { throw ChatError.httpError(status: 0) }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        guard let (responseData, response) = try? await session.upload(for: request, from: data),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let uri = object["content_uri"] as? String else {
            throw ChatError.httpError(status: http.statusCode)
        }
        return uri
    }

    /// Sends an already-uploaded image into a room.
    public static func sendImage(
        roomID: String,
        mxcURI: String,
        filename: String,
        mimeType: String,
        width: Int,
        height: Int,
        byteCount: Int,
        transactionID: String,
        bearer: String,
        session: URLSession = .shared
    ) async throws -> String {
        let room = pathSegment(roomID)
        let txn = pathSegment(transactionID)
        guard let url = URL(string: homeserver + "/_matrix/client/v3/rooms/\(room)/send/m.room.message/\(txn)") else {
            throw ChatError.httpError(status: 0)
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "body": filename,
            "msgtype": "m.image",
            "url": mxcURI,
            "info": ["mimetype": mimeType, "w": width, "h": height, "size": byteCount],
        ])
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventID = object["event_id"] as? String else {
            throw ChatError.httpError(status: http.statusCode)
        }
        return eventID
    }

    /// Edits an already-sent message.
    ///
    /// Sends a NEW `m.room.message` carrying `m.new_content` plus an `m.relates_to`
    /// of `rel_type: m.replace`. The top-level `body` is the fallback text older
    /// clients show, conventionally prefixed with `* `.
    @discardableResult
    public static func editMessage(
        roomID: String,
        eventID: String,
        newBody: String,
        transactionID: String,
        bearer: String,
        session: URLSession = .shared
    ) async throws -> String {
        let room = pathSegment(roomID)
        let txn = pathSegment(transactionID)
        guard let url = URL(string: homeserver + "/_matrix/client/v3/rooms/\(room)/send/m.room.message/\(txn)") else {
            throw ChatError.httpError(status: 0)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "body": "* " + newBody,
            "msgtype": "m.text",
            "m.new_content": ["body": newBody, "msgtype": "m.text"],
            "m.relates_to": ["rel_type": "m.replace", "event_id": eventID],
        ])
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newID = object["event_id"] as? String else {
            throw ChatError.httpError(status: http.statusCode)
        }
        return newID
    }

    /// Deletes (redacts) a message.
    ///
    /// Redaction strips the content server-side; the event remains with
    /// `unsigned.redacted_because`, which is how the parse knows to drop it.
    @discardableResult
    public static func redactMessage(
        roomID: String,
        eventID: String,
        reason: String?,
        transactionID: String,
        bearer: String,
        session: URLSession = .shared
    ) async throws -> String {
        let room = pathSegment(roomID)
        let event = pathSegment(eventID)
        let txn = pathSegment(transactionID)
        guard let url = URL(string: homeserver + "/_matrix/client/v3/rooms/\(room)/redact/\(event)/\(txn)") else {
            throw ChatError.httpError(status: 0)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: reason.map { ["reason": $0] } ?? [:])
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let redactionID = object["event_id"] as? String else {
            throw ChatError.httpError(status: http.statusCode)
        }
        return redactionID
    }

    // MARK: Reactions

    /// One reaction key on a message, with who reacted.
    public struct MessageReaction: Sendable, Equatable, Identifiable {
        public let key: String
        /// Senders, so a count can be shown and "did I react" answered.
        public let senders: [String]
        /// The current user's own reaction event, needed to remove it
        /// by redacting the event that added it.
        public let myEventID: String?

        public var id: String { key }
        public var count: Int { senders.count }
        public var imageURL: URL? { RedditChatReactions.imageURL(forKey: key) }

        public init(key: String, senders: [String], myEventID: String?) {
            self.key = key
            self.senders = senders
            self.myEventID = myEventID
        }
    }

    /// Adds a reaction to a message.
    ///
    /// `key` must be one of Reddit's 48 image filenames; see `RedditChatReactions`.
    ///
    /// Reacting twice with the same key returns 409, which is treated as success
    /// since the intended state already holds.
    @discardableResult
    public static func addReaction(
        roomID: String,
        eventID: String,
        key: String,
        transactionID: String,
        bearer: String,
        session: URLSession = .shared
    ) async throws -> String? {
        let room = pathSegment(roomID)
        let txn = pathSegment(transactionID)
        guard let url = URL(string: homeserver + "/_matrix/client/v3/rooms/\(room)/send/m.reaction/\(txn)") else {
            throw ChatError.httpError(status: 0)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "m.relates_to": [
                "rel_type": "m.annotation",
                "event_id": eventID,
                "key": key,
            ],
        ])
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        // Already reacted: the desired state holds, so this is a no-op.
        if http.statusCode == 409 { return nil }
        guard http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newID = object["event_id"] as? String else {
            throw ChatError.httpError(status: http.statusCode)
        }
        return newID
    }

    /// Removes a reaction by redacting the event that added it.
    ///
    /// There is no "unreact" endpoint; Matrix models removal as a
    /// redaction of the annotation event, which is why callers must
    /// keep the reaction's own event id.
    @discardableResult
    public static func removeReaction(
        roomID: String,
        reactionEventID: String,
        transactionID: String,
        bearer: String,
        session: URLSession = .shared
    ) async throws -> String {
        try await redactMessage(
            roomID: roomID, eventID: reactionEventID, reason: nil,
            transactionID: transactionID, bearer: bearer, session: session)
    }

    /// Parses a `/relations` response into reactions for one message.
    public static func parseReactions(_ data: Data, myUserID: String?) -> [MessageReaction] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chunk = object["chunk"] as? [[String: Any]] else { return [] }
        var senders: [String: [String]] = [:]
        var mine: [String: String] = [:]
        var order: [String] = []
        for event in chunk {
            guard event["type"] as? String == "m.reaction" else { continue }
            // A removed reaction keeps its content and is marked only by
            // `unsigned.redacted_because`, unlike a redacted message.
            if let unsigned = event["unsigned"] as? [String: Any],
               unsigned["redacted_because"] != nil { continue }
            guard let content = event["content"] as? [String: Any] else { continue }
            // Reddit's client flattens the relation into content; sync delivers it nested.
            let relation = (content["m.relates_to"] as? [String: Any]) ?? content
            guard relation["rel_type"] as? String == "m.annotation",
                  let key = relation["key"] as? String,
                  let sender = event["sender"] as? String else { continue }
            if senders[key] == nil { order.append(key) }
            senders[key, default: []].append(sender)
            if let myUserID, sender == myUserID, let id = event["event_id"] as? String {
                mine[key] = id
            }
        }
        return order.map {
            MessageReaction(key: $0, senders: senders[$0] ?? [], myEventID: mine[$0])
        }
    }

    /// Fetches the reactions on one message.
    ///
    /// Needs its own request: Reddit does not deliver reactions through `/messages`
    /// or bundle them into `unsigned.m.relations`, only `/sync` and `/relations`.
    public static func reactions(
        roomID: String,
        eventID: String,
        myUserID: String?,
        bearer: String,
        session: URLSession = .shared
    ) async throws -> [MessageReaction] {
        let room = pathSegment(roomID)
        let event = pathSegment(eventID)
        guard let url = URL(string: homeserver
            + "/_matrix/client/v1/rooms/\(room)/relations/\(event)/m.annotation") else {
            throw ChatError.httpError(status: 0)
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw ChatError.unauthorized }
        guard http.statusCode == 200 else { throw ChatError.httpError(status: http.statusCode) }
        return parseReactions(data, myUserID: myUserID)
    }

    // MARK: Receipts and typing

    /// Marks a message read. Best-effort: a failed receipt must never
    /// block reading a room, so this reports success rather than throwing.
    @discardableResult
    public static func sendReadReceipt(
        roomID: String,
        eventID: String,
        bearer: String,
        session: URLSession = .shared
    ) async -> Bool {
        let room = pathSegment(roomID)
        let event = pathSegment(eventID)
        guard let url = URL(string: homeserver + "/_matrix/client/v3/rooms/\(room)/receipt/m.read/\(event)") else {
            return false
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Publishes a typing notice. `timeout` is how long the server keeps the notice
    /// alive, so a client that stops typing (or dies) stops showing as typing
    /// without an explicit "stopped" call.
    @discardableResult
    public static func sendTyping(
        roomID: String,
        userID: String,
        isTyping: Bool,
        timeoutMilliseconds: Int = 20_000,
        bearer: String,
        session: URLSession = .shared
    ) async -> Bool {
        let room = pathSegment(roomID)
        let user = pathSegment(userID)
        guard let url = URL(string: homeserver + "/_matrix/client/v3/rooms/\(room)/typing/\(user)") else {
            return false
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PUT"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["typing": isTyping]
        if isTyping { payload["timeout"] = timeoutMilliseconds }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: Profiles

    /// Resolves a Matrix user id to its Reddit display name. A room's participants
    /// are opaque `t2_` ids that Reddit's own API does not resolve, so this is the
    /// only way to show a username.
    public static func displayName(forUserID userID: String, bearer: String, session: URLSession = .shared) async -> String? {
        let encoded = pathSegment(userID)
        guard let url = URL(string: homeserver + "/_matrix/client/v3/profile/" + encoded) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await session.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["displayname"] as? String
    }

    /// The Reddit account id inside a Matrix user id
    /// (`@t2_1a2b3c:reddit.com` -> `t2_1a2b3c`).
    public static func accountID(fromMatrixUserID userID: String) -> String? {
        guard userID.hasPrefix("@") else { return nil }
        let body = userID.dropFirst()
        guard let colon = body.firstIndex(of: ":") else { return nil }
        let id = String(body[body.startIndex..<colon])
        return id.isEmpty ? nil : id
    }
}

/// One Reddit Chat room.
public struct ChatRoom: Sendable, Equatable, Identifiable {
    public let id: String
    /// `m.room.name`, set only for titled (group) rooms.
    public let name: String?
    /// `com.reddit.chat.type.type`, e.g. "direct".
    public let chatType: String?
    /// Matrix user ids of the participants.
    public let participants: [String]
    /// A pending chat request rather than a joined room.
    public let isInvite: Bool
    /// `origin_server_ts` of the newest message, in milliseconds.
    public let lastMessageTimestamp: Double
    public let preview: String?
    public let previewSender: String?
    public let notificationCount: Int
    /// Whether this room feeds Reddit's global chat badge.
    public let countsTowardGlobalBadge: Bool

    public init(
        id: String,
        name: String?,
        chatType: String?,
        participants: [String],
        isInvite: Bool,
        lastMessageTimestamp: Double,
        preview: String?,
        previewSender: String?,
        notificationCount: Int,
        countsTowardGlobalBadge: Bool
    ) {
        self.id = id
        self.name = name
        self.chatType = chatType
        self.participants = participants
        self.isInvite = isInvite
        self.lastMessageTimestamp = lastMessageTimestamp
        self.preview = preview
        self.previewSender = previewSender
        self.notificationCount = notificationCount
        self.countsTowardGlobalBadge = countsTowardGlobalBadge
    }

    public var lastMessageDate: Date? {
        lastMessageTimestamp > 0 ? Date(timeIntervalSince1970: lastMessageTimestamp / 1000) : nil
    }

    /// A direct room has no `m.room.name`, so its title is the other
    /// participant. `self` is excluded, or every DM would be titled
    /// with your own name.
    public func otherParticipants(excluding selfUserID: String?) -> [String] {
        participants.filter { $0 != selfUserID }
    }
}
