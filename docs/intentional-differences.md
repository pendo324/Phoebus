# Intentional differences from Apollo and Apollo Reborn

Phoebus aims to match Apollo for Reddit's design and Apollo Reborn's
features closely. This page lists the places where it deliberately does
not, and why.

## Feeds and subreddits

- **Filtered subreddits are filtered locally.** Filtering applies to
  All and Popular only, and the filters are not synced to Reddit's
  server-side r/all filter. Apollo synced Filtered Subreddits to that
  server-side filter; Reborn adds nothing here, so Phoebus keeps the
  filters on the device for now.

## Media and link previews

- **Link previews are one unified card pipeline.** Reborn's rich
  previews and Apollo's original ones are combined into a single set of
  cards stacked at the end of a post, rather than two separate styles
  (Reborn's split comes from being a tweak on top of Apollo). YouTube
  links get a card, not inline video. Twitter/X previews have a fallback
  provider (for example fxtwitter) because Twitter's own embed is
  unreliable, and Bluesky and Twitter cards have a Compact mode to match
  the other previews.

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
- **Push notifications go through Bark or a self-hosted notification
  backend.** Phoebus has no APNs push: a build signed without a paid
  developer account has no push entitlement, so the backend delivers
  through Bark.
- **Remind Me uses local notifications.** Reminders are scheduled on the
  device through the system notification center, with no server-side
  reminder service, so they also work offline.
