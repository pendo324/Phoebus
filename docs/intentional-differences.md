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

- **The flair alert says what kind of flair it is and where it's from.**
  Tapping a flair in a comment header, or the post's or author's flair in
  the post header, opens Apollo's flair alert: "Flair", the flair in full
  with its emoji, and OK. Phoebus adds a line under the flair, such as
  "User flair in r/nfl" or "Post flair in r/nfl", which Apollo's alert
  doesn't have. Feed rows open it from the author's flair pill.
- **Feed rows show the author's flair with its emoji, and wrap it.** In a
  subreddit's feed the flair sits after the name in the info row, as in
  Apollo; when it doesn't fit, it moves to its own line under the row
  rather than truncating the name or the stats. Settings > Appearance >
  Flair > Show Flair in Feeds (Phoebus-only, on by default) hides it in all
  feed rows; User Flair still governs flair everywhere.
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
  backups, and "Show Recently Visited" in Subreddit List Sections hides it.
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
- **Post Rules (Settings > Filters > Rules > Post Rules) are
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

## Removed posts and comments

- **Removed posts can be recovered.** When a post reads `[removed]` or
  `[deleted]`, has a removal category, or its author is deleted, post
  detail shows the archived title (when it differs), body, link and
  author from Arctic Shift under a "Recovered from archive" label. It
  follows the Deleted Comments mode: Always Show fetches on open (with
  Tap to Show behind the reason chip), Passive shows a "Show Original
  Post" row, Off shows nothing. Neither Apollo nor Reborn has this;
  it is inspired by Continuum's removed post recovery.
- **Deleted comments fall back to Reveddit.** When Arctic Shift has no
  copy of a deleted comment in the thread, Phoebus asks Reveddit's thread
  lookup once and fills the gaps; Arctic Shift's copy wins where both
  have one. Reborn uses Arctic Shift only; the fallback is inspired by
  Continuum's removed comment recovery.
- **Saved items are kept locally.** Every save made in Phoebus keeps a
  small snapshot (title or comment text, subreddit, author, link). When
  Saved has been paged to its end, or after "Check for Missing", items
  Reddit no longer lists move to Saved > Kept Locally with a Removed,
  Deleted, Unavailable or Not in Saved badge; a gone comment's body comes
  back from Arctic Shift. "Keep Local Copies of Saved Items" in Settings >
  General turns it off. Neither Apollo nor Reborn has this; it is
  inspired by Continuum's Local Saved.

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
- **You can sign in to YouTube for the player.** Settings > Accounts & Security >
  YouTube signs the player in as your Google account
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

