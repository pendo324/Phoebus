# Credits

Phoebus stands on the work of two projects. This page says exactly what
comes from where.

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
[JeffreyCA](https://github.com/JeffreyCA),
[icpryde](https://github.com/icpryde),
[jordanearle](https://github.com/jordanearle),
[nickclyde](https://github.com/nickclyde),
[DeltAndy123](https://github.com/DeltAndy123),
[IllIIllIllIllII](https://github.com/IllIIllIllIllII)

**Code:**
[EthanArbuckle](https://github.com/EthanArbuckle),
[iCrazeiOS](https://github.com/iCrazeiOS),
[hllvc](https://github.com/hllvc),
[yodaluca23](https://github.com/yodaluca23),
[ep0chzero](https://github.com/ep0chzero),
[mmshivesh](https://github.com/mmshivesh),
[Uranosphaerite](https://github.com/Uranosphaerite),
[wdeezy](https://github.com/wdeezy),
[ryannair05](https://github.com/ryannair05),
[ichitaso](https://github.com/ichitaso),
[epheterson](https://github.com/epheterson),
[nunoo](https://github.com/nunoo),
[lampemw](https://github.com/lampemw),
[rebelancap](https://github.com/rebelancap),
[nackerr](https://github.com/nackerr),
[Alstruit](https://github.com/Alstruit),
[federgilad](https://github.com/federgilad),
[ostechgit](https://github.com/ostechgit),
[JamesLautner](https://github.com/JamesLautner),
[Thetromboneman1](https://github.com/Thetromboneman1),
[jaredrossberg](https://github.com/jaredrossberg),
[paradoxally](https://github.com/paradoxally)

**Icons and design:**
[iGerman00](https://github.com/iGerman00),
[jryng](https://github.com/jryng),
[bajader](https://github.com/bajader),
[metalnakls](https://github.com/metalnakls),
[paulo1manso](https://github.com/paulo1manso),
[lilacvibes](https://github.com/lilacvibes),
[harshb16](https://github.com/harshb16),
[AcornElf](https://github.com/AcornElf),
[harumatsu](https://www.reddit.com/user/harunatsu91202024/)

The app's Thanks To screen (Settings › About › Apollo Reborn Contributors,
or Settings › Apollo Reborn › Thanks To) shows the same list, loaded from
Apollo Reborn's `contributors.json`, so it stays current.

## Apollo

[Apollo for Reddit](https://apolloapp.io) by Christian Selig, the app
whose design and behaviour Phoebus recreates. Apollo's standard app icons
are extracted from Apollo's own IPA when Phoebus is built. Phoebus is not affiliated with or endorsed by Christian Selig.

## Tools and libraries

- [xtool](https://xtool.sh), which makes building iOS apps on Linux
  possible.
- [AnimatedImage](https://github.com/noppefoxwolf/AnimatedImage) (MIT) and
  [KSCrash](https://github.com/kstenerud/KSCrash) (MIT), both SwiftPM
  dependencies.
