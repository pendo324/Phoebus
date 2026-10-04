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
| Long-poll sync | `Sources/PhoebusCore/Inbox/Chat/ChatLiveSync.swift` (UI owner `Inbox/Chat/ChatLive.swift`) |
| Reaction key set | `Sources/PhoebusCore/Inbox/Chat/RedditChatReactions.swift` |
| Repository facade | `Sources/PhoebusCore/API/Repository/RedditRepository+Chat.swift` |
| Screens | `Sources/PhoebusUI/Inbox/Chat/ChatListScreen.swift` (`ChatRoomScreen`) |
