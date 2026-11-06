import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// Muting a chat room. Room ids, tokens and text are made up; nothing here touches a network.

private final class MuteStub: URLProtocol, @unchecked Sendable {
    struct Captured {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var captured: [Captured] = []
    /// One answer per request in order, the last repeated; nil fails the transport.
    nonisolated(unsafe) static var answers: [(status: Int, body: String)?] = [(200, "{}")]

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
        let index = Self.captured.count
        Self.captured.append(Captured(url: url, method: request.httpMethod ?? "GET",
                                      headers: request.allHTTPHeaderFields ?? [:], body: body))
        guard let answer = Self.answers[min(index, Self.answers.count - 1)] else {
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

private actor MintLog {
    var calls: [Bool] = []
    func record(_ forceMint: Bool) -> String {
        calls.append(forceMint)
        return forceMint ? "FRESH" : "OLD"
    }
}

/// The shape of Reddit's push rules: a mute of one room, a disabled mute, a timed mute that ended,
/// one that has not, a mentions-only mute, a rule of another kind, and a room-kind rule.
private let pushRulesFixture = """
{"global":{
 "override":[
  {"rule_id":"!muted:fixture","default":false,"enabled":true,"actions":["dont_notify"],
   "conditions":[{"kind":"event_match","key":"room_id","pattern":"!muted:fixture"}]},
  {"rule_id":"!off:fixture","default":false,"enabled":false,"actions":["dont_notify"],
   "conditions":[{"kind":"event_match","key":"room_id","pattern":"!off:fixture"}]},
  {"rule_id":"!ended:fixture","enabled":true,"actions":["dont_notify"],"com.reddit.expiration_ts":1000,
   "conditions":[{"kind":"event_match","key":"room_id","pattern":"!ended:fixture"}]},
  {"rule_id":"!timed:fixture","enabled":true,"actions":["dont_notify"],"com.reddit.expiration_ts":99999999999999,
   "conditions":[{"kind":"event_match","key":"room_id","pattern":"!timed:fixture"}]},
  {"rule_id":"!mentions:fixture_mentions","enabled":true,"actions":["dont_notify"],
   "conditions":[{"kind":"event_match","key":"room_id","pattern":"!mentions:fixture"},{"kind":"contains_display_name"}]},
  {"rule_id":"!loud:fixture","enabled":true,"actions":["notify"],
   "conditions":[{"kind":"event_match","key":"room_id","pattern":"!loud:fixture"}]},
  {"rule_id":".m.rule.master","default":true,"enabled":false,"actions":[],"conditions":[]}],
 "room":[{"rule_id":"!room-kind:fixture","enabled":true,"actions":["dont_notify"]}],
 "underride":[{"rule_id":"!under:fixture","enabled":true,"actions":["dont_notify"],
   "conditions":[{"kind":"event_match","key":"room_id","pattern":"!under:fixture"}]}]}}
"""

@MainActor func checkChatMute() async throws {
    func room(_ id: String, unread: Int = 0, counts: Bool = true, muted: Bool = false) -> ChatRoom {
        ChatRoom(id: id, name: id, chatType: "direct", participants: [], isInvite: false,
                 lastMessageTimestamp: 1000, preview: "hello", previewSender: nil,
                 notificationCount: unread, countsTowardGlobalBadge: counts, isMuted: muted)
    }

    // The requests.
    let put = ChatMute.request(.mute, roomID: "!muted:fixture", bearer: "TOKEN")
    let delete = ChatMute.request(.unmute, roomID: "!muted:fixture", bearer: "TOKEN")
    let ruleURL = "https://matrix.redditspace.com/_matrix/client/v3/pushrules/global/override/%21muted%3Afixture"
    check("chat mute: muting PUTs the override rule named by the room id, with the id escaped",
          put?.httpMethod == "PUT" && put?.url?.absoluteString == ruleURL)
    check("chat mute: the rule drops notifications for an event_match on the room id",
          put?.httpBody == Data(#"{"actions":["dont_notify"],"conditions":[{"key":"room_id","kind":"event_match","pattern":"!muted:fixture"}]}"#.utf8)
            && put?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    check("chat mute: unmuting DELETEs the same rule with no body",
          delete?.httpMethod == "DELETE" && delete?.url?.absoluteString == ruleURL && delete?.httpBody == nil)
    check("chat mute: both carry the bearer",
          put?.value(forHTTPHeaderField: "Authorization") == "Bearer TOKEN"
            && delete?.value(forHTTPHeaderField: "Authorization") == "Bearer TOKEN")
    check("chat mute: the push rules are read from /pushrules/",
          ChatMute.rulesRequest(bearer: "TOKEN")?.url?.absoluteString == "https://matrix.redditspace.com/_matrix/client/v3/pushrules/"
            && ChatMute.rulesRequest(bearer: "TOKEN")?.httpMethod == "GET")

    // Reading muted rooms from the rules.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let muted = ChatMute.mutedRoomIDs(fromPushRules: Data(pushRulesFixture.utf8), now: now)
    check("chat mute: an enabled dont_notify rule on the room is muted", muted.contains("!muted:fixture"))
    check("chat mute: a disabled rule is not muted", !muted.contains("!off:fixture"))
    check("chat mute: a timed mute is muted until it ends",
          muted.contains("!timed:fixture") && !muted.contains("!ended:fixture"))
    check("chat mute: a mentions-only rule, a notifying rule, another kind of rule and the server's own rules are not a muted room",
          muted == ["!muted:fixture", "!timed:fixture"])
    check("chat mute: garbage reads as nothing muted",
          ChatMute.mutedRoomIDs(fromPushRules: Data("[]".utf8)).isEmpty
            && ChatMute.mutedRoomIDs(fromPushRules: Data("{}".utf8)).isEmpty)
    check("chat mute: the rule Phoebus writes is read back as muted",
          ChatMute.mutedRoomIDs(fromPushRules: Data(
            (#"{"global":{"override":[{"rule_id":"!muted:fixture","enabled":true,"actions":["dont_notify"],"conditions":[{"key":"room_id","kind":"event_match","pattern":"!muted:fixture"}]}]}}"#).utf8)) == ["!muted:fixture"])

    // Answers.
    func outcome(_ status: Int, _ action: ChatMuteAction, _ body: String = "{}") -> Error? {
        do { try ChatMute.interpret(status: status, data: Data(body.utf8), action: action); return nil } catch { return error }
    }
    check("chat mute: a 200 is done", outcome(200, .mute) == nil && outcome(200, .unmute) == nil)
    check("chat mute: unmuting a room that is not muted is already done",
          outcome(404, .unmute, #"{"errcode":"M_NOT_FOUND"}"#) == nil)
    check("chat mute: muting that answers 404 is a rejection",
          outcome(404, .mute, #"{"errcode":"M_NOT_FOUND"}"#) as? RedditChatClient.ChatError
            == .requestRejected(status: 404, errcode: "M_NOT_FOUND"))
    check("chat mute: a 401 asks for a fresh bearer",
          outcome(401, .mute, #"{"errcode":"M_UNKNOWN_TOKEN"}"#) as? RedditChatClient.ChatError == .unauthorized)

    // Through a stubbed transport.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MuteStub.self]
    let session = URLSession(configuration: configuration)
    let mints = MintLog()

    MuteStub.captured = []
    MuteStub.answers = [(200, "{}")]
    try await ChatMute.perform(.mute, roomID: "!muted:fixture", bearer: { await mints.record($0) }, session: session)
    try await ChatMute.perform(.unmute, roomID: "!muted:fixture", bearer: { await mints.record($0) }, session: session)
    check("chat mute: mute then unmute send a PUT then a DELETE to the rule with the bearer",
          MuteStub.captured.map(\.method) == ["PUT", "DELETE"]
            && MuteStub.captured.allSatisfy { $0.url.absoluteString == ruleURL && $0.headers["Authorization"] == "Bearer OLD" }
            && MuteStub.captured.first?.body == put?.httpBody)

    MuteStub.captured = []
    MuteStub.answers = [(401, #"{"errcode":"M_UNKNOWN_TOKEN"}"#), (200, "{}")]
    try await ChatMute.perform(.mute, roomID: "!muted:fixture", bearer: { await mints.record($0) }, session: session)
    let mintCalls = await mints.calls
    check("chat mute: a 401 re-mints the bearer and sends again once",
          MuteStub.captured.count == 2
            && MuteStub.captured.map { $0.headers["Authorization"] } == ["Bearer OLD", "Bearer FRESH"]
            && mintCalls.suffix(2) == [false, true])

    MuteStub.captured = []
    MuteStub.answers = [(401, "{}")]
    var dead: Error?
    do { try await ChatMute.perform(.mute, roomID: "!muted:fixture", bearer: { await mints.record($0) }, session: session) }
    catch { dead = error }
    check("chat mute: a token that is refused twice stops after one retry",
          dead as? RedditChatClient.ChatError == .unauthorized && MuteStub.captured.count == 2)

    func failure(_ answer: (status: Int, body: String)?, _ action: ChatMuteAction = .mute) async -> String? {
        MuteStub.answers = [answer]
        do { try await ChatMute.perform(action, roomID: "!muted:fixture", bearer: { _ in "T" }, session: session); return nil }
        catch { return ChatMute.failureMessage(for: error, action: action) }
    }
    let offlineMute = await failure(nil), offlineUnmute = await failure(nil, .unmute)
    let limited = await failure((429, #"{"errcode":"M_LIMIT_EXCEEDED"}"#))
    let broken = await failure((503, "<html>")), refused = await failure((403, #"{"errcode":"M_FORBIDDEN"}"#))
    check("chat mute: offline says to check the connection and names the action",
          offlineMute?.contains("connection") == true && offlineMute?.contains("mute") == true
            && offlineUnmute?.contains("unmute") == true)
    check("chat mute: a rate limit says to wait", limited?.contains("moment") == true)
    check("chat mute: a server error is not blamed on the user", broken?.contains("trouble") == true)
    check("chat mute: a refusal says Reddit refused", refused?.contains("refused") == true)

    MuteStub.captured = []
    MuteStub.answers = [(200, pushRulesFixture)]
    let fetched = try await ChatMute.fetchMutedRoomIDs(bearer: { _ in "T" }, session: session, now: now)
    check("chat mute: the rules are fetched with a GET and read", fetched == ["!muted:fixture", "!timed:fixture"]
          && MuteStub.captured.first?.method == "GET")
    MuteStub.answers = [(401, "{}"), (200, pushRulesFixture)]
    let refetched = try await ChatMute.fetchMutedRoomIDs(bearer: { await mints.record($0) }, session: session, now: now)
    check("chat mute: reading the rules re-mints once on a 401", refetched.count == 2)

    // State: the change shows at once, moves the badge, rolls back, and a stale sync does not undo it.
    func syncing(_ json: String) -> ChatSyncDelta { try! ChatSyncDelta(parsing: Data(json.utf8)) }
    func message(_ ts: Int, _ text: String) -> String {
        #"{"type":"m.room.message","origin_server_ts":\#(ts),"sender":"@x:fixture","content":{"msgtype":"m.text","body":"\#(text)"}}"#
    }
    let initial = """
    {"next_batch":"s1","rooms":{"join":{
     "!a:fixture":{"timeline":{"events":[\(message(1000, "one"))]},
       "unread_notifications":{"notification_count":3,"com.reddit.is_counted_in_global_navigation_counter":true}},
     "!b:fixture":{"timeline":{"events":[\(message(2000, "two"))]},
       "unread_notifications":{"notification_count":2,"com.reddit.is_counted_in_global_navigation_counter":true}}}}}
    """
    var state = ChatSyncState()
    state.apply(syncing(initial), replacing: true)
    check("chat mute: a synced account starts with both rooms counted", state.unreadCount == 5)
    state.applyMutedRules(["!b:fixture"])
    check("chat mute: the push rules mark a room muted and it leaves the derived total",
          state.rooms["!b:fixture"]?.isMuted == true && state.rooms["!a:fixture"]?.isMuted == false
            && ChatRoomUnread.badgeTotal(of: Array(state.rooms.values)) == 3)

    let a = state.rooms["!a:fixture"]!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    check("chat mute: muting an unread room starts the change", state.beginMute(.mute, room: a, now: t0) == .started)
    check("chat mute: ...which shows at once and takes the room out of the badge",
          state.rooms["!a:fixture"]?.isMuted == true && state.rooms["!a:fixture"].map(ChatRoomUnread.countsTowardBadge) == false
            && state.rooms["!a:fixture"].map(ChatRoomUnread.isUnread) == true && state.unreadCount == 2)
    check("chat mute: a second change to the room while one is in flight is refused",
          state.beginMute(.unmute, room: state.rooms["!a:fixture"]!, now: t0) == .busy)
    state.rollbackMute(roomID: "!a:fixture")
    check("chat mute: a failed mute puts the room and the badge back",
          state.rooms["!a:fixture"]?.isMuted == false && state.rooms["!a:fixture"]?.countsTowardGlobalBadge == true
            && state.unreadCount == 5 && !state.mutedRoomIDs.contains("!a:fixture"))

    state.applyMutedRules([])
    _ = state.beginMute(.mute, room: state.rooms["!a:fixture"]!, now: t0)
    state.settleMute(roomID: "!a:fixture", now: t0)
    let staleCounted = """
    {"next_batch":"s2","com.reddit.global_navigation_counter":5,"rooms":{"join":{"!a:fixture":{
      "unread_notifications":{"notification_count":3,"com.reddit.is_counted_in_global_navigation_counter":true}}}}}
    """
    state.apply(syncing(staleCounted), now: t0.addingTimeInterval(5))
    check("chat mute: a sync that still counts the room, and Reddit's old counter, do not undo the mute",
          state.rooms["!a:fixture"]?.isMuted == true && state.rooms["!a:fixture"]?.countsTowardGlobalBadge == false
            && state.unreadCount == 2)
    state.apply(syncing(staleCounted), now: t0.addingTimeInterval(ChatMute.staleShield + 1))
    check("chat mute: once Reddit has had its time, its own flag and counter decide",
          state.rooms["!a:fixture"]?.countsTowardGlobalBadge == true && state.unreadCount == 5
            && state.rooms["!a:fixture"]?.isMuted == true)

    var flipping = ChatSyncState()
    flipping.apply(syncing(initial), replacing: true)
    _ = flipping.beginMute(.mute, room: flipping.rooms["!a:fixture"]!, now: t0)
    flipping.settleMute(roomID: "!a:fixture", now: t0)
    flipping.confirmMute(server: room("!a:fixture", unread: 3, counts: false), now: t0.addingTimeInterval(2))
    flipping.apply(syncing(#"{"next_batch":"s3","com.reddit.global_navigation_counter":2,"rooms":{"join":{"!a:fixture":{"unread_notifications":{"notification_count":3,"com.reddit.is_counted_in_global_navigation_counter":false}}}}}"#),
                   now: t0.addingTimeInterval(3))
    check("chat mute: when Reddit's flag follows the rule the local override ends and Reddit's counter is used",
          flipping.rooms["!a:fixture"]?.isMuted == true && flipping.rooms["!a:fixture"]?.countsTowardGlobalBadge == false
            && flipping.unreadCount == 2)

    // Unmuting a room that has unread messages starts counting it.
    var unmuting = ChatSyncState()
    unmuting.apply(syncing(initial), replacing: true)
    unmuting.applyMutedRules(["!b:fixture"])
    unmuting.apply(syncing(#"{"next_batch":"s2","com.reddit.global_navigation_counter":3,"rooms":{"join":{"!b:fixture":{"unread_notifications":{"notification_count":2,"com.reddit.is_counted_in_global_navigation_counter":false}}}}}"#))
    check("chat mute: a muted room Reddit leaves out of its counter starts out uncounted", unmuting.unreadCount == 3)
    check("chat mute: unmuting starts the change", unmuting.beginMute(.unmute, room: unmuting.rooms["!b:fixture"]!, now: t0) == .started)
    check("chat mute: ...and the room counts toward the badge again at once, as the total",
          unmuting.rooms["!b:fixture"]?.isMuted == false && unmuting.rooms["!b:fixture"].map(ChatRoomUnread.countsTowardBadge) == true
            && unmuting.unreadCount == 5)
    check("chat mute: a request, or a room not yet unmuted, cannot be changed to what it already is",
          unmuting.beginMute(.unmute, room: room("!c:fixture"), now: t0) == .unchanged
            && unmuting.beginMute(.mute, room: room("!i:fixture").withInvite(true), now: t0) == .notJoined)
    unmuting.rollbackMute(roomID: "!b:fixture")
    check("chat mute: a failed unmute leaves it muted and uncounted",
          unmuting.rooms["!b:fixture"]?.isMuted == true && unmuting.unreadCount == 3)

    check("chat mute: a fetched room list carries the mute state and the local total",
          {
              var local = ChatSyncState()
              local.apply(syncing(initial), replacing: true)
              _ = local.beginMute(.mute, room: local.rooms["!a:fixture"]!, now: t0)
              let fetched = try! RedditChatClient.parseSync(Data("""
              {"next_batch":"s9","com.reddit.global_navigation_counter":5,"rooms":{"join":{
               "!a:fixture":{"unread_notifications":{"notification_count":3,"com.reddit.is_counted_in_global_navigation_counter":true}},
               "!b:fixture":{"unread_notifications":{"notification_count":2,"com.reddit.is_counted_in_global_navigation_counter":true}}}}}
              """.utf8))
              let list = local.reconciled(fetched, now: t0.addingTimeInterval(1))
              return list.rooms.first { $0.id == "!a:fixture" }?.isMuted == true && list.unreadCount == 2
          }())

    // The engine's flow.
    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt",
                                          expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let auth = RedditAuthClient(session: session, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    let engine = ChatLiveSync(repository: RedditRepository(client: RedditAPIClient(auth: auth, session: session)))
    let updates = await engine.updates()
    var seen = updates.makeAsyncIterator()
    let target = room("!a:fixture", unread: 3)

    struct Offline: Error {}
    var thrown: Error?
    do { try await engine.setMuted(true, room: target) { throw Offline() } } catch { thrown = error }
    check("chat mute: a failed change reaches the caller", thrown is Offline)
    var latest: ChatLiveSync.Update?
    while let update = await seen.next() {
        latest = update
        if update.snapshot.rooms.first(where: { $0.id == "!a:fixture" })?.isMuted == false { break }
    }
    check("chat mute: ...after the room is back as it was, and the change was published as local",
          latest?.snapshot.rooms.first { $0.id == "!a:fixture" }?.isMuted == false && latest?.isLocalChange == true)

    try await engine.setMuted(true, room: target) {}
    var afterMute: ChatLiveSync.Update?
    while let update = await seen.next() {
        afterMute = update
        if update.snapshot.rooms.first(where: { $0.id == "!a:fixture" })?.isMuted == true { break }
    }
    check("chat mute: muting publishes the muted room and the lower badge to every subscriber",
          afterMute?.snapshot.rooms.first { $0.id == "!a:fixture" }?.isMuted == true && afterMute?.snapshot.unreadCount == 0)

    // Reddit's sync and push rules agree on what is muted.
    check("chat mute: muted and unread are what VoiceOver says",
          ChatRoomUnread.accessibilityStatus(room("!m", unread: 1, muted: true)) == "Muted, unread"
            && ChatRoomUnread.accessibilityStatus(room("!m", muted: true)) == "Muted"
            && ChatRoomUnread.accessibilityStatus(room("!m", unread: 1)) == "Unread"
            && ChatRoomUnread.accessibilityStatus(room("!m")) == nil)
    check("chat mute: the indicator follows the rule; the grey dot follows the rule or Reddit's flag",
          ChatRoomUnread.showsMutedIndicator(room("!m", muted: true))
            && !ChatRoomUnread.showsMutedIndicator(room("!m", unread: 1, counts: false))
            && ChatRoomUnread.isMutedUnread(room("!m", unread: 1, counts: false))
            && ChatRoomUnread.isMutedUnread(room("!m", unread: 1, counts: true, muted: true))
            && !ChatRoomUnread.countsTowardBadge(room("!m", unread: 1, counts: true, muted: true)))
}
