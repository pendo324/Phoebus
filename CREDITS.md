# Credits

Phoebus stands on the work of two projects. This page says exactly what
comes from where.

Crediting someone here does not mean they are involved with Phoebus.
Phoebus has no connection with, and is not endorsed or supported by,
Apollo Reborn or its maintainers, Christian Selig or Apollo, or Reddit.
Please don't contact them about Phoebus.

## What Phoebus is made of

- **The core app is written from scratch.** The SwiftUI and UIKit
  interface, the Reddit API client, the settings system, theming, the
  comment tree, media viewers, gestures, widgets and extensions are
  original Swift code. Apollo is the design reference: Phoebus recreates
  how Apollo looks and behaves, but contains none of Apollo's source code.
- **Apollo Reborn's features are ported from Apollo Reborn's code.**
  [Apollo Reborn](https://github.com/Apollo-Reborn/Apollo-Reborn) is an
  open-source tweak, licensed under the GNU GPL version 3, that extends
  Apollo with features of its own. Phoebus implements those features by
  porting Reborn's source directly: its Objective-C and Logos code is
  translated to Swift, keeping its logic, settings keys, defaults,
  thresholds and fixes. Examples include Reborn's settings hub, Bark and
  self-hosted notifications, web-session sign-in, the Badge Book, rich
  link previews, AI summaries, translation, deleted-comment recovery,
  backups and the theme gallery. Code comments name the Reborn
  feature or issue a piece of code comes from.
- **Some Apollo Reborn files are included as they are.** The Liquid Glass
  icon sources in `Icons/LiquidGlass` come from Apollo Reborn.
- **Reddit's achievement artwork.** The Badge Book images and catalog in
  `Sources/PhoebusUI/Resources/BadgeBook` are Reddit's own achievement and
  trophy images, taken from the set Apollo Reborn bundles.
- **No Apollo artwork.** The interface glyphs are SF Symbols, the
  open-source icons listed under [Icons](#icons), and drawings original
  to Phoebus (the subreddit tag, the SpongeText and Text Faces glyphs,
  and the SF compositions for the slashed vote arrows, collapse to root,
  hide posts above, parent comment, multireddit and subreddit wiki).
  Apollo's app icons are not in the repository (see
  [Build-time inputs](#build-time-inputs)).

Because Phoebus contains code derived from Apollo Reborn, it is licensed
under the GNU GPL version 3 as well (see [LICENSE](LICENSE)). The Apollo
Reborn parts remain the work of the Apollo Reborn contributors listed
below, and the copyright in them is theirs.

## Apollo Reborn contributors

Thank you to everyone who built Apollo Reborn. Without their work, most
of what Phoebus does beyond Apollo itself would not exist. This list is
taken from Apollo Reborn's own
[contributors list](https://github.com/Apollo-Reborn/Apollo-Reborn#contributors-).

**Maintainers:**
JeffreyCA,
icpryde,
jordanearle,
nickclyde,
DeltAndy123,
IllIIllIllIllII

**Code:**
EthanArbuckle,
iCrazeiOS,
hllvc,
yodaluca23,
ep0chzero,
mmshivesh,
Uranosphaerite,
wdeezy,
ryannair05,
ichitaso,
epheterson,
nunoo,
lampemw,
rebelancap,
nackerr,
Alstruit,
federgilad,
ostechgit,
JamesLautner,
Thetromboneman1,
jaredrossberg,
paradoxally

**Icons and design:**
iGerman00,
jryng,
bajader,
metalnakls,
paulo1manso,
lilacvibes,
harshb16,
AcornElf,
harumatsu

The app's Thanks To screen (Settings › About › Apollo Reborn Contributors,
or Settings › Apollo Reborn › Thanks To) shows the same list, loaded from
Apollo Reborn's `contributors.json`, so it stays current.

## Ported features

Phoebus features ported from a specific Apollo Reborn pull request, with
the pull request's author. Pull requests are written in backticks and
authors by GitHub username without an @, so nothing here notifies them.
Features ported before Phoebus tracked individual pull requests (the
settings hub, notifications, web-session sign-in, the Badge Book, link
previews, AI summaries, translation, deleted-comment recovery, backups,
the theme gallery and more) are the work of the Reborn contributors as a
whole; Reborn's own [changelog](https://github.com/Apollo-Reborn/Apollo-Reborn/blob/main/CHANGELOG.md)
says who wrote what.

| Phoebus feature | Reborn PR | Author |
|---|---|---|
| Subreddit Headers: custom local banners and icons | `Apollo-Reborn#266` | icpryde, jordanearle |
| Hidden `&#x200B;` and trailing blank lines trimmed from posts and comments | `Apollo-Reborn#405` | JeffreyCA |
| Multireddits: Gallery View, renaming, descriptions and custom icons | `Apollo-Reborn#799`, `Apollo-Reborn#837` | icpryde |
| Collapsible Liquid Glass navigation actions | `Apollo-Reborn#1035`, `Apollo-Reborn#1047` | IllIIllIllIllII |
| Find in Comments search bar | `Apollo-Reborn#1036` | icpryde |
| Sort Favorites Alphabetically | `Apollo-Reborn#1042` | IllIIllIllIllII |
| Save All Media | `Apollo-Reborn#1048` | IllIIllIllIllII |
| No oversized paragraph gaps after a stripped `&#x200B;` | `Apollo-Reborn#1050` | icpryde |
| Hidden header style | `Apollo-Reborn#1074` | IllIIllIllIllII |
| Swipe Tab Bar to Navigate | `Apollo-Reborn#1075` | DeltAndy123 |
| Account Switcher sheet | `Apollo-Reborn#1077` | IllIIllIllIllII |
| Hide Header on Scroll | `Apollo-Reborn#1079` | IllIIllIllIllII |
| Action Menus | `Apollo-Reborn#1131` | icpryde |
| Profile Picture Shape | `Apollo-Reborn#1136` | IllIIllIllIllII |
| Hidden & Deleted | `Apollo-Reborn#1137` | IllIIllIllIllII |
| Gallery View grid autoplay | `Apollo-Reborn#1142` | icpryde |
| Settings Shortcuts | `Apollo-Reborn#1150` | IllIIllIllIllII |
| Posts tab re-tap scrolls to the top before going back | `Apollo-Reborn#1153` | IllIIllIllIllII |
| Row highlight colours | `Apollo-Reborn#1166` | IllIIllIllIllII |
| Confirm Favorite Changes | `Apollo-Reborn#1173` | nunoo |
| Immersive profile headers | `Apollo-Reborn#1186` | IllIIllIllIllII |
| Search tab keyboard on re-tap | `Apollo-Reborn#1190` | IllIIllIllIllII |
| Posted comment fade-in | `Apollo-Reborn#1196` | icpryde |
| Chat drafts | `Apollo-Reborn#1207` | Thetromboneman1 |
| API-Key-Free avatar lookups within the session limit | `Apollo-Reborn#1220` | icpryde |
| Unmute Videos in Feed: one audible video, muted under fullscreen | `Apollo-Reborn#1250`, `Apollo-Reborn#1252` | icpryde |
| Toon Bot icons | `Apollo-Reborn#1253` | IllIIllIllIllII |
| Image menu anchored at the press | `Apollo-Reborn#1254` | IllIIllIllIllII |
| Google Search | `Apollo-Reborn#1260` | icpryde |
| Interactive posts: permission prompt and subscription sync | `Apollo-Reborn#1264` | icpryde |
| Swipe Past Gallery to Navigate | `Apollo-Reborn#1271` | Thetromboneman1 |
| Comment links on shared media | `Apollo-Reborn#1278` | Thetromboneman1 |
| Touch-and-hold menus follow the Action Menus layout | `Apollo-Reborn#1282` | icpryde |
| Crosspost title | `Apollo-Reborn#1290` | icpryde |
| Keyless moderators' removal reasons, user lists and modmail | `Apollo-Reborn#1298`, `Apollo-Reborn#1304`, `Apollo-Reborn#1311` | icpryde |
| Siri & Spotlight | `Apollo-Reborn#1299` | jordanearle |
| Kagi Search | `Apollo-Reborn#1305` | nickclyde |
| Message Copy Text / Select Text | `Apollo-Reborn#1307` | icpryde |
| Post flair and wiki saves | `Apollo-Reborn#1309` | icpryde |
| Subreddit Switcher Sheet | `Apollo-Reborn#1313` | IllIIllIllIllII |
| True Black Keyboard | `Apollo-Reborn#1316` | IllIIllIllIllII |
| Open via Nitter | `Apollo-Reborn#1334` | nickclyde |
| In-App Update Prompt | `Apollo-Reborn#1343` | IllIIllIllIllII |
| Minimize tab bar style and navigation reveals | `Apollo-Reborn#1349` | IllIIllIllIllII |
| Subreddits settings regrouped | `Apollo-Reborn#1350` | IllIIllIllIllII |
| Subreddit List Sections previews | `Apollo-Reborn#1351` | IllIIllIllIllII |
| User Profiles settings | `Apollo-Reborn#1352` | IllIIllIllIllII |
| Load more replies smoothly | `Apollo-Reborn#1358` | icpryde |
| RedGIFs failure reasons | `Apollo-Reborn#1359` | icpryde |
| Posts tab re-tap saves your place | `Apollo-Reborn#1360` | IllIIllIllIllII |
| Summary Language | `Apollo-Reborn#1362` | icpryde |
| Action Menus settings and Remind Me In… | `Apollo-Reborn#1368` | icpryde, building on `Apollo-Reborn#1300` by AcornElf |
| Sign-in popups for Google and Apple | `Apollo-Reborn#1372` | icpryde |

## Apollo

[Apollo for Reddit](https://apolloapp.io) by Christian Selig, the app
whose design and behaviour Phoebus recreates. Phoebus is not affiliated
with or endorsed by Christian Selig.

## Inspired by

Some Phoebus-only features are inspired by features in other open-source
Reddit clients. No code is taken from either; Phoebus implements the
idea in its own code. Each one is described in
[docs/intentional-differences.md](docs/intentional-differences.md).

- [Continuum](https://github.com/cygnusx-1-org/continuum) (AGPL-3.0):
  Other Discussions, Recently Visited, crosspost destination
  suggestions, quarantine opt-in, Copy Multireddit, Post Rules, removed
  post and comment recovery, Local Saved, video playback options, NSFW
  and Spoiler switches in the post composer, Comment Filters, search
  history and user search, the edited-time display, the followed-user
  highlight, hidden scores, text sizes and fonts, Remember Thread
  Position, Resume Where I Left Off and separate settings per account.
- [RedReader](https://github.com/QuantumBadger/RedReader) (GPL-3.0):
  relative comment ages, the own-username highlight, and text sizes and
  fonts.

## Build-time inputs

Apollo's standard app icons are Apollo's artwork, so they are not in the
repository. `scripts/generate-icons.sh` extracts them (the `AppIcon-*`
images of each icon listed in `xtool.yml`) from an Apollo IPA that
whoever builds Phoebus supplies through `PHOEBUS_APOLLO_IPA`, a path or a
URL (see [docs/building-on-linux.md](docs/building-on-linux.md)). The IPA
and the extracted images are never committed.

## Attribution style

Code ported from Apollo Reborn is credited by the Reborn feature's name
and Reborn PR number, written as plain text: in code comments as
`Reborn "Kagi Search" (#1305)`, and in commit messages and pull requests
in backticks, as `Apollo-Reborn#1305`. Contributors are named without an @
and without links to Reborn's pull requests or issues, and Reborn
authors are not added as `Co-authored-by`, since each of those notifies
people on Reborn's side. This page keeps the full list of who to thank.

## Icons

A few interface glyphs are open-source icons, bundled as vector PDFs in
`Sources/PhoebusUI/Resources/Glyphs` with their source SVGs and full
licence texts (`LICENSES.md` there). Everything else is an SF Symbol,
used by name and not redistributed, or drawn for Phoebus.

- **Phosphor Icons** (`checks`, `reddit-logo` light), from
  [phosphor-icons/core](https://github.com/phosphor-icons/core) v2.1.1.
  MIT License, Copyright (c) 2023 Phosphor Icons.
- **Lucide** (`swords`, `arrow-up-wide-narrow`, `bold`, `italic`, `quote`,
  `heading`), from [lucide-icons/lucide](https://github.com/lucide-icons/lucide)
  (`lucide-static` 1.55.0). ISC License, Copyright (c) 2026 Lucide Icons
  and Contributors. `italic` is derived from Feather: MIT License,
  Copyright (c) 2013-present Cole Bemis.
- **Tabler Icons** (`shield-star`, also redrawn at stroke 2.25 for the
  moderator orb), from [tabler/tabler-icons](https://github.com/tabler/tabler-icons)
  3.49.0. MIT License, Copyright (c) 2020-2026 Paweł Kuna.
- **Font Awesome Free** (brand icon `twitter`), from
  [Font Awesome](https://fontawesome.com) 7.3.1 by Fonticons, Inc.,
  licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- **Simple Icons** (`wikipedia`), from
  [simple-icons](https://github.com/simple-icons/simple-icons) 16.35.0,
  CC0 1.0.
- Reddit, the Snoo, Twitter and Wikipedia are trademarks of their
  respective owners (Reddit, Inc.; X Corp.; Wikimedia Foundation). They
  are used only to label links to those services and do not imply any
  affiliation or endorsement.

## Tools and libraries

- [xtool](https://xtool.sh), which makes building iOS apps on Linux
  possible.
- [AnimatedImage](https://github.com/noppefoxwolf/AnimatedImage) (MIT) and
  [KSCrash](https://github.com/kstenerud/KSCrash) (MIT), both SwiftPM
  dependencies.
