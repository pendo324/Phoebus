import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answering a Reddit Chat request.
///
/// A request is a Matrix room invite. Accepting joins the room and
/// declining leaves it, which for an invite is Matrix's way of rejecting
/// it. Both are idempotent on the homeserver (joining a joined room or
/// leaving a left one answers 200), so a request can be repeated after
/// a lost response. Apollo Reborn hosts Reddit's web chat and never
/// answers requests natively; this is Phoebus-only.
public enum ChatRequestAction: String, Sendable, Equatable {
    case accept
    case decline

    /// The Matrix endpoint segment for this answer.
    public var path: String { self == .accept ? "join" : "leave" }
}

public enum ChatRequestError: Error, LocalizedError, Equatable {
    /// The room is not a request waiting for an answer (already answered, or not an invite).
    case notPending
    /// The sender has no Reddit account id to block.
    case cannotBlock

    public var errorDescription: String? {
        switch self {
        case .notPending: return "That chat request has already been answered."
        case .cannotBlock: return "Couldn't tell who sent this request, so they can't be blocked."
        }
    }
}

public enum ChatRequests {
    /// Whether the composer may send into a room. A room still waiting as a
    /// request refuses messages from a user who has not joined, so the UI
    /// offers Accept in its place instead of a send that fails.
    public static func canReply(in room: ChatRoom) -> Bool {
        !room.isInvite
    }

    /// The Matrix user id of whoever sent the request: the inviter named in
    /// the invite, else the room's one other participant.
    public static func requester(of room: ChatRoom, selfUserID: String?) -> String? {
        room.inviter ?? room.otherParticipants(excluding: selfUserID).first
    }

    /// An invite to a subreddit's modmail conversation (for example a ban notice),
    /// which arrives in the same invite list as a person's chat request.
    public static func isModmail(_ room: ChatRoom) -> Bool {
        room.chatType == "reddit_modmail"
    }

    /// Whether Reddit's own request counter includes this invite. An account with
    /// one person's request and one modmail invite is reported as having 1.
    public static func countsAsRequest(_ room: ChatRoom) -> Bool {
        !isModmail(room)
    }

    /// Block is offered for a person who wrote to you, not for a subreddit's modmail.
    public static func canBlock(_ room: ChatRoom, selfUserID: String?) -> Bool {
        !isModmail(room) && requester(of: room, selfUserID: selfUserID).flatMap(blockFullname(forMatrixUserID:)) != nil
    }

    /// The Reddit fullname (`t2_...`) the account block API takes, for a Matrix user id.
    public static func blockFullname(forMatrixUserID userID: String) -> String? {
        guard let id = RedditChatClient.accountID(fromMatrixUserID: userID), id.hasPrefix("t2_") else { return nil }
        return id
    }

    /// How long a local answer keeps hiding a request the homeserver still
    /// lists, in seconds. A `/sync` already in flight when the answer is
    /// sent can still carry the old invite.
    public static let staleInviteShield: TimeInterval = 30

    /// The request for joining or leaving a room.
    public static func request(_ action: ChatRequestAction, roomID: String, bearer: String) -> URLRequest? {
        let room = RedditChatClient.pathSegment(roomID)
        guard let url = URL(string: RedditChatClient.homeserver
            + "/_matrix/client/v3/rooms/\(room)/\(action.path)") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{}".utf8)
        return request
    }

    /// Reads the homeserver's answer to a join or leave.
    ///
    /// 401 re-mints the bearer. A 403 or 404 that carries a Matrix error
    /// (the invite was withdrawn, or the room is gone) is the request's own
    /// rejection, not a dead token, and must not be retried as one.
    public static func interpret(status: Int, data: Data) throws {
        if status == 200 { return }
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let code = body?["errcode"] as? String
        if status == 401 { throw RedditChatClient.ChatError.unauthorized }
        if status == 403 && code == nil { throw RedditChatClient.ChatError.unauthorized }
        throw RedditChatClient.ChatError.requestRejected(status: status, errcode: code)
    }

    /// The sentence shown when answering a request fails.
    public static func failureMessage(for error: Error, action: ChatRequestAction) -> String {
        let verb = action == .accept ? "accept" : "decline"
        switch error {
        case let error as ChatRequestError:
            return error.errorDescription ?? "Couldn't \(verb) the request."
        case RedditChatClient.ChatError.httpError(let status) where status == 0:
            return "Couldn't \(verb) the request. Check your connection and try again."
        case RedditChatClient.ChatError.httpError(let status) where status >= 500:
            return "Reddit Chat is having trouble. Couldn't \(verb) the request, try again in a moment."
        case RedditChatClient.ChatError.requestRejected(let status, let code):
            if status == 429 || code == "M_LIMIT_EXCEEDED" {
                return "Reddit is limiting Chat requests. Try to \(verb) again in a moment."
            }
            if status == 403 || status == 404 || code == "M_FORBIDDEN" || code == "M_NOT_FOUND" {
                return "This request is no longer available. Pull to refresh the list."
            }
            return "Couldn't \(verb) the request (HTTP \(status))."
        case RedditChatClient.ChatError.unauthorized, RedditChatClient.ChatError.mintFailed,
             RedditChatClient.ChatError.noWebSession:
            return (error as? LocalizedError)?.errorDescription ?? "Couldn't \(verb) the request."
        default:
            if (error as? URLError) != nil {
                return "Couldn't \(verb) the request. Check your connection and try again."
            }
            return "Couldn't \(verb) the request. \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }
}

extension RedditChatClient {
    /// Joins (accepts) or leaves (declines) a room.
    public static func answerRequest(
        _ action: ChatRequestAction,
        roomID: String,
        bearer: String,
        session: URLSession = .shared
    ) async throws {
        guard let request = ChatRequests.request(action, roomID: roomID, bearer: bearer) else {
            throw ChatError.httpError(status: 0)
        }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { throw ChatError.httpError(status: 0) }
        try ChatRequests.interpret(status: http.statusCode, data: data)
    }
}
