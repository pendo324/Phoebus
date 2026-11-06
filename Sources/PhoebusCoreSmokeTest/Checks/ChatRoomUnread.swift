import Foundation
import PhoebusCore

/// A muted room shows the unread dot but feeds no badge or push. Fixture ids
/// and text are made up.
@MainActor func checkChatRoomUnread() async throws {
    func room(_ id: String, unread: Int, counts: Bool, invite: Bool = false) -> ChatRoom {
        ChatRoom(id: id, name: id, chatType: "direct", participants: [], isInvite: invite,
                 lastMessageTimestamp: 1000, preview: "hello", previewSender: nil,
                 notificationCount: unread, countsTowardGlobalBadge: counts)
    }
    let mutedUnread = room("!muted:fixture", unread: 1, counts: false)
    let loudUnread = room("!loud:fixture", unread: 2, counts: true)
    let mutedRead = room("!quiet:fixture", unread: 0, counts: false)
    let loudRead = room("!read:fixture", unread: 0, counts: true)
    let invite = room("!invite:fixture", unread: 1, counts: true, invite: true)

    check("chat unread: a muted room with unread messages shows the dot",
          ChatRoomUnread.isUnread(mutedUnread) && ChatRoomUnread.isMutedUnread(mutedUnread))
    check("chat unread: ...but does not count toward the badge",
          !ChatRoomUnread.countsTowardBadge(mutedUnread))
    check("chat unread: an unmuted unread room shows the dot and counts",
          ChatRoomUnread.isUnread(loudUnread) && ChatRoomUnread.countsTowardBadge(loudUnread)
            && !ChatRoomUnread.isMutedUnread(loudUnread))
    check("chat unread: a read room, muted or not, has neither",
          ![mutedRead, loudRead].contains { ChatRoomUnread.isUnread($0) || ChatRoomUnread.countsTowardBadge($0) })
    check("chat unread: a request is neither a dot nor a badge count",
          !ChatRoomUnread.isUnread(invite) && !ChatRoomUnread.countsTowardBadge(invite))

    let all = [mutedUnread, loudUnread, mutedRead, loudRead, invite]
    check("chat unread: the derived badge total leaves out muted rooms and requests",
          ChatRoomUnread.badgeTotal(of: all) == 2)
    check("chat unread: Unread Only lists exactly the rooms that show a dot",
          ChatMessagesFilterStore.apply(filter: .all, unreadOnly: true, to: all).map(\.id)
            == all.filter(ChatRoomUnread.isUnread).map(\.id)
            && ChatMessagesFilterStore.apply(filter: .all, unreadOnly: true, to: all).map(\.id)
            == ["!muted:fixture", "!loud:fixture"])

    // The shape Reddit sends for a muted room: one notification, no highlight,
    // not counted in the navigation counter.
    var state = ChatSyncState()
    state.apply(try ChatSyncDelta(parsing: Data(#"""
    {"next_batch":"s1","rooms":{"join":{
     "!muted:fixture":{"timeline":{"events":[{"type":"m.room.message","origin_server_ts":1000,"sender":"@bot:fixture","content":{"msgtype":"m.text","body":"hello"}}]},
       "unread_notifications":{"notification_count":1,"highlight_count":0,"com.reddit.is_counted_in_global_navigation_counter":false}},
     "!loud:fixture":{"timeline":{"events":[{"type":"m.room.message","origin_server_ts":2000,"sender":"@friend:fixture","content":{"msgtype":"m.text","body":"hi"}}]},
       "unread_notifications":{"notification_count":2,"highlight_count":1,"com.reddit.is_counted_in_global_navigation_counter":true}}}}}
    """#.utf8)), replacing: true)
    let parsedMuted = state.rooms["!muted:fixture"]
    let parsedLoud = state.rooms["!loud:fixture"]
    check("chat unread: a synced muted room reads as unread but not badged",
          parsedMuted.map { ChatRoomUnread.isUnread($0) && !ChatRoomUnread.countsTowardBadge($0) } == true)
    check("chat unread: a synced room with a highlight is unread and badged",
          parsedLoud.map { ChatRoomUnread.isUnread($0) && ChatRoomUnread.countsTowardBadge($0) } == true)
    check("chat unread: the sync's derived badge total excludes the muted room", state.unreadCount == 2)
    check("chat unread: the muted flag survives a later sync that carries no counts",
          {
              var next = state
              next.apply(try! ChatSyncDelta(parsing: Data(#"""
              {"next_batch":"s2","rooms":{"join":{"!muted:fixture":{"timeline":{"events":[
               {"type":"m.room.message","origin_server_ts":3000,"sender":"@bot:fixture","content":{"msgtype":"m.text","body":"again"}}]}}}}}
              """#.utf8)))
              return next.rooms["!muted:fixture"].map(ChatRoomUnread.isMutedUnread) == true && next.unreadCount == 2
          }())
}
