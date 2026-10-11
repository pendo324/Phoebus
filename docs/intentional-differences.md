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

## Settings and interface

- **Header Style has an "Automatic" option** that follows the system.
  This is a Phoebus addition.
- **There is no What's New screen, no FLEX debugging and no debug rows
  in the Apollo Reborn hub.** They are not useful in Phoebus. The FLEX
  setting is not imported from backups.
- **There is no Memechine Learning setting.** Apollo's General > Other
  switch gated a classifier that Phoebus does not reimplement, so General
  settings offers no row for it.

- **A community author's profile shows their achievements there.** Opening
  an author from a post or comment thread shows "Achievements in r/<sub>"
  (e.g. Elder), fetched once per user and subreddit when the profile opens.
  It needs a web session and is hidden without one; Apollo and Reborn have
  no such section.

## Crash reports

- **Crash reports are reviewed and exported by you.** The review screen
  has no hand-off to a developer feedback form, so there is no "Include
  Debug Logs" switch and no developer-only testing section; share a
  report with "Export Sanitized Report". Reports belong to the person
  running the app, not to Reborn's developers.

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
