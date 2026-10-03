# Widgets and signing

The configurable widgets (Post, Feed, Photo, Calendar, Headline,
Shortcuts) only work when the app is installed under the same App ID it
was signed with. The widgets with no settings (Showerthoughts, Jokes,
Actions) work either way.

## The issue

A configurable widget gets its settings (feed, sort, caption, ...)
from iOS: the widget extension asks the Shortcuts service
(`siriactionsd`) to resolve its App Intent configuration. That service
identifies the caller by the `application-identifier` in its code
signature, not by its bundle identifier, and only answers callers whose
App ID belongs to an installed app.

Certificate signers (Feather, ESign, Ksign, zsign) sign every bundle
with the provisioning profile's entitlements as they are. A profile
made for an explicit App ID, e.g. `TEAM.app.example.slot1`, gives the
app and its widget extension that `application-identifier`, while the
app keeps its own bundle identifier (`com.pendo324.Phoebus`). No
installed app is called `app.example.slot1`, so the Shortcuts service
refuses the widget, the widget never receives its settings, and iOS
never asks it for a snapshot or timeline. The widget stays a blank
placeholder.

No change in the app can fix this. The `application-identifier` must
match the profile, and the service checks it before any app code runs.

## The fix

The bundle identifier and the signing App ID have to agree. Either:

- **Rename the bundle identifier when signing.** In Feather, set
  *Identifier* to the certificate's App ID (the part after the team
  ID). Feather renames the widget extension to match. To keep it for
  every update, add a bundle identifier mapping in Feather's signing
  options, from `com.pendo324.Phoebus` to the App ID. Ksign has a
  button that fills in the certificate's App ID. A new identifier
  counts as a new app, so export a backup from the old install first.
- **Sign it properly.** With a developer account, register an App ID
  for the app (and one for the widget extension) and sign and
  distribute it under those, as Xcode does. The App IDs then
  match the bundle identifiers.

A wildcard profile (`TEAM.*`) also works, since the signed App ID then
covers any bundle identifier.

## Checking an install

Settings › Apollo Reborn › Accounts & API Keys › Copy Widget Setup Code
shows a Status section:

- **Editable Widgets: Blocked by signing** means the App ID and bundle
  identifier differ; the footer names the identifier to sign with.
- **App Group: Not granted** means the signing gave no App Group, so
  the widgets can't read the feed or sign-in and only show public
  subreddits.
