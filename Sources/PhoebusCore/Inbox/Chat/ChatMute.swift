import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ChatMuteAction: String, Sendable, Equatable {
    case mute
    case unmute

    var isMute: Bool { self == .mute }
}

public enum ChatMuteError: Error, LocalizedError, Equatable {
    /// A change to this room is still in flight.
    case busy
    /// Requests cannot be muted: they are answered, not silenced.
    case notAJoinedRoom

    public var errorDescription: String? {
        switch self {
        case .busy: return "That conversation is already being changed."
        case .notAJoinedRoom: return "Only a conversation you have joined can be muted."
        }
    }
}

/// Muting a Reddit Chat room.
///
/// Reddit's own chat page mutes a room with a Matrix push rule: an
/// `override` rule whose id is the room id, with the action `dont_notify`
/// and one `event_match` condition on `room_id`. Unmuting deletes it. Reddit
/// then leaves the room out of its global badge counter. A timed mute adds
/// `com.reddit.expiration_ts` (milliseconds) to the rule and counts as muted
/// until then. The rules that mute only mentions, threads or reports have
/// other ids and extra conditions, and are not a muted room.
public enum ChatMute {
    /// How long a local change keeps overriding the counted flag a `/sync`
    /// reports, in seconds, while Reddit catches up with the rule.
    public static let staleShield: TimeInterval = 60

    static let expirationKey = "com.reddit.expiration_ts"

    private static func ruleURL(roomID: String) -> URL? {
        URL(string: RedditChatClient.homeserver
            + "/_matrix/client/v3/pushrules/global/override/\(RedditChatClient.pathSegment(roomID))")
    }

    private static func authorized(_ url: URL, method: String, bearer: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// The rule body that mutes `roomID`.
    public static func ruleBody(roomID: String) -> Data {
        let rule: [String: Any] = [
            "actions": ["dont_notify"],
            "conditions": [["key": "room_id", "kind": "event_match", "pattern": roomID]],
        ]
        return (try? JSONSerialization.data(withJSONObject: rule, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// The request that mutes (PUT the rule) or unmutes (DELETE it) a room.
    public static func request(_ action: ChatMuteAction, roomID: String, bearer: String) -> URLRequest? {
        guard let url = ruleURL(roomID: roomID) else { return nil }
        var request = authorized(url, method: action.isMute ? "PUT" : "DELETE", bearer: bearer)
        if action.isMute {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = ruleBody(roomID: roomID)
        }
        return request
    }

    /// The request for the account's push rules.
    public static func rulesRequest(bearer: String) -> URLRequest? {
        URL(string: RedditChatClient.homeserver + "/_matrix/client/v3/pushrules/")
            .map { authorized($0, method: "GET", bearer: bearer) }
    }

    /// The rooms the account's push rules mute, from a `/pushrules` answer.
    ///
    /// A room is muted by an enabled `override` rule whose id is the room id,
    /// whose only condition is an `event_match` on `room_id` for that id, whose
    /// actions include `dont_notify`, and whose expiry (if any) is still ahead.
    public static func mutedRoomIDs(fromPushRules data: Data, now: Date = Date()) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = (root["global"] as? [String: Any])?["override"] as? [[String: Any]] else { return [] }
        let nowMilliseconds = now.timeIntervalSince1970 * 1000
        var muted: Set<String> = []
        for rule in rules {
            guard let ruleID = rule["rule_id"] as? String, !ruleID.isEmpty,
                  (rule["enabled"] as? Bool) ?? true,
                  (rule["actions"] as? [Any])?.contains(where: { ($0 as? String) == "dont_notify" }) == true,
                  let conditions = rule["conditions"] as? [[String: Any]], conditions.count == 1,
                  conditions[0]["kind"] as? String == "event_match",
                  conditions[0]["key"] as? String == "room_id",
                  conditions[0]["pattern"] as? String == ruleID else { continue }
            if let expiry = (rule[expirationKey] as? NSNumber)?.doubleValue, expiry < nowMilliseconds { continue }
            muted.insert(ruleID)
        }
        return muted
    }

    /// Reads the homeserver's answer to a mute or unmute. Deleting a rule that
    /// is already gone (404) is the state asked for, so it is a success.
    public static func interpret(status: Int, data: Data, action: ChatMuteAction) throws {
        if status == 200 { return }
        if action == .unmute && status == 404 { return }
        try ChatRequests.interpret(status: status, data: data)
    }

    private static func send(_ request: URLRequest?, session: URLSession) async throws -> (Data, Int) {
        guard let request else { throw RedditChatClient.ChatError.httpError(status: 0) }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw RedditChatClient.ChatError.httpError(status: 0) }
        return (data, http.statusCode)
    }

    /// Mutes or unmutes a room. `bearer(forceMint)` supplies the token; a 401
    /// re-mints it once and sends again, which is safe because both calls are
    /// idempotent.
    public static func perform(
        _ action: ChatMuteAction,
        roomID: String,
        bearer: @Sendable (Bool) async throws -> String,
        session: URLSession = .shared
    ) async throws {
        func attempt(_ forceMint: Bool) async throws {
            let (data, status) = try await send(
                request(action, roomID: roomID, bearer: try await bearer(forceMint)), session: session)
            try interpret(status: status, data: data, action: action)
        }
        do { try await attempt(false) } catch RedditChatClient.ChatError.unauthorized { try await attempt(true) }
    }

    /// The rooms muted on the account, re-minting the token once on a 401.
    public static func fetchMutedRoomIDs(
        bearer: @Sendable (Bool) async throws -> String,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> Set<String> {
        func attempt(_ forceMint: Bool) async throws -> Set<String> {
            let (data, status) = try await send(rulesRequest(bearer: try await bearer(forceMint)), session: session)
            try ChatRequests.interpret(status: status, data: data)
            return mutedRoomIDs(fromPushRules: data, now: now)
        }
        do { return try await attempt(false) } catch RedditChatClient.ChatError.unauthorized { return try await attempt(true) }
    }

    /// The sentence shown when muting or unmuting fails.
    public static func failureMessage(for error: Error, action: ChatMuteAction) -> String {
        let verb = action.isMute ? "mute" : "unmute"
        switch error {
        case let error as ChatMuteError:
            return error.errorDescription ?? "Couldn't \(verb) the conversation."
        case RedditChatClient.ChatError.httpError(let status) where status == 0:
            return "Couldn't \(verb) the conversation. Check your connection and try again."
        case RedditChatClient.ChatError.httpError(let status) where status >= 500:
            return "Reddit Chat is having trouble. Couldn't \(verb) the conversation, try again in a moment."
        case RedditChatClient.ChatError.requestRejected(let status, let code):
            if status == 429 || code == "M_LIMIT_EXCEEDED" {
                return "Reddit is limiting Chat requests. Try to \(verb) the conversation again in a moment."
            }
            if status >= 500 {
                return "Reddit Chat is having trouble. Couldn't \(verb) the conversation, try again in a moment."
            }
            return "Reddit refused to \(verb) the conversation (HTTP \(status))."
        case RedditChatClient.ChatError.unauthorized, RedditChatClient.ChatError.mintFailed,
             RedditChatClient.ChatError.noWebSession:
            return (error as? LocalizedError)?.errorDescription ?? "Couldn't \(verb) the conversation."
        default:
            if error is URLError {
                return "Couldn't \(verb) the conversation. Check your connection and try again."
            }
            return "Couldn't \(verb) the conversation. \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }
}
