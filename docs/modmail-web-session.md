# Modmail over a web session

How Phoebus reaches Reddit modmail for an account that is signed in with
a web session (cookies) rather than an OAuth API key. The behaviours
below are what Reddit's servers do today, observed against a moderator
account; Reddit can change them at any time.

## 1. Modmail is not Matrix

Reddit Chat is Matrix (see
[chat-sending-and-threads.md](chat-sending-and-threads.md)). Modmail's
web page declares no Matrix client and contains no Matrix references.
It is built from `modmail-*` custom elements
(`modmail-mailbox-wrapper`, `modmail-nav-wrapper`,
`modmail-action-bar-multi`, `modmail-subreddit-selection-menu`) and
talks to Reddit's Shreddit GraphQL endpoint.

## 2. What a web session can and cannot reach

- `/api/mod/conversations` (the New Mod Mail REST API) is **OAuth-only**.
  It answers 403 to any cookie-authenticated request.
- Reddit does serve modmail to a web session, through other routes:

| Endpoint | with session cookie | without |
|---|---|---|
| `/message/moderator.json` | 200 JSON | 403 |
| `/message/moderator/inbox.json` | 200 JSON | 403 |
| `/message/moderator/unread.json` | 200 JSON | 403 |
| `/api/mod/conversations` | 403 | 403 |

  `/mail/*` is also fully server-rendered for a cookie session.
- Requests need a **full mobile-browser User-Agent**. With a truncated
  one Reddit answers JSON paths with 403 or a bot-check page. Phoebus
  sends `RedditAPIClient.webBrowserUserAgent`.

So an account without an API key can still use modmail; an OAuth account
uses the REST endpoint. `RedditRepository`'s modmail methods route to
`ModmailWebService` whenever the account holds a web session, so every
modmail screen works under either sign-in method with no parallel UI.

## 3. The write path: Shreddit GraphQL

`https://www.reddit.com/svc/shreddit/graphql` accepts a cookie session.
The CSRF token goes **in the JSON body**, taken from the session's
`csrf_token` cookie, not in a header:

```
POST /svc/shreddit/graphql
Accept: application/json
Content-Type: application/json
Origin: https://www.reddit.com
{"operation": "<Name>", "variables": {...}, "csrf_token": "<csrf_token cookie>"}
```

Operations `ModmailWebService` uses:

| Operation | Purpose | Method |
|---|---|---|
| `ModmailConversations` | list a mailbox (`modmailConversationsV2`) | `fetchConversations` |
| `ModmailUnreadCounts` | per-mailbox unread counts | `fetchUnreadCounts` |
| `ModmailConversationMessagesAndActions` | a thread | `fetchThread` |
| `AddModmailMessage` | reply in a conversation (public or internal) | `reply` |
| `GetMessageRecipientSubredditInfo` | subreddit name to `t5_` id | `subredditID` |
| `SendMessageToSubreddit` | user to subreddit modmail | `sendToSubreddit` |
| `SetModmailConversationsReadStatus` | mark read or unread | `setRead` |
| `SetModmailConversationsHighlightStatus` | highlight | `setHighlighted` |
| `SetModmailConversationsArchiveStatus` | archive | `setArchived` |
| `SetModmailConversationsFilterStatus` | filter | `setFiltered` |
| `MarkAllModmailConversationsAsRead` | mailbox-scoped mark all read (`mailboxCategory` plus `subredditIds`) | `markAllRead` |

Details that matter:

- `conversationIds` are **prefixed**: `ModmailConversation_<id>`
  (`ModmailWebService.prefixed`).
- `subredditIds: []` is required on list calls; omitting it answers
  500. The empty array means every subreddit the account moderates.
- Mailbox categories are GraphQL enum values (`ALL`, `NEW`,
  `IN_PROGRESS`, `ARCHIVED`, `HIGHLIGHTED`, `MOD_DISCUSSIONS`,
  `NOTIFICATIONS`, `FILTERED`, `APPEALS`, `JOIN_REQUESTS`), which differ
  from the REST API's lowercase `state` strings
  (`MailboxCategory.init` maps `ModmailInboxTab.apiState` onto them).
  The sort enum is `RECENT`, `UNREAD`, `MOD`, `USER`; the UI's
  Relevance option is search-only.
