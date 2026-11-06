# Reddit Chat: transport, sending and threads

How Phoebus talks to Reddit Chat, what the homeserver does and does not
support, and why sending is built the way it is. The behaviours below
are what Reddit's homeserver does today, observed against a live
account; Reddit can change them at any time.

## 1. Two separate messaging systems

Reddit has two unrelated messaging systems, and Phoebus uses both:

| | Private messages (Apollo's "Direct Chat") | Reddit Chat |
|---|---|---|
| Transport | Reddit API (`/api/comment`, `/api/compose`) | Matrix (`matrix.redditspace.com`) |
| Thing type | `t4` private messages | Matrix rooms and events |
| Phoebus code | `RedditRepository` inbox and compose methods | `RedditChatClient`, `RedditRepository+Chat`, `ChatListScreen` |

The two inboxes do not overlap: the `t4` messages box
(`/message/messages.json`) can be empty while Matrix `/sync` returns
live conversations. A reply to a `t1` comment-reply or a `t4` private
message goes through the Reddit API; a Reddit Chat message goes to a
Matrix room.

Apollo Reborn does not send Reddit Chat messages natively: it hosts
Reddit's own web chat in a web view, which owns the composer. A native
Matrix send is therefore new work in Phoebus, not a port.

## 2. Credentials and sync

- Reddit Chat needs a **web session** (cookie sign-in), not just an
  OAuth account. `WebSessionCredential` holds the cookies.
- The session's `token_v2` cookie value works directly as a Bearer
  token against the homeserver. `RedditChatClient.mintBearer` obtains a
  fresh one by presenting the session cookies *minus* `token_v2` to
  `https://www.reddit.com/chat/`, because Reddit re-issues the cookie to
  a session that presents none (a stored token just echoes back,
  expired). In the app the request is made through an offscreen web
  view (`browserMinter`), since Reddit only re-issues the cookie to a
  browser. `storedBearer` and `isExpired` reuse a still-valid token.
- A 401 re-mints the bearer and retries once.
- `sync` / `liveSync` read `/_matrix/client/v3/sync`; `ChatLiveSync`
  keeps one long-poll sync in flight while the app is open and merges
  room, typing and receipt state for every subscriber (the badge, Bark
  notifications, the chat list and open rooms).
- Reddit's homeserver is Matrix-shaped rather than standard. Its login
  flow is the proprietary `com.reddit.token`, `/refresh` does not exist,
  and the spec level and room version are old, so Phoebus implements the
  handful of endpoints it needs over plain HTTP and JSON instead of
  using a Matrix SDK (see section 5). Reddit extensions such as
  `com.reddit.chat.type`, `com.reddit.profile` and the
  `com.reddit.global_navigation_counter` account-data key are parsed
  alongside the standard events.

## 3. Sending

### Payload

A text message is a plain Matrix event, the same shape Reddit's own
client sends:

```json
{ "body": "Hello", "msgtype": "m.text" }
```

`PUT /_matrix/client/v3/rooms/{id}/send/m.room.message/{txnId}`
(`RedditChatClient.send`). Reddit's own client uses a Reddit fullname
as the transaction id; Phoebus uses `phoebus_<UUID>`.

### Transaction ids make sends idempotent

The homeserver deduplicates on the transaction id, not on content:
replaying a send with the **same** id returns the **same** `event_id`,
while a **different** id with an identical body creates a second
message. A retry must therefore reuse the original id, or a response
lost to a flaky network delivers the message twice.

Reddit's REST endpoints (`/api/comment`, `/api/compose`) offer no such
key, which is why `submitComment` and `sendPrivateMessage` are never
retried automatically. The Matrix send is the one send path that can be
made safely retryable.

### `ChatSendQueue`

A persistent FIFO outbox (an actor storing its entries in
`UserDefaults`), modelled on the Matrix Rust SDK's `send_queue`:

1. **The transaction id is assigned at enqueue** and persisted, so it
   survives retries and an app restart. "Did this already send?" survives
   a force-quit.
2. **A failed send blocks the ones behind it.** A conversation cannot
   arrive out of order because message 2 overtook a stuck message 1.
3. **Failure is three-state.** `RedditChatClient.isRecoverable` decides:
   401 (re-mint), transport failure and 5xx stay queued and retry; a 4xx
   *parks* the message, because retrying a request the server already
   rejected only repeats the rejection. Every queued message is
   abortable (`abort`) and retryable (`retry`) rather than being a
   spinner.
4. Only one drain per entry runs at a time (`claimNext`, an in-flight
   set), since drains start from several places (opening the room,
   sending, Try Again, pull to refresh).
5. Entries record the account that wrote them, so switching accounts
   never sends a queued message as someone else.

`RedditRepository` exposes `enqueueChatMessage`, `drainChatQueue`,
`pendingChatMessages`, `abortChatMessage` and `retryChatMessage`. The
smoke suite asserts the queue's ordering, parking, persistence and
account scoping without sending anything.

### Other room operations

Implemented in `RedditChatClient` on the same credential:

- Images, GIFs and video: media upload (`uploadMedia`, `sendImage`)
  against `/_matrix/media/v3`, which advertises a 20 MB upload limit
  (100 MB for GIFs).
- Edits (`editMessage`): a new `m.room.message` carrying `m.new_content`
  and an `m.relates_to` of `rel_type: m.replace`; the parser folds edits
  into their target and drops the `m.replace` events themselves. The
  top-level `body` of an edit is Matrix's legacy fallback (`* text`) and
  must never be shown.
- Deleting (`redactMessage`): a redaction. A redacted message has its
  content emptied and gains `unsigned.redacted_because`.
- Read receipts (`sendReadReceipt`), typing notices (`sendTyping`) and
  their display (`parseEphemeral`, `RoomEphemeral`).
- Date separators (`ChatDateFormatter`), the Direct/Group/All and
  Unread Only filter (`ChatMessagesFilter`), and Bark unread
  notifications (`ChatUnreadNotifier`).
- Unread rules (`ChatRoomUnread`, one source for every screen and total):
  a joined room with `notification_count` above zero is unread and shows
  the dot, the bold title and a place under Unread Only. A room Reddit
  keeps out of its global counter (a muted one,
  `is_counted_in_global_navigation_counter` false) is still unread, drawn
  with a grey dot, but only a room that counts toward the badge feeds the
  Inbox tab badge, the app icon badge, `lastChatUnread` and the Bark
  pushes. Opening the room clears it with the read receipt as for any room.
- Muting (`ChatMute`, `ChatSyncState.beginMute`): Reddit's own chat page mutes a
  room with a push rule, and Phoebus writes and reads the same one. Mute is
  `PUT /_matrix/client/v3/pushrules/global/override/<room id>` with
  `{"actions":["dont_notify"],"conditions":[{"key":"room_id","kind":"event_match","pattern":"<room id>"}]}`;
  unmute is `DELETE` of that rule (a 404 is already unmuted). A room is muted
  when an enabled `override` rule has the room id as its id and as the only
  condition's pattern and `dont_notify` among its actions, and has no
  `com.reddit.expiration_ts` in the past (a timed mute made on Reddit's side).
  The rules that mute only mentions, threads or reports have other ids and extra
  conditions, and are not a muted room. `/sync` does not carry push rules, so the
  engine reads `GET /pushrules/` after its first sync and on every list refresh.
  Reddit then leaves the room out of its global counter, but its counted flag is
  only re-sent when the room changes. A change made here therefore applies at
  once (the row, the grey dot, the Inbox total, which is derived from the rooms
  while it settles), is read back from a fresh room list two seconds after the
  rule is accepted, overrides stale `/sync` flags for `ChatMute.staleShield`
  seconds, and is rolled back with a plain sentence if the rule is refused. A
  change made here records the new total for Bark and never pushes for it. The
  row shows `bell.slash.fill` beside its time (also in Inbox's chat row), the
  conversation's menu button shows it too, and Mute/Unmute is on the row's swipe
  and long press and in the conversation's menu.

### Reactions

A Reddit Chat reaction key is an **image filename** served from
Reddit's CDN, for example `foyijyyga7081.gif`, not an emoji and not a
name. The homeserver rejects anything else with
`M_INVALID_ARGUMENT_VALUE: "reaction key is not supported"`.
`RedditChatReactions.keys` holds the 48 keys the homeserver accepts, in
Reddit's picker order, and `imageURL(forKey:)` resolves each to
`https://i.redd.it/<key>`.

Parsing details that matter (`parseReactions`, `reactions`):

- Reactions are **not** included in `/messages`. They arrive in `/sync`
  and `/relations`, so a room's reactions cost one `/relations` request
  per message, issued concurrently and bounded, **after** the messages
  render. Reactions are decoration and must not make the conversation
  wait.
- Removing a reaction is a **redaction of the event that added it**, so
  every reaction retains the event id that created it.
- A removed reaction keeps its content and is marked only by
  `unsigned.redacted_because`, unlike a redacted message whose content
  is emptied. Filtering on empty content would leave removed reactions
  on screen.
- Reddit's own client sends the relation *flattened* into the event
  content, while sync delivers it *nested* under `m.relates_to`. Both
  occur, and both are handled.
- A reaction to an *edited* message must target the original event: the
  edit event's id is folded away and a reaction attached to it renders
  nowhere.

## 3a. Chat requests

A chat request is a Matrix **room invite**. `/sync` lists it under
`rooms.invite` (its state is `invite_state`, not `state`), and Reddit's
`com.reddit.invites_counter` counts it. Apollo Reborn hosts Reddit's web
chat and never answers a request natively; Reddit's own apps offer
Accept, Ignore and Block (and Report). Phoebus has Accept, Decline and
Block.

- **Accept** is `POST /_matrix/client/v3/rooms/{id}/join` with `{}`.
  **Decline** is `POST .../rooms/{id}/leave`, which for an invite is
  Matrix's rejection. Both are idempotent (joining a joined room or
  leaving a left one answers 200), so the 401 re-mint retry is safe
  (`RedditChatClient.answerRequest`, `RedditRepository.sendChatRequestAnswer`).
- **Block** is the account block (`/api/block_user` with the sender's
  `t2_` id, `blockChatRequester`), run *before* the leave: if it fails the
  request is untouched and the error says so. The sender is the inviter named
  in the invite's `m.room.member` event (`ChatRoom.inviter`), else the one
  other participant.
- **Errors.** A 401 re-mints. A 403 or 404 that carries a Matrix `errcode`
  (the invite was withdrawn) is the request's own rejection
  (`ChatError.requestRejected`) and is never retried as a dead token; a 403
  with no body still means a dead bearer, as elsewhere. `ChatRequests.failureMessage`
  turns each into a sentence (offline, no longer available, rate limited, server
  trouble).
- **Optimistic.** `ChatLiveSync.answerRequest` asks `ChatSyncState` to apply the
  answer first: an accepted request becomes a joined room (so it moves from
  Requests to Messages) and a declined one disappears, and the request count
  drops, which publishes to the Inbox badge (`InboxUnreadCount.chat` shows the
  request count while nothing is unread). On failure the request is put back, the
  count restored and the error rethrown for the screen. The count is Reddit's own
  counter lowered locally, never recomputed from the invite list, because the two
  differ (see modmail invites).
- **A stale sync cannot undo it.** A `/sync` already in flight, or a list fetched
  while the answer is outstanding, can still carry the old invite. While an
  answer is outstanding, and for `ChatRequests.staleInviteShield` (30 s) after the
  homeserver took it, invite entries for that room are ignored, and Reddit's counter
  is only taken when it is lower than the local one. The sync that reports the join or the
  leave ends the override, so a genuine later invite shows.
- **No reply before accepting.** A user who has not joined cannot send into the
  room, so `ChatRequests.canReply` is false for an invite and the conversation
  shows the Accept bar in place of the composer. Nothing is sent, queued or
  silently joined.
- **What a request carries.** Observed against a live account: the invite is
  only `invite_state` (create, join rules, the inviter's own `join`, an optional
  name and `com.reddit.chat.type`, and the `invite` member event, which Reddit
  lists twice) with no timeline, and `/messages` on the invited room answers 200
  with an empty chunk. Neither the first message nor any history is available
  before joining, so the request screen says who it is from and to accept to read
  the message. The inviter is the `sender` of the `invite` event (also the room's
  creator and the one `join` member), which is what `ChatRoom.inviter` holds.
- **Modmail invites.** The invite list also holds invites to subreddit modmail
  conversations (`com.reddit.chat.type` of `reddit_modmail`, for example a ban
  notice). Reddit's request counter leaves them out (an account with one person's
  request and one of these reported 1), so they do not move the optimistic count
  (`ChatRequests.countsAsRequest`), do not offer Block (`canBlock`), and read as a
  modmail notice rather than "wants to chat with you".

## 4. Threads

Threads are reachable. The homeserver advertises
`org.matrix.msc3440.stable` in `/_matrix/client/versions`, and the
relations API works:

`GET /_matrix/client/v1/rooms/{id}/relations/{event}/m.thread`
(`RedditChatClient.threadReplies`, `fetchChatThreadReplies`).

The same call returns the same chunk shape as `/messages`, so the same
parser applies. Messages carry their reply count in the bundled
`unsigned.m.relations["m.thread"]`, which `ChatRoomScreen` uses to show
an "N replies" affordance and push a thread view.

What the homeserver does **not** provide is a room-level *listing*:
MSC3856's `/_matrix/client/v1/rooms/{id}/threads` returns 404. A
room-wide or global Threads tab would have to walk each room's recent
timeline and query relations per message, which is a cost that scales
with the number of rooms. Phoebus therefore offers threads per message
and has no Threads section in the chat list (`ChatListScreen` has
Messages and Requests).

## 5. Why direct Matrix, and why no Matrix SDK

### Not a hosted web view

Reddit's chat page is a client-side app that itself declares
`<rs-matrix-client uri="https://matrix.redditspace.com">`: Reddit's web
client is a Matrix client too. Hosting it means running a browser and
patching a private DOM (the composer re-renders on every keystroke, chat
content lives in shadow roots, the page does not render on older iOS
versions), all of which is a bet on markup Reddit may change at any
time. That is the price a tweak pays because it cannot replace Apollo's
screens. Phoebus owns its UI, so it talks to the public, versioned
`/_matrix/client/v3/...` API directly, and themes, accent colours, swipe
actions, Liquid Glass insets and the markdown renderer apply
automatically.

The trade-off is feature completeness: the web client gets every new
Chat feature for free, whereas each feature here needs implementing. If
a feature were needed before a native version existed, an embedded web
room is a possible fallback.

### Not a Matrix SDK

- **matrix-ios-sdk** (the legacy SDK) has no `Package.swift`, is
  CocoaPods-only, and its Core subspec requires prebuilt binary
  dependencies, so it cannot be consumed by an xtool/SwiftPM build on
  Linux. It also implements no `com.reddit.token` login flow, which is
  the only flow Reddit's homeserver offers.
- **matrix-rust-components-swift** (the current SDK) builds, and
  `Client.restoreSession` can take the minted token directly, so build
  system and login are not obstacles. The blocker is sync: the Rust SDK
  requires sliding sync (MSC3575/MSC4186), and Reddit's homeserver does
  not provide it. Every sliding-sync path (`unstable/org.matrix.simplified_msc3575/sync`,
  `unstable/org.matrix.msc3575/sync`, `unstable/org.matrix.msc4186/sync`,
  `unstable/org.matrix.msc4186/sliding_sync`) returns 404 while plain
  `GET /v3/sync` returns 200, and `/versions` lists no sliding-sync
  feature. Without it the SDK's room list and timelines cannot run.
- Reddit Chat as observed is unencrypted (no `m.room.encrypted` events,
  `.well-known` advertises `io.element.e2ee.default: false`), so an SDK's
  main value (end-to-end encryption, device verification, key backup) is
  inert here.

The practical answer is to follow the spec rather than invent: standard
endpoints, standard transaction-id idempotency, standard `m.thread` and
`m.replace` relations, with Reddit's `com.reddit.*` extensions handled
alongside. The send queue (section 3) borrows the Rust SDK's *design*,
not its code. This is worth revisiting if Reddit ships sliding sync.

## 6. Where the code lives

| Piece | File |
|---|---|
| Matrix client, sync parsing, send, threads, edits, reactions, receipts, typing, media | `Sources/PhoebusCore/Inbox/Chat/RedditChatClient.swift` |
| Persistent ordered outbox | `Sources/PhoebusCore/Inbox/Chat/ChatSendQueue.swift` |
| Answering requests (join, leave, errors, messages) | `Sources/PhoebusCore/Inbox/Chat/ChatRequests.swift`; optimistic state in `ChatLiveSync.swift` (`ChatSyncState`) |
| Long-poll sync | `Sources/PhoebusCore/Inbox/Chat/ChatLiveSync.swift` (UI owner `Inbox/Chat/ChatLive.swift`) |
| Reaction key set | `Sources/PhoebusCore/Inbox/Chat/RedditChatReactions.swift` |
| Repository facade | `Sources/PhoebusCore/API/Repository/RedditRepository+Chat.swift` |
| Screens | `Sources/PhoebusUI/Inbox/Chat/ChatListScreen.swift` (`ChatRoomScreen`, `ChatRequestBar`) |
