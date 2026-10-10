# Intentional differences from Apollo and Apollo Reborn

Phoebus aims to match Apollo for Reddit's design and Apollo Reborn's
features closely. This page lists the places where it deliberately does
not, and why.

If you are about to "fix" one of these back to the upstream behaviour,
check the reason first. If you add a change that knowingly differs from
Apollo or Reborn, add an entry here.

## Feeds and subreddits

- **Filtered subreddits are filtered locally.** Filtering applies to
  All and Popular only, and the filters are not synced to Reddit's
  server-side r/all filter. Apollo synced Filtered Subreddits to that
  server-side filter; Reborn adds nothing here, so Phoebus keeps the
  filters on the device for now.
- **There is no "Block Announcements" row, and Reddit admin posts are
  never hidden.** Reborn's switch blocks Apollo's own announcement
  server, which Phoebus does not have. The Apollo setting is not
  imported from backups.
- **"Use Community Icons" exists and defaults on.** It uses Reddit's
  current community icons. Apollo only had the older icon style, which
  is what turning the setting off gives you.
- **Your own changes show as soon as you reopen a thread or feed.** An
  edited or deleted post, a comment you edited or deleted, the comment
  count after you comment, and a post you just submitted are kept on the
  device (`OwnPostChanges`, the comment-tree caches, `SubmittedPosts`)
  rather than waiting for Reddit's listings to catch up. A just-posted
  comment also gets the OP mark and the flair Phoebus already has for
  you (the post's, or an earlier comment's), without a fetch.

- **Your own posts have an Insights sheet.** ••• › Insights (feed and
  comments view) shows views, the 48-hour views chart, top countries and
  top comments from Reddit's author-only post stats page. Apollo and
  Reborn only had Reborn's comment insights. It needs a web session and
  offers the web sign-in without one.

- **The post composer checks the subreddit's posting rules.** Phoebus
  fetches the moderators' post requirements (title length and words,
  required text, blocked domains, required flair, gallery limits) and
  shows problems under the field as you write, plus the community's
  guidelines in a collapsible note. Only clear-cut cases (title over the
  maximum, missing required flair, text required or not allowed, a blocked
  domain) disable Post; everything else is a warning, and Reddit's answer on
  submit still wins. If the rules can't be fetched the composer behaves as
  before. Neither Apollo nor Reborn has this.

## Posts and comments

