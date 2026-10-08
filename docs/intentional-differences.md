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

## Media and link previews

- **Link previews are one unified card pipeline.** Reborn's rich
  previews and Apollo's original ones are combined into a single set of
  cards stacked at the end of a post, rather than two separate styles
  (Reborn's split comes from being a tweak on top of Apollo). YouTube
  links get a card, not inline video. Twitter/X previews have a fallback
  provider (for example fxtwitter) because Twitter's own embed is
  unreliable, and Bluesky and Twitter cards have a Compact mode to match
  the other previews.

## Settings and interface

- **Header Style has an "Automatic" option** that follows the system.
  This is a Phoebus addition.
- **There is no What's New screen, no FLEX debugging and no debug rows
  in the Apollo Reborn hub.** They are not useful in Phoebus. The FLEX
  setting is not imported from backups.
- **There is no Memechine Learning setting.** Apollo's General > Other
  switch gated a classifier that Phoebus does not reimplement, so General
  settings offers no row for it.

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
  settings route URLs; the screen is in the hub and in Settings search.

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
