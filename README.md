# Phoebus

Phoebus is an independent, from-scratch SwiftUI reimplementation of
[Apollo for Reddit](https://apolloapp.io)'s design and of the feature
set added by the Apollo Reborn tweak. It is a
native iOS Reddit client, built entirely on Linux with
[xtool](https://xtool.sh).

The name comes from Phoebus ("bright", "radiant"), the Greek epithet of
the god Apollo, often joined as Phoebus Apollo.

It is a personal, non-commercial project. It is not affiliated with or
endorsed by Christian Selig, Apollo or Reddit. See [Disclaimer](#disclaimer).

https://github.com/user-attachments/assets/0af89223-80c8-4dab-8c52-c2023812e959

## Installing

Phoebus is not on the App Store. Install it with AltStore or SideStore, or
sideload an IPA yourself; it runs on iOS 17 and later. However you install
it, you then need a Reddit API client ID of your own to sign in: see
[Configuration](#configuration).

### With AltStore or SideStore

There are no stable releases yet, so for now only the nightly source and
the `nightly` pre-release have builds.

Add one of these sources (in AltStore, Sources › +; in SideStore, Sources
› +), or open https://pendo324.github.io/AltStoreRepo/ on the device and
tap a link:

| Source | URL | Builds |
|---|---|---|
| pendo324 | `https://pendo324.github.io/AltStoreRepo/source.json` | Stable releases (none yet) |
| Phoebus Nightly | `https://pendo324.github.io/AltStoreRepo/nightly/source.json` | The last 20 builds of `main`. These can break. |

Then install Phoebus from the source. AltStore or SideStore signs it with
your Apple ID and offers an update whenever a new build is published. Both
sources install the same app (`com.pendo324.Phoebus`), so a device has one
or the other.

With a free Apple ID, apps installed this way must be refreshed every 7
days, which AltStore and SideStore do in the background. Each of Phoebus's
app extensions (widgets, Open in Apollo, Safari) uses one of the App IDs a
free account can register per week; if you run short, AltStore can
install the app without them.

### From an IPA

- **Stable:** `Phoebus-v<version>.ipa` from
  [Releases](https://github.com/pendo324/Phoebus/releases), once there is
  one (none yet).
- **Nightly:** the newest builds of `main` in the
  [`nightly` pre-release](https://github.com/pendo324/Phoebus/releases/tag/nightly).

The IPAs are unsigned. Open one in AltStore or SideStore, or sign it with
Sideloadly or a certificate signer (Feather, ESign, Ksign). With a
certificate signer, read [docs/widgets-and-signing.md](docs/widgets-and-signing.md)
first: the configurable widgets need the bundle identifier to match the
signing App ID.

### In the iOS Simulator

Each release also has a `-simulator.ipa`, one build for both Intel and
Apple Silicon Macs:

```bash
xcrun simctl install booted Phoebus-v<version>-simulator.ipa
```

To build Phoebus yourself, see [Building](#building). How the builds and
releases are made is in [docs/releases.md](docs/releases.md).

## Features

- **Feeds and subreddits.** Subreddit, multireddit, home, Popular and
  All listings with sorts, compact and large post rows, a jump bar,
  Gallery View (waterfall grid), community highlights, favourites,
  sections and custom layouts, search, and local filters (keywords,
  users, subreddits, flairs, tags, RES filter import).
- **Posts and comments.** Post detail with a recursive comment tree,
  depth bars, collapse animations, find-in-comments, optimistic
  voting, saving, sharing (including share as image), composers for
  comments and posts (polls, crossposts, Giphy, text faces) and Remind
  Me.
- **Media.** Images, galleries, Imgur albums, animated GIF/APNG/WebP,
  Reddit video, RedGifs, Streamable, Vimeo, YouTube, tweets and other
  link preview cards, a fullscreen viewer with Live Text and hold-for-
  speed video scrubbing, floating picture in picture, and saving and
  downloading media.
- **Inbox, chat and modmail.** Inbox with unread badge, native Reddit
  Chat (a Matrix client) with a persistent send queue, threads and
  reactions, and modmail over a web session.
- **Profiles and moderation.** Profile layouts, badge book, saved
  categories, a mod queue, removal reasons, mod log, banned and muted
  users, invites, AutoModerator configuration and subreddit traffic.
- **Gestures.** Apollo's back and forward page swipes, configurable row
  swipe actions, double-tap to upvote, and hold-and-drag scrubbing.
- **Settings.** Apollo's settings tree plus Reborn's hub (interface,
  posts and feeds, comments, media, translation, AI summaries, deleted
  comment recovery, picture in picture and more), searchable, with
  Apollo and Reborn backup import (`.apollobackup`), JSON backups and
  automatic backups.
- **Themes and appearance.** A theme gallery, an editor, AI theme
  generation, QR sharing, automatic switching by time or sunset, pure
  black tiers, Liquid Glass surfaces and alternate app icons.
- **Extensions.** WidgetKit widgets and a Live Activity, a Share Sheet
  "Open in Apollo" action, a Safari web extension, and App Intents for
  Shortcuts.

Places where Phoebus deliberately differs from Apollo and Reborn are
listed in [docs/intentional-differences.md](docs/intentional-differences.md).

## Requirements

- A Reddit API client ID of your own (see [Configuration](#configuration)).
- To build: Swift 6.4, a fork of [xtool](https://xtool.sh) that
  `scripts/install-xtool.sh` builds for you, and a Darwin SDK built from
  **Xcode 27**. The project is developed and built on Linux; see
  [docs/building-on-linux.md](docs/building-on-linux.md).
- Target platform: iOS 17 and later, with the iOS 26 design on iOS 26.
  Newer APIs are guarded (see [docs/conventions.md](docs/conventions.md),
  "Minimum iOS: 17").

## Building

All commands run from the repository root.

```bash
xtool dev build            # produces xtool/Phoebus.app
xtool dev build --ipa      # produces a .ipa
xtool dev run              # builds and installs on a connected device
```

On Linux, see [docs/building-on-linux.md](docs/building-on-linux.md) for the
toolchain requirements, the workarounds the scripts apply and how to
override them locally. To build for the iOS Simulator without a Mac:

```bash
scripts/build-for-simulator.sh                    # x86_64 simulator triple
scripts/build-for-simulator.sh arm64-apple-ios-simulator  # Apple Silicon simulator
```

The simulator build is also the compile check for `PhoebusUI` and the app
target, since the host-side tests only build `PhoebusCore`. Installing the
result into a simulator needs `simctl`, which only exists on macOS.

To build the same IPAs the releases have, device and simulator (see
[docs/releases.md](docs/releases.md)):

```bash
scripts/build-ipa.sh --simulator dist
```

If xtool fails with `.../swift-sdks doesn't exist`, `xcode-select` is
pointing at the Command Line Tools instead of a full Xcode:
`sudo xcode-select -s /Applications/Xcode.app`.

### Tests

`PhoebusCore` has no UIKit dependency, so its logic is tested by a
standalone executable, `PhoebusCoreSmokeTest`, that runs on the Linux
host:

```bash
swift build --target PhoebusCore                  # compile the core library
SMOKE_SKIP_IOS=1 scripts/smoke.sh                # build and run the smoke tests
scripts/smoke.sh                                 # the same, then the iOS build
```

`scripts/smoke.sh` prints `SMOKE: ok (N passed)` on success and reports
failures, crashes and a missing terminator line with distinct exit
codes. The app deploys to iOS 17, so the iOS build fails on any newer
API used without an availability guard.

## Project layout

| Path | Contents |
|---|---|
| `Sources/PhoebusCore` | Foundation-only library: models, networking, settings stores, theming and pure policies. Builds on Linux. |
| `Sources/PhoebusUI` | SwiftUI and UIKit screens, components, media views and gesture recognizers. |
| `Sources/Phoebus` | The app target: `@main`, the tab bar, deep links, App Intents. |
| `Sources/PhoebusWidget` | WidgetKit extension and Live Activity. |
| `Sources/PhoebusOpenIn` | Share Sheet action extension. |
| `Sources/PhoebusSafari`, `SafariExtension/` | Safari web extension handler and its JavaScript. |
| `Sources/PhoebusCoreSmokeTest` | The test suite: `main.swift` plus `Checks/<Area>.swift`. |
| `Tests/Fixtures` | JSON fixtures read by the tests. |
| `Config/` | Per-target `Info.plist`, entitlements and the App Intents protocol list. |
| `Icons/Standard/<id>/` | The standard alternate icons, one folder per icon, listed in `xtool.yml`. Apollo's artwork, extracted from its IPA at build time and not checked in. |
| `Icons/LiquidGlass/<group>/<id>/` | The Liquid Glass icons as Icon Composer sources (`<id>.icon`), rendered to PNGs at build time by `scripts/generate-icons.sh`; `icons.json` lists them. |
| `scripts/` | Build, smoke-test and check scripts; `scripts/generate/` holds the generators and audits. |
| `docs/` | Architecture, conventions, components, gestures, protocol notes, building on Linux and releases. |

Start with [docs/architecture.md](docs/architecture.md) for how the
targets fit together, and [docs/components.md](docs/components.md) to
find the code for a feature.

## Configuration

Phoebus does **not** include or reuse Apollo's Reddit client ID, which
belongs to its developer. You supply your own:

1. Register an app at <https://www.reddit.com/prefs/apps> with type
   "installed app" and a redirect URI of `phoebus://oauth-callback` (the
   default, `RedditOAuthConfig.defaultRedirectURI`).
2. In the app, open **Custom API Settings** on the sign-in screen (or,
   once signed in, Settings, Apollo Reborn, Accounts & API Keys, Default
   API Keys) and enter the Reddit API key (client ID), the redirect URI
   and a User Agent. An API secret is only needed for "web app" clients.
   The values are stored on the device and override the build-time
   defaults.

The build-time default in
`Sources/PhoebusCore/Accounts/Auth/RedditAuthClient.swift`
(`RedditOAuthConfig.defaultClientID`) is the placeholder
`REPLACE_WITH_YOUR_CLIENT_ID`; you can also edit it there. Without a
client ID, OAuth sign-in cannot work. A web-session sign-in (cookies,
no API key) is available for accounts that cannot get one, which is also
what Reddit Chat and modmail use.

Imgur, Image Chest and Giphy keys, needed for uploading images, inline
albums and the GIF picker, are entered on the same screens. RedGifs uses
its public keyless temporary-token endpoint.

To use the widgets' personalised feed, the app and widget need a shared
App Group; see `Config/Phoebus/Phoebus.entitlements`, `Config/PhoebusWidget/PhoebusWidget.entitlements`,
`SharedFeedCache.appGroupID` and
[docs/widgets-and-signing.md](docs/widgets-and-signing.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Coding agents should also read
[AGENTS.md](AGENTS.md).

## Credits

- [Apollo for Reddit](https://apolloapp.io) by Christian Selig, whose
  design and behaviour Phoebus reimplements.
- Apollo Reborn, the tweak that extended Apollo with the features Phoebus
  also reproduces.
- [xtool](https://xtool.sh), which makes building iOS apps on Linux
  possible.
- [AnimatedImage](https://github.com/noppefoxwolf/AnimatedImage) and
  [KSCrash](https://github.com/kstenerud/KSCrash), both SwiftPM dependencies.

## Disclaimer

Phoebus is a personal, non-commercial project and an independent
reimplementation: it contains no Apollo source code, binaries, artwork or
private credentials. Apollo's standard icons are extracted from Apollo's
own IPA when you build. It is not affiliated with, authorised or endorsed by
Christian Selig, the Apollo or Apollo Reborn projects, or Reddit. "Apollo"
and "Reddit" are trademarks of their respective owners and are used here
only to describe what Phoebus is compatible with.

## License

Phoebus is free software, licensed under the GNU General Public License,
version 3; see [LICENSE](LICENSE). The Liquid Glass icon sources in
`Icons/LiquidGlass` come from Apollo Reborn, which is GPL-3.0 as well.
Dependencies keep their own licenses: AnimatedImage (MIT) and KSCrash
(MIT).
