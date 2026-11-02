import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Answering Reddit Chat requests
//
// The sync fixture has the shape of a Matrix /sync response with identifiers,
// usernames and message text replaced.

private final class ChatRequestStub: URLProtocol, @unchecked Sendable {
    struct Captured {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var captured: [Captured] = []
    /// The status and body to answer with; nil fails the transport, as being offline does.
    nonisolated(unsafe) static var answer: (status: Int, body: String)? = (200, "{}")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        Self.captured.append(Captured(url: url, method: request.httpMethod ?? "GET",
                                      headers: request.allHTTPHeaderFields ?? [:], body: body))
        guard let answer = Self.answer else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil,
                                                              headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// The invites have the shape Reddit sends: no timeline, a stripped state that holds the
// inviter's own join and the invite event twice, and one invite to a subreddit's modmail
// that Reddit's counter leaves out.
private let requestsSyncFixture = """
{"next_batch":"s_FIXTURE_REQ","com.reddit.global_navigation_counter":0,"com.reddit.invites_counter":1,
 "rooms":{
  "join":{"!joined:fixture":{
    "state":{"events":[{"type":"com.reddit.chat.type","content":{"type":"direct","participants":["@t2_me:reddit.com","@t2_friend:reddit.com"]}}]},
    "timeline":{"events":[{"type":"m.room.message","sender":"@t2_friend:reddit.com","origin_server_ts":1700000000000,"content":{"body":"message 0","msgtype":"m.text"}}]},
    "unread_notifications":{"notification_count":0}}},
  "invite":{
   "!req1:fixture":{"com.reddit.is_counted_in_global_navigation_counter":0,
    "invite_state":{"events":[
      {"type":"m.room.create","sender":"@t2_sender1:reddit.com","state_key":"","content":{"creator":"@t2_sender1:reddit.com"}},
      {"type":"m.room.member","sender":"@t2_sender1:reddit.com","state_key":"@t2_sender1:reddit.com","content":{"displayname":"sender1","membership":"join"}},
      {"type":"m.room.join_rules","sender":"@t2_sender1:reddit.com","state_key":"","content":{"join_rule":"invite"}},
      {"type":"m.room.member","sender":"@t2_sender1:reddit.com","state_key":"@t2_me:reddit.com","content":{"displayname":"me","is_direct":true,"membership":"invite"}},
      {"type":"m.room.member","sender":"@t2_sender1:reddit.com","state_key":"@t2_me:reddit.com","content":{"displayname":"me","is_direct":true,"membership":"invite"}}]}},
   "!req2:fixture":{"com.reddit.is_counted_in_global_navigation_counter":0,
    "invite_state":{"events":[
      {"type":"m.room.create","sender":"@t2_sender2:reddit.com","state_key":"","content":{"creator":"@t2_sender2:reddit.com"}},
      {"type":"m.room.name","sender":"@t2_sender2:reddit.com","state_key":"","content":{"name":"Notice from r/example"}},
      {"type":"m.room.join_rules","sender":"@t2_sender2:reddit.com","state_key":"","content":{"join_rule":"invite"}},
      {"type":"m.room.member","sender":"@t2_sender2:reddit.com","state_key":"@t2_sender2:reddit.com","content":{"displayname":"sender2","membership":"join"}},
      {"type":"com.reddit.chat.type","sender":"@t2_sender2:reddit.com","state_key":"","content":{"type":"reddit_modmail"}},
      {"type":"m.room.member","sender":"@t2_sender2:reddit.com","state_key":"@t2_me:reddit.com","content":{"displayname":"me","membership":"invite"}},
      {"type":"m.room.member","sender":"@t2_sender2:reddit.com","state_key":"@t2_me:reddit.com","content":{"displayname":"me","membership":"invite"}}]}}}}}
"""

private func requestsDelta(_ json: String) -> ChatSyncDelta {
    try! ChatSyncDelta(parsing: Data(json.utf8))
}

@MainActor func checkChatRequests() async throws {
    let sync = try! RedditChatClient.parseSync(Data(requestsSyncFixture.utf8))
    let requests = sync.rooms.filter(\.isInvite)
    let first = requests.first { $0.id == "!req1:fixture" }
    let second = requests.first { $0.id == "!req2:fixture" }

    check("requests with no message keep a fixed order, so a request does not move between refreshes",
          requests.map(\.id) == ["!req1:fixture", "!req2:fixture"]
            && ChatRoom.newestFirst(first!, second!) && !ChatRoom.newestFirst(second!, first!))

    // Reading a request.
    check("both pending invites are read, and Reddit's own count is kept (it leaves the modmail one out)",
          requests.count == 2 && sync.requestsCount == 1)
    check("a request names who sent the invite",
          first?.inviter == "@t2_sender1:reddit.com" && second?.inviter == "@t2_sender2:reddit.com")
    check("an invite carries no message, so a request has no preview",
          first?.preview == nil && second?.preview == nil && first?.lastMessageTimestamp == 0)
    check("the inviter is the one who sent the invite, even with the invite event listed twice",
          first?.participants == ["@t2_me:reddit.com", "@t2_sender1:reddit.com"])
    check("a subreddit's modmail invite is told from a person's request",
          second.map(ChatRequests.isModmail) == true && first.map(ChatRequests.isModmail) == false
            && second.map(ChatRequests.countsAsRequest) == false && first.map(ChatRequests.countsAsRequest) == true)
    check("Block is offered for a person and not for modmail",
          ChatRequests.canBlock(first!, selfUserID: "@t2_me:reddit.com")
            && !ChatRequests.canBlock(second!, selfUserID: "@t2_me:reddit.com"))
    check("a joined room has no inviter", sync.rooms.first { !$0.isInvite }?.inviter == nil)
    check("the requester is the inviter",
          ChatRequests.requester(of: first!, selfUserID: "@t2_me:reddit.com") == "@t2_sender1:reddit.com")
    check("...or the one other participant when the invite names nobody",
          ChatRequests.requester(of: first!.withInvite(true).replacingInviter(nil), selfUserID: "@t2_me:reddit.com")
            == "@t2_sender1:reddit.com")
    check("a request cannot be replied to until it is accepted",
          !ChatRequests.canReply(in: first!) && ChatRequests.canReply(in: first!.withInvite(false)))
    check("the sender's Reddit account id is what a block needs",
          ChatRequests.blockFullname(forMatrixUserID: "@t2_sender1:reddit.com") == "t2_sender1"
            && ChatRequests.blockFullname(forMatrixUserID: "@someone:elsewhere.org") == nil
            && ChatRequests.blockFullname(forMatrixUserID: "garbage") == nil)

    // Request construction.
    let join = ChatRequests.request(.accept, roomID: "!req1:fixture", bearer: "TOKEN")
    let leave = ChatRequests.request(.decline, roomID: "!req1:fixture", bearer: "TOKEN")
    check("accepting POSTs to the room's join endpoint with the room id escaped",
          join?.httpMethod == "POST"
            && join?.url?.absoluteString == "https://matrix.redditspace.com/_matrix/client/v3/rooms/%21req1%3Afixture/join")
    check("declining POSTs to the room's leave endpoint",
          leave?.httpMethod == "POST"
            && leave?.url?.absoluteString == "https://matrix.redditspace.com/_matrix/client/v3/rooms/%21req1%3Afixture/leave")
    check("both carry the bearer and an empty JSON body",
          join?.value(forHTTPHeaderField: "Authorization") == "Bearer TOKEN"
            && join?.httpBody == Data("{}".utf8) && leave?.httpBody == Data("{}".utf8))

    // Response handling.
    func outcome(_ status: Int, _ body: String = "{}") -> Error? {
        do { try ChatRequests.interpret(status: status, data: Data(body.utf8)); return nil } catch { return error }
    }
    check("a 200 is an accepted answer", outcome(200) == nil)
    check("a 401 asks for a fresh bearer",
          outcome(401, #"{"errcode":"M_UNKNOWN_TOKEN"}"#) as? RedditChatClient.ChatError == .unauthorized)
    check("a 403 with no Matrix error is a dead bearer too",
          outcome(403, "") as? RedditChatClient.ChatError == .unauthorized)
    check("a 403 with a Matrix error is the request's own rejection",
          outcome(403, #"{"errcode":"M_FORBIDDEN","error":"x"}"#) as? RedditChatClient.ChatError
            == .requestRejected(status: 403, errcode: "M_FORBIDDEN"))
    check("other failures keep their status",
          outcome(429, #"{"errcode":"M_LIMIT_EXCEEDED"}"#) as? RedditChatClient.ChatError
            == .requestRejected(status: 429, errcode: "M_LIMIT_EXCEEDED")
            && outcome(502, "<html>") as? RedditChatClient.ChatError == .requestRejected(status: 502, errcode: nil))

    // Through a stubbed transport.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ChatRequestStub.self]
    let session = URLSession(configuration: configuration)
    ChatRequestStub.captured = []
    ChatRequestStub.answer = (200, #"{"room_id":"!req1:fixture"}"#)
    try await RedditChatClient.answerRequest(.accept, roomID: "!req1:fixture", bearer: "TOKEN", session: session)
    try await RedditChatClient.answerRequest(.decline, roomID: "!req2:fixture", bearer: "TOKEN", session: session)
    check("accept and decline each send one request",
          ChatRequestStub.captured.map(\.method) == ["POST", "POST"]
            && ChatRequestStub.captured.first?.url.path.hasSuffix("/join") == true
            && ChatRequestStub.captured.last?.url.path.hasSuffix("/leave") == true
            && ChatRequestStub.captured.first?.headers["Authorization"] == "Bearer TOKEN")
    ChatRequestStub.answer = (403, #"{"errcode":"M_FORBIDDEN","error":"You are not invited to this room."}"#)
    var rejection: Error?
    do { try await RedditChatClient.answerRequest(.accept, roomID: "!req1:fixture", bearer: "TOKEN", session: session) }
    catch { rejection = error }
    check("a withdrawn invite is reported, not swallowed",
          rejection as? RedditChatClient.ChatError == .requestRejected(status: 403, errcode: "M_FORBIDDEN"))
    ChatRequestStub.answer = nil
    var offline: Error?
    do { try await RedditChatClient.answerRequest(.accept, roomID: "!req1:fixture", bearer: "TOKEN", session: session) }
    catch { offline = error }
    check("no connection is a transport failure", offline as? RedditChatClient.ChatError == .httpError(status: 0))

    // Messages for the user.
    func message(_ error: Error, _ action: ChatRequestAction = .accept) -> String {
        ChatRequests.failureMessage(for: error, action: action)
    }
    check("offline says to check the connection and names the action",
          message(RedditChatClient.ChatError.httpError(status: 0)).contains("connection")
            && message(RedditChatClient.ChatError.httpError(status: 0)).contains("accept")
            && message(RedditChatClient.ChatError.httpError(status: 0), .decline).contains("decline"))
    check("a withdrawn invite says the request is gone",
          message(RedditChatClient.ChatError.requestRejected(status: 403, errcode: "M_FORBIDDEN")).contains("no longer available"))
    check("a rate limit says to wait",
          message(RedditChatClient.ChatError.requestRejected(status: 429, errcode: "M_LIMIT_EXCEEDED")).contains("moment"))
    check("a server error is not blamed on the user",
          message(RedditChatClient.ChatError.httpError(status: 503)).contains("trouble"))
    check("a missing web session explains how to sign in",
          message(RedditChatClient.ChatError.noWebSession).contains("web session"))
    check("a second answer to the same request is explained",
          message(ChatRequestError.notPending).contains("already been answered"))

    // Request state: invite vs joined, optimistic transitions, rollback.
    var state = ChatSyncState()
    state.apply(requestsDelta(requestsSyncFixture), replacing: true)
    check("a synced account starts with Reddit's count and both invites listed",
          state.requestsCount == 1 && state.rooms.count == 3)
    check("a joined room cannot be answered as a request",
          !state.beginRequest(.accept, room: state.rooms["!joined:fixture"]!))
    check("accepting turns the request into a joined room at once",
          state.beginRequest(.accept, room: first!)
            && state.rooms["!req1:fixture"]?.isInvite == false && state.requestsCount == 0)
    check("...which keeps who it is from",
          state.rooms["!req1:fixture"]?.inviter == "@t2_sender1:reddit.com")
    check("a request already being answered cannot be answered again",
          !state.beginRequest(.decline, room: first!))
    check("declining a modmail invite removes it and leaves the count alone, as Reddit's does not include it",
          state.beginRequest(.decline, room: second!)
            && state.rooms["!req2:fixture"] == nil && state.requestsCount == 0)
    state.rollbackRequest(roomID: "!req2:fixture")
    check("...and a failed decline puts it back without raising the count",
          state.rooms["!req2:fixture"]?.isInvite == true && state.requestsCount == 0)
    state.rollbackRequest(roomID: "!req1:fixture")
    check("a failed accept makes a person's request a request again and restores the count",
          state.rooms["!req1:fixture"]?.isInvite == true && state.requestsCount == 1)
    state.rollbackRequest(roomID: "!req1:fixture")
    check("rolling back twice changes nothing", state.requestsCount == 1)

    // A sync that began before the answer must not undo it.
    let staleInvite = """
    {"next_batch":"s2","com.reddit.invites_counter":1,"rooms":{"invite":{"!req1:fixture":{"invite_state":{"events":[
      {"type":"m.room.member","sender":"@t2_sender1:reddit.com","state_key":"@t2_me:reddit.com","content":{"membership":"invite"}}]}}}}}
    """
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    _ = state.beginRequest(.accept, room: first!)
    state.apply(requestsDelta(staleInvite), now: t0)
    check("a stale invite does not bring an answered request back, nor Reddit's old counter",
          state.rooms["!req1:fixture"]?.isInvite == false && state.requestsCount == 0)
    state.settleRequest(roomID: "!req1:fixture", now: t0)
    state.apply(requestsDelta(staleInvite), now: t0.addingTimeInterval(10))
    check("...including after the homeserver took the answer",
          state.rooms["!req1:fixture"]?.isInvite == false)
    let reconciled = state.reconciled(sync, now: t0.addingTimeInterval(10))
    check("a freshly fetched list shows the local answer too",
          reconciled.rooms.first { $0.id == "!req1:fixture" }?.isInvite == false && reconciled.requestsCount == 0)
    let joined = """
    {"next_batch":"s3","rooms":{"join":{"!req1:fixture":{"timeline":{"events":[
      {"type":"m.room.message","sender":"@t2_sender1:reddit.com","origin_server_ts":1700000009000,"content":{"body":"later"}}]}}}}}
    """
    state.apply(requestsDelta(joined), now: t0.addingTimeInterval(11))
    check("the sync that reports the join ends the override",
          state.rooms["!req1:fixture"]?.isInvite == false && state.rooms["!req1:fixture"]?.preview == "later"
            && state.reconciled(sync, now: t0.addingTimeInterval(11)).rooms.first { $0.id == "!req1:fixture" }?.isInvite == true)
    state.apply(requestsDelta(staleInvite), now: t0.addingTimeInterval(12))
    check("a new invite to the same room after that is honoured",
          state.rooms["!req1:fixture"]?.isInvite == true)

    var lapsing = ChatSyncState()
    lapsing.apply(requestsDelta(requestsSyncFixture), replacing: true)
    _ = lapsing.beginRequest(.decline, room: second!)
    lapsing.settleRequest(roomID: "!req2:fixture", now: t0)
    let secondInvite = """
    {"next_batch":"s4","rooms":{"invite":{"!req2:fixture":{"invite_state":{"events":[{"type":"m.room.name","content":{"name":"Group chat"}}]}}}}}
    """
    lapsing.apply(requestsDelta(secondInvite), now: t0.addingTimeInterval(5))
    check("a declined request stays gone while a stale sync arrives", lapsing.rooms["!req2:fixture"] == nil)
    lapsing.apply(requestsDelta(secondInvite), now: t0.addingTimeInterval(ChatRequests.staleInviteShield + 1))
    check("...but not forever, so a real re-invite shows", lapsing.rooms["!req2:fixture"]?.isInvite == true)

    var leaving = ChatSyncState()
    leaving.apply(requestsDelta(requestsSyncFixture), replacing: true)
    _ = leaving.beginRequest(.decline, room: second!)
    leaving.apply(requestsDelta(#"{"next_batch":"s5","rooms":{"leave":{"!req2:fixture":{}}}}"#), now: t0)
    leaving.apply(requestsDelta(secondInvite), now: t0)
    check("the sync that reports the leave ends the override", leaving.rooms["!req2:fixture"]?.isInvite == true)

    // The flow the engine runs.
    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt",
                                          expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let auth = RedditAuthClient(session: session, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    let engine = ChatLiveSync(repository: RedditRepository(client: RedditAPIClient(auth: auth, session: session)))
    let updates = await engine.updates()
    var seen = updates.makeAsyncIterator()

    struct Offline: Error {}
    var failure: Error?
    do { try await engine.answerRequest(.decline, room: first!) { throw Offline() } } catch { failure = error }
    check("a failed answer reaches the caller", failure is Offline)
    var latest: ChatLiveSync.Update?
    while let update = await seen.next() {
        latest = update
        if update.snapshot.rooms.contains(where: { $0.id == "!req1:fixture" && $0.isInvite }) { break }
    }
    check("...after the request is back in the list and counted",
          latest?.snapshot.rooms.first { $0.id == "!req1:fixture" }?.isInvite == true && latest?.snapshot.requestsCount == 1)

    try await engine.answerRequest(.accept, room: first!) {}
    let afterAccept = await seen.next()
    check("accepting publishes the joined room and the lower count to every subscriber",
          afterAccept?.snapshot.rooms.first { $0.id == "!req1:fixture" }?.isInvite == false
            && afterAccept?.snapshot.requestsCount == 0)

    var repeated: Error?
    do { try await engine.answerRequest(.accept, room: first!.withInvite(false)) {} } catch { repeated = error }
    check("answering a room that is not a request is refused without sending",
          repeated as? ChatRequestError == .notPending)
}

private extension ChatRoom {
    func replacingInviter(_ inviter: String?) -> ChatRoom {
        ChatRoom(id: id, name: name, chatType: chatType, participants: participants, isInvite: isInvite,
                 lastMessageTimestamp: lastMessageTimestamp, preview: preview, previewSender: previewSender,
                 notificationCount: notificationCount, countsTowardGlobalBadge: countsTowardGlobalBadge,
                 inviter: inviter)
    }
}