- A message from a moderator to their own subreddit lands in
  **Mod Discussions** (`MOD_DISCUSSIONS`), not `ALL`. `ALL` can show its
  empty state while the conversation exists, which would look like a
  failed send if only `ALL` were checked. Looking a thread's header up
  must therefore walk the categories rather than only `ALL`.
- Mod actions (highlight, archive, and so on) are interleaved with
  messages in one `messagesAndActions` connection discriminated by
  `__typename`; dropping them would hide the audit entries the real
  client shows inline.
- `messagesAndActions` pages **25 at a time, newest first**, counting
  mod actions alongside messages. A busy audit trail can push the only
  message onto page 2, so `fetchThread` requests `first: 100`.
- A reply succeeds only if `ok` is true **and** `messageId` is
  non-empty.

### A response of `ok: true` is not proof

A rejected mutation can answer `ok: true, errors: null` and do
nothing; the real failure is in `extensions.warnings[].extensions.code`:

```json
{"data":{"setModmailConversationsArchiveStatus":{"ok":true,"errors":null}},
 "extensions":{"warnings":[{"message":"Fallback value returned",
 "extensions":{"code":"BAD_REQUEST"}}]}}
```

That is Reddit's rule, not a transport problem: mod discussions cannot
be archived (the row carries `data-is-archive-disabled`). The native
client therefore treats a response as successful only if `ok` is true
*and* there is no warning (`warningCode(in:)`, `requireOK`), and
reports a silent rejection as `ServiceError.silentlyRejected`.

### Throttling

Reddit rate-limits this endpoint by answering **HTTP 200** with a
"Prove your humanity" HTML page and a `Retry-After` header, not a 429.
`ModmailWebService.perform` recognises that as
`ServiceError.rateLimited` (instead of a decode failure) and retries
with exponential backoff. Reddit sends `Retry-After: 0`, so the header
is a floor, not a promise: honouring it literally would burn every
attempt inside the throttle window.

## 4. Not ported, and not possible

- **No delete.** There is no delete-conversation operation in Reddit's
  modmail or compose bundles. Sent modmail cannot be retracted.
- **Scraping `/mail/*`** for the list is avoided. The signed partial
  (`/svc/shreddit/partial/.../modmail-conversations`) carries a `sig`
  bound to its parameters, so it can only be scraped from a page, never
  constructed; a JSON listing is far less fragile.
- **Legacy `/api/compose`** answers 401 on www and 404 on old.
  The modhash from `/api/me.json` rotates on every request and is not a
  usable CSRF token. GraphQL supersedes it.
- Over a web session every operation Apollo's modmail UI exposes (list,
  thread, reply, highlight, read/unread, filter, archive, compose) is
  available. Archiving a mod discussion is refused by Reddit, as above.

## 5. Native implementation

- `Sources/PhoebusCore/Inbox/Modmail/ModmailWebService.swift`: the GraphQL
  transport, retries and operations above.
- `Sources/PhoebusCore/Inbox/Modmail/ModmailWebConversation.swift`: decoding of
  conversations, thread entries and mod actions into the same shapes
  the OAuth path produces.
- `Sources/PhoebusCore/Inbox/Modmail/ModmailConversation.swift`:
  `ModmailInboxTab` (mailboxes) and `ModmailSortOption`.
- `Sources/PhoebusUI/Inbox/ModmailListScreen.swift`: the mailbox
  dropdown, sort menu and Mark All Read.
- `Tests/Fixtures/modmail-conversations-v2.json` and
  `Tests/Fixtures/modmail-messages-and-actions.json`: captured response
  shapes the smoke suite decodes.

### UI structure

The mailboxes are menu items, not tabs. The screen has a title-view
dropdown (the current mailbox name plus a chevron), a sort menu and a
"more" menu. A five-segment control above the list would truncate every
label at iPhone width. The sort options are Most Recent, Unread, Mod,
User and Relevance, each with its own icon.