- **Settings are grouped by task, not by Apollo's or Reborn's tree.**
  The root is one screen: thirteen category rows (Accounts & Security,
  Appearance, Posts, Feed, Comments, Media, Links & Sharing, Filters,
  Inbox & Notifications, Gestures & Haptics, Integrations, Data &
  Storage, About). A category screen holds the switches and pickers
  themselves, in sections; it pushes a screen of its own only for a list
  editor (filters, blocked users, watchers, backups), a screen with a
  pinned live preview (Inline Images, Preview Cards, Subreddit Layout,
  Subreddit List Sections, Profile Layout, Text Sizes & Fonts) or a
  multi-step tool (Theme Manager, App Icon, Translation, Phoebus AI).
  Apollo's General screen (46 rows from five unrelated jobs: 19 of them
  comment settings), Interface, Deleted Comments, Portrait Lock,
  Passcode, Notifications, Marking Read / Hiding, Polls, User Profiles
  and Subreddits no longer exist as screens: their sections moved to the
  category that does that job, so "Comments" is the comment settings,
  not two of them, and no category repeats its name one level down.
  Nothing is more than two levels deep. Core's `SettingsCategory` lists
  every category's sections and drill-downs, and the search index
  generator refuses a screen that draws other sections or pushes other
  screens than Core says.

  Where each screen and section of Apollo's and Reborn's trees went:

  | Was | Now |
  |---|---|
  | Settings › Modern Settings (Reborn's hub) | gone: the root is the tree |
  | Modern Settings › Accounts & API Keys | Accounts & Security: Sign-In, Settings per Account, API Keys, Kagi Search, YouTube |
  | Settings › Accounts (the account switcher) | Accounts & Security › Accounts, with an Add Account row |
  | Accounts & API Keys › Experimental › Web Session Accounts | Accounts & Security › Accounts (web-session accounts are added from Add Account) |
  | Accounts & API Keys › Extras › Copy Widget Setup Code | Integrations › Widget Setup Code |
  | Settings › Face ID & Passcode | Accounts & Security › Passcode |
  | (Phoebus) Sign Out, Global Defaults | Accounts & Security: the last row; Settings per Account › Edit Global Defaults |
  | Settings › Appearance: Text Size | Appearance › Text |
  | Settings › Appearance: Posts, Large Posts, Compact Posts, Flair, Other | Posts: Layout, Large Posts, Compact Posts, Thumbnails, Flair & Awards, Post Info |
  | Settings › Appearance: Media (Show GIF Progress) | Media › Playback |
  | Settings › Appearance › Theme Manager, Text Sizes & Fonts | Appearance › Theme, Text drill-downs |
  | Settings › App Icon | Appearance › Theme › App Icon |
  | Modern Settings › Interface (Tab Bar, Display & Navigation) | Appearance: Tab Bar, Bars & Navigation, Keyboard |
  | Interface › Menus › Customize Action Menus | Gestures & Haptics › Menus › Action Menus |
  | Interface › Tab Bar › Settings Shortcuts | Integrations › Settings Tab › Settings Shortcuts |
  | Modern Settings › User Profiles (Profile Layout, picture rows) | Appearance › Profiles; Profile Layout is a drill-down there, Profile Picture Tab Icon sits beside the picture rows |
  | Modern Settings › Theme Manager › Comments Theme | Comments › Display › Thread Colours |
  | Modern Settings › Posts & Feeds | Feed (Recently Read, Floating Tabs, Interactive Posts, the video scrubber and forward-swipe rows under Loading); Text Post Thumbnails and Info Row are Posts |
  | Modern Settings › Subreddits | Feed › Subreddit List and Search › Search Sources |
  | Modern Settings › Polls | Posts › Polls (the switch and Option Text Alignment); its Reddit Sign-In cell is Accounts & Security › Sign-In › reddit.com Web Sign-In |
  | Modern Settings › Comments, Deleted Comments | Comments: Collapsing, Removed Comments, Live Comments |
  | Modern Settings › Media | Media (Browsing, Playback, NSFW Media, Network); Links & Sharing (Sharing, Uploads) |
  | Media › Inline Media › Inline Media Settings | Comments › Display › Inline Images |
  | Modern Settings › Picture-in-Picture | Media › Miniplayer › Picture-in-Picture |
  | Modern Settings › Open in App, Rich Link Previews | Links & Sharing › Other Apps › Open in App; Link Previews › Preview Cards |
  | Modern Settings › Translation, Phoebus AI | Integrations › Translation & AI |
  | Modern Settings › Siri & Spotlight | Integrations › Siri & Spotlight (iOS 27) |
  | Settings › Filters & Blocks | Filters: keywords, subreddits, blocked users, user tags, authors and domains, subreddit-specific filters, filter by name |
  | Filters & Blocks › Post Rules, Comment Filters | Filters › Rules › Post Rules, Comment Rules |
  | Modern Settings › Tag Filters | Filters › Tag Filters and Per-Subreddit Overrides sections |
  | Modern Settings › Saved Categories | Data & Storage › Saved Items › Saved Categories |
  | Settings › Notifications | Inbox & Notifications: Inbox, Notification Sound; Subreddit Watchers is a drill-down |
  | Modern Settings › Notification Backend | Inbox & Notifications › Delivery and Registration |
  | Modern Settings › Backup & Restore | Data & Storage › Export & Restore |
  | Modern Settings › Automatic Backups, Manage Backups | Data & Storage › Backups, Backup Schedule, Backup Activity; Manage Backups |
  | Modern Settings › Clear Caches; General › Cache › Clear Cache | Data & Storage › Storage › Clear Cache |
  | Modern Settings › Clear Banners | Data & Storage › Storage › Clear Banners & Icons |
  | General › Manage Uploads | Data & Storage › Uploads › Manage Imgur Uploads |
  | General › Is Apollo Still Taking up Storage? | Data & Storage › Storage › What Phoebus Keeps on Disk |
  | Modern Settings › Export Logs | About › Support › Export Debug Logs |
  | Modern Settings › Automatic Update Checks | About › Updates |
  | Modern Settings › Crash Reports | About › Support › Crash Reports |
  | Modern Settings › Anonymous Install Count | gone (see below) |
  | Modern Settings › Feature Requests, Bug Reports, GitHub, Version | About › Support |
  | Settings › General: Posts | Feed › Sorting, Loading; Media › Playback (Autoplay GIFs/Videos); Links & Sharing › Sharing (Share Includes Title); Data & Storage › Saved Items (Upvote on Save) |
  | Settings › General: Comments | Comments (all but Blocked Users); Blocked Users is Filters › Blocked Users' Comments |
  | Settings › General: Safari | Links & Sharing › In-App Browser |
  | Settings › General: Media | Media › Browsing, Playback, Saving |
  | Settings › General: Moderator | Inbox & Notifications › Moderator |
  | Settings › General: Other | Feed › Loading, Read Posts (3D Touch Marks Read); Links & Sharing (Open Tweets in, Share old.reddit Links); Data & Storage › Saved Items; Gestures & Haptics › Haptics |
  | General › Smart Rotation Lock | Gestures & Haptics › Rotation |
  | General › Mark Read / Hiding Posts | Feed › Read Posts, Auto Hide |
  | General › Open Links In | Links & Sharing › Open Links In |
  | Settings › Low Data Mode | gone (see below) |
  | Settings › Gestures | Gestures & Haptics |
  | Settings › About | About |

  Reborn's post-filter surface has no screen of its own: it is Filters'
  Subreddit-Specific Filters and Filter Subreddits by Name sections, and
  the per-subreddit detail is pushed from there.

  Integrations keeps Translation, Phoebus AI and Settings Shortcuts as
  drill-downs rather than inlining them: Translation alone has five
  sections, and inlined they would take the screen past 60 rows.
  Picture-in-Picture stays one for the same reason (four sections and
  three choosers), which keeps Media near 30 rows. Subreddit Watchers
  holds Reborn's trending subreddits too, since both lists come from one
  backend call.

- **A settings screen has one entrance.** Each screen is pushed from
  exactly one row, and has one name everywhere: its row, its navigation
  title, its search entry and every breadcrumb. One link into another
  category's content stays, because it is where that screen is needed:
  Open in App's Open Links in row pushes the same browser list that
  Links & Sharing draws inline, beside the apps that take the rest.

- **Polls link to the web sign-in rather than hold it.** Voting in polls
  needs the active account signed in with a reddit.com web session, and
  the cell that shows and sets it up (a green "Ready to vote and post", a
  "Sign In Again" choice, "Set Up reddit.com Web Sign-In") is Accounts &
  Security's, with the other sign-in rows. Posts › Polls says so in its
  footer and has a Web Sign-In row, with the account's status, that opens
  Accounts & Security scrolled to and flashing that cell. Core lists it as a
  cross-link (`SettingsCrossLink`) to a row on another category's screen,
  not as a drill-down, so it is not a second entrance to a screen.

- **Some screens are renamed.** A drill-down may not share a word with
  its category (`Checks/SettingsTree.swift` checks it, and the list of
  exceptions is empty), and Phoebus names a screen by what it holds. Their
  `UserDefaults` keys and shortcut ids are unchanged:

  | Reborn / Apollo | Phoebus | Why |
  |---|---|---|
  | Comments Theme | Thread Colours | Was in Comments |
  | Inline Media | Inline Images | Is in Comments |
  | Rich Link Previews | Preview Cards | Is in Links & Sharing |
  | Feed Shortcuts | Subreddit Shortcuts | Is in Feed |
  | Comment Filters (Phoebus's) | Comment Rules | Is in Filters; matches Post Rules |
  | Is Apollo Still Taking up Storage? | What Phoebus Keeps on Disk | Is in Data & Storage |
  | Accounts & API Keys, Posts & Feeds, Media | sections of Accounts & Security, Feed, Media | Dissolved into their categories |
  | Blocked Users (Hide / Collapse) | Blocked Users' Comments | Sits beside the Blocked Users list |

- **Clear Cache is one control.** Apollo's General › Cache menu (Clear
  Cache, Clear Browser Cache) and Reborn's Clear Tweak Caches are merged
  into Data & Storage's Clear Cache row, which asks what to clear (the
  app cache, only artwork and previews, or the in-app browser's cache)
  before it does. Sign Out and Clear Banners & Icons ask first too.
  Export Debug Logs does not: it only opens the share sheet.

- **There is no Anonymous Install Count switch.** Reborn's switch turns
  off its install heartbeat; Phoebus sends none, so the switch changed
  nothing and is not shown. Nothing reads `ApolloUsageHeartbeatDisabled`.

- **There is no Low Data Mode row.** Apollo's Low Data Mode has no
  setting behind it in Phoebus yet, so it has no row in the tree.

- **Settings shortcut ids follow the regrouping.** The "reborn" shortcut
  opened a hub that no longer exists, and the screens behind several
  others were dissolved, so a saved list migrates each retired id to the
  category that holds those settings now and keeps its slot:

  | Retired id | Becomes |
  |---|---|
  | `reborn` | `settings-root` |
  | `accounts-api-keys` | `accounts-security` |
  | `posts-feeds`, `subreddits`, `general` | `feed` |
  | `user-profiles`, `profile-layout`, `interface` | `appearance` |
  | `inline-media` | `media` |
  | `tag-filters` | `filters` |
  | `automatic-backups` | `data-storage` |
  | `gestures` | `gestures-haptics` |

  Ids that migrate to one place collapse to one shortcut. `general` goes
  to Feed because its first sections (sorting, Default Reddit to Load,
  read posts) became Feed's, but its largest part, the comment rows, is
  Comments. The default shortcut list names Data & Storage where Reborn's
  named Automatic Backups.

- **The app icons are Phoebus's own, not Apollo's or Reborn's.**
  Apollo's icons and Reborn's Liquid Glass packs are their artists' work,
  so Phoebus ships neither. Reborn's picker is unchanged, but its Liquid
  Glass packs are Phoebus's two, Phoebus and Always Dark, and there are no
  standard packs; the standard "Default" entry (search) is the primary
  icon, Phoebus.
  - The bar's Light / Dark / System menu is Reborn's. The icons are
    compiled into an asset catalog on Linux (actool's reimplementation),
    so System is the icon itself and follows iOS's Home Screen appearance
    setting (light, dark, tinted, clear), and Light and Dark are variants
    that pin the light or the dark look in every setting.
- **The interface glyphs are not Apollo's.** Phoebus ships none of
  Apollo's artwork, so the info row, vote arrows, swipe actions, menus,
  tab bar, composer toolbar, link buttons, inbox and feed orbs use SF
  Symbols, a few open-source icons (see CREDITS.md) and drawings of its
  own, sized to look as large as Apollo's in the same slots. Shapes and
  line weights differ from Apollo's:
  - The swipe-action glyphs are SF regular weight, a little heavier than
    Apollo's thin outlines, so they read at the same size.
  - The sort menu's Top and Controversial are Lucide's arrow-and-bars
    and crossed swords, Mark All Read is Phosphor's double check, and
    the moderator menu row and orb are Tabler's shield with a star.
  - Link buttons use the brand's own mark only for links to that
    service: an outline Snoo (Phosphor `reddit-logo`) for Reddit posts,
    the Twitter bird (Font Awesome) and the Wikipedia W (Simple Icons).
    Other web links get a generic compass (`location.north.circle.fill`;
    Safari's icon is reserved for Apple's app), and xkcd links two
    figures (`figure.2`), since xkcd has no openly licensed mark.
  - The subreddit "r" tag is Phoebus's own drawing, not a trace of
    Apollo's.
  - SpongeText ("aAa") and Text Faces ("ಠ_ಠ") are drawn as text.
  - The settings profile preview shows SF `person.crop.circle.fill` on a
    tinted circle instead of Apollo's avatar.
- **The Inbox tab is filled on the glass tab bar.** On iOS 26's glass
  tab bar the Inbox tab uses `envelope.fill`; the other tabs, and every
  tab on the classic tab bar, stay outline as in Apollo.
- **There is no Wallpapers screen.** The Settings row and the
  collection behind it are gone. Apollo's "Goodbye" set is a curation
  of other people's photographs, one of them by Christian Selig, hosted
  on Imgur rather than the artists' own hosts; shipping a browser for
  it would mean republishing another artist's work from a third-party
  host on someone else's behalf. The old Apollo and Reborn backup keys
  (`UnlockedWallpapers`, `WallpaperPromptMostRecent2`) are still
  imported, so a backup from either app restores everything else
  cleanly.

- **Deleting your own post asks first.** Delete Post in the post's ••• menu
  shows a "Delete Post?" alert. Apollo's strings hold no such prompt, but a
  delete cannot be undone.
- **Header Style has an "Automatic" option** that follows the system.
  This is a Phoebus addition.
- **Comment Rules are a Phoebus addition.** Settings → Filters → Rules →
  Comment Rules holds named filters that hide or collapse comments by
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
  profile and the inbox. Settings → Filters → User Tags lists,
  edits and deletes them. Tags stay on the device (never sent to Reddit),
  match usernames case-insensitively and are included in backups.
  Neither Apollo nor Reborn has this; it is inspired by Continuum's user
  tags.
- **The Minimize hide style draws its own pill.** Reborn resizes UIKit's
  own tab bar glass into the pill. Phoebus lays a glass capsule over the
  bar, shrinks it on Reborn's measured curves while the real bar fades,
  and keeps the bar hidden (UIKit writes its alpha back during layout)
  until the pill is tapped. Its Down style moves the bar's sublayers
  rather than the bar, which UIKit's layout turned into a jump.
- **There is no What's New screen, no FLEX debugging and no debug rows
  from the Apollo Reborn hub.** They are not useful in Phoebus. The FLEX
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
- **Text Sizes & Fonts** (Settings > Appearance) sets a size for post
  titles, post details, the opened post's title, post text, comment
  headers, comment text and link previews on top of the app-wide Text
  Size, and a built-in font family (System, Rounded, Serif, Monospaced)
  for titles, content and the interface (post details, comment headers and
  link previews; other screens keep the system font). Neither Apollo nor Reborn has
  this; it is inspired by Continuum's and RedReader's font settings. At
  its defaults every font is unchanged.
- **Threads can remember where you were.** With General > Comments >
  Remember Thread Position on (off by default), leaving a thread saves the
  topmost comment on screen, and reopening it scrolls back there with a
  brief "Back to Top" pill. The last 20 threads are kept (Threads to
  Remember). A comment link opens at its comment instead, and Live sort
  never restores. Neither Apollo nor Reborn has this; it is inspired by
  Continuum's comment thread continuity.
- **A cold launch can pick up where you left off.** With General > Other >
  Resume Where I Left Off on (off by default), the app reopens the tab you
  were on, the Posts tab's feed scrolled back to the post you'd reached,
  and the post you had open (at its comment, with Remember Thread
  Position). Only within a day of leaving and for the same account; a
  link, widget, notification, quick action or Shortcut opens where it
  points instead. Neither Apollo nor Reborn has this; it is inspired by
  Continuum's resume.
- **Update checks read Phoebus's AltStore source.** Reborn's in-app
  update prompt (#1343) reads a release manifest and compares release
  versions. Phoebus reads the AltStore source of the build's channel
  (stable or nightly, stamped into `Info.plist` by CI) and compares build
  numbers, since a nightly keeps the version of the release it builds on.
  The notes are the source entry's description (a commit subject or a
  link), builds without a channel (local and dev builds) never check, and
  the sheet has no separate expanded notes view.
- **The update installer can be chosen.** Reborn's update sheet always
  opens its chooser. Phoebus adds Settings › About › Update Installer
  (`Phoebus.updateInstaller`, default Ask Every Time): picking AltStore,
  SideStore, Feather, FlareStore or Download IPA makes Update open it
  directly, falling back to the chooser when it can't be opened.

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
- **Deleting your own comment asks first.** Delete in a comment's menu
  shows a "Delete Comment?" alert. Apollo's strings hold no such prompt
  for your own comment (only the moderator Comment Nuke asks), but a
  delete cannot be undone and sat one tap from Edit.

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

## Siri & Spotlight

- **It needs iOS 27 and builds into the app.** Reborn ships it as a
  separate framework injected into Apollo; Phoebus compiles it into the app
  target, and everything is gated on iOS 27 (the Siri & Spotlight section
  of the Apollo Reborn settings and its search results are hidden before it).
  Indexing is off until you turn it on, as in Reborn.
- **"Search Apollo Posts" is not ported.** Reborn's second search action
  fetched Reddit results into a Siri card. Phoebus has "Search Phoebus", which
  opens the Search tab's post results, and "Find Indexed Phoebus Posts" for
  what the device has already seen.
- **Posts and comments are captured from responses, not from cells.** Reborn
  collects the comments of the cells that have loaded; Phoebus reads the
  listing and comment responses it already fetched (including "more
  comments"), so the loaded comments are the fetched thread, up to the same
  limits. Nothing extra is requested, except by Refresh Subscribed Communities.
- **There is no `reborn/settings/siri-spotlight` link.** Phoebus has no
  settings route URLs; the screen is under General and in Settings search.

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
- **Accounts can keep their own settings.** Not in Apollo or Reborn, which
  share one set of settings across accounts; inspired by Continuum's
  per-account settings. "Separate Settings per Account" (off by default,
  API Keys & Sign-In) keeps global defaults and lets each account
  override single settings: changes made while signed in to an account
  apply to it only, overridden rows show a dot with "Use Global Default"
  on long press, and "Edit Global Defaults", "Copy Overrides from…" and
  "Reset This Account's Overrides" manage the layers. An account without its
  own value follows the global one. API keys, passcode,
  notifications, backups and filters stay global.
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