- **Link posts have Other Discussions.** A link post's ••• menu in the
  comments view (and a crosspost's) has "Other Discussions", listing the
  other posts of the same link from Reddit's `/duplicates` endpoint as
  feed rows, each opening its thread. When Reddit reports any, a
  "N Other Discussions" row also sits under the post header; Settings >
  General > Comments > Show Other Discussions hides it. Neither Apollo nor
  Reborn has this; it is inspired by Continuum's Other Discussions. A
  Phoebus addition.
- **Recently Visited lists the subreddits, profiles and multireddits you
  open.** Neither Apollo nor Reborn has it; it is inspired by
  Continuum's history. It shows under the feed shortcuts in the
  Subreddits list and on the Search tab before you type, newest first,
  collapsed to five with Show All, with swipe to remove and Clear. Home,
  Popular, All and Moderator are not recorded. Each account keeps its
  own list of up to 50 (signed out has its own), the list is included in
  backups, and "Show Recently Visited" in Subreddit Sections hides it.
- **The crosspost composer suggests destinations.** Neither Apollo nor
  Reborn has it; it is inspired by Continuum's crosspost screen. While
  the subreddit field is empty, recently visited subreddits and the
  subreddits Reddit offers for crossposting (`/api/crosspostable_subreddits`,
  signed-in only) list below it, de-duplicated and without the source
  subreddit or user profiles; tapping one fills the field. The Reddit
  list is fetched once per launch and is simply absent if it fails.
- **A quarantined subreddit can be opted in to.** Under Apollo's
  "quarantined" message, Phoebus shows Reddit's own warning and, when
  signed in, a "View Anyway" button that opts the account in after a
  confirmation and reloads the feed or thread. Once opted in, the
  subreddit's ••• menu has "Leave Quarantine" to opt back out. Neither
  Apollo nor Reborn offers this; it is inspired by Continuum's
  quarantine opt-in.
- **Someone else's multireddit can be copied to your account.** Its •••
  menu has "Copy to My Multireddits" in place of Edit Multireddit: it
  asks for a name (prefilled with the original's), copies it with
  Reddit's `/api/multi/copy`, and offers to open the private copy.
  Neither Apollo nor Reborn offers this; it is inspired by Continuum's
  Copy Multireddit.
- **Post Rules (Settings > Filters & Blocks > Post Rules) are
  Phoebus-only.** Neither Apollo nor Reborn has them; they are inspired
  by Continuum's post filters. A rule hides posts outside a score,
  comment or award range (both ends inclusive), can show only NSFW or
  only spoiler posts, and can hide or require titles matching a
  case-insensitive regular expression (an invalid pattern is ignored).
  Each rule applies to every feed or to chosen ones (Home, Popular, All,
  a subreddit or a multireddit, while viewing that feed). Pinned
  (stickied) posts and your own posts are never hidden, and profiles,
  search and saved lists are not filtered. When the filters empty a
  whole page, the feed fetches the next one straight away, up to five
  pages, so infinite scroll does not stall.

## Media and link previews

- **Link previews are one unified card pipeline.** Reborn's rich
  previews and Apollo's original ones are combined into a single set of
  cards stacked at the end of a post, rather than two separate styles
  (Reborn's split comes from being a tweak on top of Apollo). YouTube
  links get a card, not inline video. Twitter/X previews have a fallback
  provider (for example fxtwitter) because Twitter's own embed is
  unreliable, and Bluesky and Twitter cards have a Compact mode to match
  the other previews.
- **Inline YouTube videos fall back to a poster.** A video that can't play
  in the embedded player (embedding disabled by its owner, removed or
  private) shows its thumbnail with "Can't play here. Watch on YouTube",
  which opens the video, instead of YouTube's own error page.
- **Inline YouTube captions follow the system caption setting.** They are
  off unless Closed Captions + SDH is on or Subtitles is On for the app.
- **YouTube videos play with the app's own controls.** Apollo and Reborn
  show YouTube's web player with its own controls. Phoebus runs the same
  official IFrame player with YouTube's controls off and drives the video
  element in its embed frame from the app, hiding the player's own overlays
  (play button, title bar, spinner, end screens), so a YouTube video behaves
  like every other video: inline on the post screen it looks like a
  v.redd.it video (full-width picture, the corner mute badge, the Feed Video
  Scrubber strip and the speed menu over it, no control panel), and the
  fullscreen viewer has the control panel, scrub bar, remaining time and
  mute button (the same web view moved into it, aspect-fit to the whole screen, with the
  viewer's chrome and the floating control panel over the picture), Hold for
  Video Speed and the scrub gesture, and the floating in-app PiP card when
  the post's video is scrolled away. The mute button shows what the video
  element reports, and ads that play in the same element are not scrubbable.
  The AirPlay button and the system PiP hand-off are AVPlayer features and
  don't apply to it. While the video is paused, not yet played or ended, a
  YouTube logo shows at the bottom-left of the picture (inline, fullscreen
  and on the card); tapping it opens the video on YouTube at the current
  time.
- **You can sign in to YouTube for the player.** Settings > Apollo Reborn >
  Accounts & API Keys > YouTube signs the player in as your Google account
  (YouTube Premium without ads, watch history, age-restricted videos), by
  Google's own sign-in page in a sheet or by pasting a browser's cookies.
  Every YouTube web view and the sheet share one persistent website data
  store, kept apart from the in-app browser and Reddit sessions. iOS blocks
  cookies in the third-party YouTube frame unless "Allow Cross-Website
  Tracking" is on for Phoebus in iOS Settings (the app can't read or set it,
  so the section links there). A player that isn't playing reloads when you
  sign in or out; a playing one picks it up when it next loads. Apollo and
  Reborn have no YouTube sign-in.
- **Link cards under a post or comment are capped (Maximum Cards,
  default 5).** Apollo and Reborn draw a card for every link. In Settings
  > Rich Link Previews you can pick 1, 2, 3, 5, 10 or Unlimited; the cards
  past the limit fold behind a "Show N more previews" row that expands in
  place. Inline images and videos are never hidden, and a link post's own
  top card is not affected. This is a Phoebus addition, so Reborn backups
  carry no value for it.

## Navigation

- **A back swipe out of an unsaved post or comment edit asks first.**
  Apollo edits your own post or comment in its composer, a modal sheet
  that vetoes a swipe-down while it holds text. Phoebus edits inline in
  the post, where a back page swipe would drop the edit without a word,
  so the swipe is held and "Discard Changes?" is shown instead. Phoebus's
  own design (`docs/gestures.md`, "Unsaved changes"); the back button and
  the inline Cancel are not guarded.
- **Video playback options.** Media → Playback adds Default Playback
  Speed (0.5x to 2x, default 1x), Loop Videos (default on) and Seek
  Interval (5, 10, 15 or 30 seconds, default Apollo's 15). Neither Apollo
  nor Reborn has them; they are inspired by Continuum's video settings.
  Every video starts at the default speed, hold-for-speed returns to it,
  and a speed picked from a player's menu now lasts through pauses and
  loops. Loop Videos off stops every video at its end, silent clips
  included; while it is on, Apollo's rule is unchanged (silent clips loop,
  videos with sound loop under Loop Videos with Audio, which is greyed out
  while Loop Videos is off). Seek Interval moves the fullscreen viewer's
  and the gallery viewer's skip buttons; the in-app PiP card keeps
  Reborn's own Skip Amount and loop setting.

## Posting

- **The post composer has NSFW and Spoiler switches for every post
  type** (text, link, media and poll), sent with the submission. Neither
  Apollo nor Reborn offers them when posting; they are inspired by
  Continuum's submit screens. Apollo's own Mark NSFW / Mark Spoiler
  actions are also wired up: on your own posts they sit in the post's
  ••• menus (feed and comments), and on other people's posts in a
  subreddit you moderate in the Moderator menu, so they never show twice.

## Settings and interface

- **Header Style has an "Automatic" option** that follows the system.
  This is a Phoebus addition.
- **Comment Filters is a Phoebus addition.** Settings → Filters & Blocks →
  Comment Filters holds named filters that hide or collapse comments by
  score range, words in the body or author, everywhere or in chosen
  subreddits. Neither Apollo nor Reborn has it; it is inspired by
  Continuum's comment filters and RedReader's minimum comment score
  setting. Your own comments and a comment opened from a link (with its
  parents) are never filtered, score bounds ignore hidden
  scores and pinned comments, negative bounds work, and a collapsed
  comment says why it was filtered.
- **User tags are a Phoebus addition.** "Tag User…" in a profile's,
  comment's, feed post's or inbox item's ••• menu and the post header's
  author menu ("Edit Tag…" once the user has one) puts your
  own short label (up to 24 characters) and colour on a user, shown as a
  pill after their name in comments, feed rows, the post header, their
  profile and the inbox. Settings → Filters & Blocks → User Tags lists,
  edits and deletes them. Tags stay on the device (never sent to Reddit),
  match usernames case-insensitively and are included in backups.
  Neither Apollo nor Reborn has this; it is inspired by Continuum's user
  tags.
- **There is no What's New screen, no FLEX debugging and no debug rows
  in the Apollo Reborn hub.** They are not useful in Phoebus. The FLEX
  setting is not imported from backups.
- **Search keeps a history and saved searches.** Recent queries show
  under the search field (all of Reddit on the Search tab, one subreddit
  in a feed's search), and a results screen's star saves the query with
  its scope, sort and time. Return on the Search tab, or its "Search
  Posts" row, opens a post search across Reddit. None of this is in
  Apollo or Reborn; it is inspired by Continuum's recent searches. "Save
  Search History" (on) and Clear Search History sit in Subreddits →
  Search.
- **Search finds users.** While typing on the Search tab, a Users
  section above the subreddits lists matching accounts (an exact
  username first) with avatar, karma and account age; tapping one opens
  the profile and adds it to recent searches. Blocked users are left out
  and suspended accounts are greyed. Neither Apollo nor Reborn searches
  accounts; this is inspired by Continuum's user search.
- **There is no Memechine Learning setting.** Apollo's General > Other
  switch gated a classifier that Phoebus does not reimplement, so General
  settings offers no row for it.
- **General > Comments has a Comment Age setting.** Since Posted (the default)
  keeps Apollo's "3h"; Relative to Post shows how long after the post a
  comment came ("+3h"), and Relative to Parent how long after the comment
  it replies to ("2m later", top-level comments count from the post).
  Tapping the age still shows the exact time. Neither Apollo nor Reborn
  has this; it is inspired by RedReader's comment age setting.
- **The edited marker can be turned off, and the age names the edit
  time.** Apollo always drew a pencil beside an edited comment's score
  and after an edited post's age, in feeds and post detail. Phoebus
  keeps that pencil (an SF Symbol, since Apollo's glyph isn't bundled)
  behind General > Comments > "Show Edited Marker", default on, and
  tapping a comment's or post's age also shows "Edited <time>" under the
  creation time. Neither the switch nor
  the age detail is in Apollo or Reborn; both are inspired by Continuum's
  edited-time display.
- **Your own username and users you follow are highlighted.** In comment
  headers, feed rows and the post header, your name is drawn in the
  accent colour (General > Comments > Highlight My Username, on by
  default) and users you follow (your Following list and Reddit
  friends) in orange (Highlight Followed Users, off by default). Moderator and admin colours still win.
  Neither Apollo nor Reborn has this; it is inspired by RedReader's own
  username highlight and Continuum's followed-user marker.
- **Scores can be hidden.** "Hide Post Scores" (Appearance > Other) and
  "Hide Comment Scores" (General > Comments), both off by default, drop
  the number from feed rows, the post header, comment headers, profile
  comments, the media viewer, crosspost cards and Share as Image. The
  vote arrows and their voted colours stay, and the post header keeps
  its "% Upvoted", which does not give the score away; the approximate
  upvote/downvote totals go with the score. Neither Apollo nor Reborn
  has this; it is inspired by Continuum's "Hide the number of votes".

- **A community author's profile shows their achievements there.** Opening
  an author from a post or comment thread shows "Achievements in r/<sub>"
  (e.g. Elder), fetched once per user and subreddit when the profile opens.
  It needs a web session and is hidden without one; Apollo and Reborn have
  no such section.
- **The Search tab has a fourth engine, Reddit Answers.** Pick it from the
  magnifier's "Search With" menu and a question asked on Return gets Reddit's
  generated answer, drawn natively with numbered citations that open the cited
  post or comment. Neither Apollo nor Apollo Reborn has it. It needs a
  reddit.com web session (the one polls use), asks Reddit's website endpoints
  rather than the OAuth API, and each question, follow-ups included, starts a
  new conversation. Carousels, image and video cards, products and quote cards
  are not requested; if one arrives it shows as its text and links.

## Profile

- **"Edit Profile" edits natively; Reborn opens Reddit's web editor.**
  Reborn's own-profile "Edit Profile" shows reddit.com/settings/profile
  in a web view (Reborn #1367). Phoebus has its own screen for the
  banner, display name, about text, "Allow People to Follow You", the
  NSFW label and social links, so it works with API-key and keyless
  sign-ins alike without a reddit.com login. A profile is the account's
  user subreddit (`u_<name>`), so the screen reads its `about/edit`
  settings and writes them back through `site_admin`, which resends every
  setting; a web-session account sends those requests to oauth.reddit.com
  with its web bearer, as moderator endpoints are. The display name is
  limited to 30 characters, not the 90 reddit.com's editor allows: that
  editor saves through web GraphQL (which needs a web session), while
  `site_admin` answers HTTP 500 to a longer title. "Allow People to Follow
  You" is the account preference `enable_followers` (`/api/v1/me/prefs`),
  because `site_admin` accepts but ignores `accept_followers`.
- **Profile Visibility is edited in Edit Profile.** Reborn has nothing for
  it (the website's "Curate your profile" is reached through Edit
  Profile's web page). Phoebus stages "Content and activity" (Show all,
  Customize with a choice of the communities you are active in, Hide all),
  NSFW and Followers in Edit Profile and applies them on Save. They go
  through reddit.com's web GraphQL (`UpdateProfilePrivacyPreferencesV2`,
  and `UpdateAccountPreferences` for the follower count) and are read from
  the settings page, so they need the same web sign-in as social links;
  without one the section offers it. The mutation's `isShowTopSubreddits`
  is always sent true, as the website does: its separate "communities
  shown" switch is not on the page any more.
- **The avatar is changed on reddit.com, signed in.** The Avatar row opens
  reddit.com's profile settings (where a photo or Reddit's avatar builder
  can be chosen) instead of uploading a photo natively. The page is an
  in-app web view signed in with the account's web session, whose cookies
  are seeded into a private data store, because the plain browser was not
  signed in to Reddit. An account without a web session is offered the
  one-time web sign-in first (the one Social Links use); "Open in Safari"
  remains as a fallback.
- **Social links are edited natively, through a web session.** Reddit has
  no OAuth endpoint for them, so the editor uses the Shreddit GraphQL
  mutations reddit.com's own profile settings send, which take a web
  session's cookie. The current links (with the ids removing one takes)
  and the platforms on offer, with the fields each takes, are read from
  that settings page's embedded state. An API-key account without one sees its links
  read-only, with a button to sign in on the web (the sign-in Polls use)
  and an "Open on reddit.com" row. Changes are staged and applied on Save
  with the rest of the screen; editing a link removes it and adds the new
  one, so it moves to the end of the list.

## Crash reports

- **Crash reports are reviewed and exported by you.** The review screen
  has no hand-off to a developer feedback form, so there is no "Include
  Debug Logs" switch and no developer-only testing section; share a
  report with "Export Sanitized Report". Reports belong to the person
  running the app, not to Reborn's developers.

## Moderation

- **Mod Notes are Phoebus-only.** Neither Apollo nor Apollo Reborn has
  them. Moderators can read, add and delete a user's notes (Reddit's
  `/api/mod/notes`) from the Moderator menu on posts and comments and from
  a leading swipe on the banned, muted and approved lists. This needs the
  `modnote` OAuth scope, so API-key accounts added before it existed must
  sign in again; until then Reddit's 403 shows as a "sign in again" message.

## Accounts, notifications and extensions

- **You bring your own Reddit API key.** Phoebus never uses Apollo's
  Reddit client ID; the build default is a placeholder. The key is
  entered under Custom API Settings and applies app-wide, so there is no
  per-account key editor.
- **Sign-in always uses a throwaway cookie store.** Web-session login, the
  Universal OAuth web view and the system OAuth sheet each start with no
  Reddit cookies, so adding a second account shows Reddit's login form
  instead of re-filing the signed-in one. Reborn clears the shared web view
  jar for an additional account; Phoebus leaves that jar alone. The system
  OAuth sheet therefore does not share Safari's Reddit login.
- **Push notifications go through a self-hosted notification backend.**
  There is no central push server: the backend you run delivers through
  the Bark app when a Bark push URL is set, and otherwise over APNs when
  the build is signed with push. Bark wins because a signing can grant
  push while the backend has no APNs key for it.
  Bark can only badge its own icon, so without APNs the app icon's badge
  is kept by the app itself, while open and from background refreshes iOS
  schedules, and can lag behind new messages.
- **Remind Me uses local notifications.** Reminders are scheduled on the
  device through the system notification center, with no server-side
  reminder service, so they also work offline.
- **A web-session account sends private messages with its web bearer.**
  Reddit answers `/api/compose` with a 401 for any cookie request, so
  Phoebus sends it to oauth.reddit.com with the account's web bearer, the
  way it sends the moderator endpoints. Reborn leaves compose on the
  cookie.
- **The Safari extension's mode is chosen in its popup.** Automatic, Ask
  or Off is set from the extension's toolbar popup, not in Settings.

## Backups

- **Some Reborn data is not imported from backups.** Custom themes are
  skipped because Reborn's theme format differs from Phoebus's,
  per-account API credentials are skipped (the global keys are
  imported), and the analytics identity (Bugsnag and Statsig IDs) and
  StoreKit state have nothing to attach to.
- **Backups leave out read-post and new-comment tracking.** The read-post
  set and the "N new comments" tracker are high-churn view state, not
  preferences; restoring stale copies would mark posts read that you have
  not seen on this device.
