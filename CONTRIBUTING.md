# Contributing to Phoebus

Thanks for your interest. Phoebus is a personal, non-commercial project,
so changes are reviewed with that scope in mind: small, focused and in
keeping with how Apollo and Apollo Reborn behave.

## Building

You need Swift 6.4, the xtool that `scripts/install-xtool.sh` builds, and
a Darwin SDK built from Xcode 27;
[docs/building-on-linux.md](docs/building-on-linux.md) covers the
toolchain setup and known issues. From the repository root:

```bash
scripts/build-for-simulator.sh    # compiles PhoebusUI and the app for the iOS Simulator
xtool dev build                     # builds xtool/Phoebus.app for a device
swift build --target PhoebusCore     # fast check for core code (Linux or macOS)
```

`scripts/build-for-simulator.sh` is the compile check for `PhoebusUI` and the
app target; the host-side tests only build `PhoebusCore`. Sign-in needs
your own Reddit client ID, entered under Custom API Settings on the
sign-in screen.

## Running the checks

```bash
SMOKE_SKIP_IOS=1 scripts/smoke.sh  # builds and runs the smoke tests
scripts/smoke.sh                   # the same, then the iOS build
```

The smoke suite (`Sources/PhoebusCoreSmokeTest`) must print
`SMOKE: ok (N passed)`. Please run it, and the iOS build, before opening
a pull request.

When you add behaviour:

- Put logic that does not need UIKit in `PhoebusCore` and cover it with
  a `check("name", condition)` in the matching `Checks/<Area>.swift`.
  Checks call real code and assert on the result; they do not read
  source files.
- If a check fails because behaviour legitimately changed, update it
  with a one-line reason. Do not delete it.
- If you add or rename a settings row, regenerate the search index:
  `python3 scripts/generate/gen-settings-search-index.py Sources/PhoebusUI Sources/PhoebusCore/Settings/Search/SettingsSearchIndexData.swift`.

## Code style

- Match the surrounding code: naming, structure and comment density.
- Comments are short and say which Apollo/Reborn feature something is
  and why. Leave out debugging history; put that in the commit message.
- Swift 6 language mode. APIs newer than iOS 17 go behind `#available`
  or a shim in `Shared/Utilities/Compatibility.swift`.
- Use `@Setting` in views and `update { ... }` for writes; no `@State`
  copies of stored settings.
- Use Apollo's `UserDefaults` keys where Apollo has the setting, so
  backups import.
- Add `.accessibilityIdentifier` to new interactive controls and an
  accessibility label to icon-only buttons.
- No leftover `NSLog` debugging.

The full guide is in [docs/conventions.md](docs/conventions.md); the
layout and recipes are in [docs/architecture.md](docs/architecture.md)
and [docs/components.md](docs/components.md).

## Commit messages

- An imperative subject of at most 72 characters ("Add inbox unread
  badge"), optionally prefixed with the area ("Gallery viewer: ...").
- A blank line, then a short body when the change needs explaining:
  what and why, not a debugging diary.
- Describe the feature or behaviour. Keep a version bump in its own
  commit.

## Pull requests

- One logical change per pull request, with a description of what
  changed and why.
- The app builds and the smoke suite passes.
- Mention anything you could only check on a device.
- Don't mix refactors or formatting changes into a feature.

## Differences from Apollo

Phoebus aims to match Apollo and Apollo Reborn. If your change knowingly
differs (a removed row, a changed default, a different mechanism), add
an entry to [docs/intentional-differences.md](docs/intentional-differences.md)
saying what differs and why.

## Apollo's assets and credentials

Do not add Apollo's app binaries, artwork or private credentials. Only the assets already bundled in this repository may be
used. Never use Apollo's Reddit client ID; API keys belong to the person
running the app.

## Conduct

Be kind and respectful, assume good faith, and keep discussion on the
work.
