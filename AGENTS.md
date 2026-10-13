# Phoebus: guide for coding agents

Phoebus is a SwiftUI reimplementation of Apollo for Reddit's design and
Apollo Reborn's features, built entirely on Linux with xtool. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the human-facing rules. The version comes
from the release tags (`scripts/version.sh`; releases are cut by
semantic-release, see [docs/releases.md](docs/releases.md)), not from
`Config/Phoebus/Info.plist`; the smoke run prints the current assertion count.

## Docs

| Doc | Read when |
|---|---|
| [docs/building-on-linux.md](docs/building-on-linux.md) | Toolchain setup, what each script does, build workarounds, AppIntents metadata, the Darwin SDK. |
| [docs/releases.md](docs/releases.md) | GitHub Actions builds, the nightly and stable releases, the AltStore sources, cutting a release. |
| [docs/architecture.md](docs/architecture.md) | Touching code: targets, directory map, where things live, key singletons. |
| [docs/components.md](docs/components.md) | Finding the code for a feature: every notable sub-component, its files, the Apollo/Reborn feature it reproduces, key flows, settings and persistence maps, recipes. |
| [docs/conventions.md](docs/conventions.md) | Writing code or comments: house style, comment policy, minimum iOS, smoke-assertion style, commits. |
| [docs/gestures.md](docs/gestures.md) | Anything touching swipes, scrubs or navigation gestures. |
| [docs/intentional-differences.md](docs/intentional-differences.md) | Before "fixing" something back to upstream behaviour, and when adding a deliberate difference. |
| [docs/widgets-and-signing.md](docs/widgets-and-signing.md) | Widgets that stay blank under a certificate signer. |
| [docs/chat-sending-and-threads.md](docs/chat-sending-and-threads.md) | Reddit Chat (Matrix): sending, the outbox, threads, reactions. |
| [docs/modmail-web-session.md](docs/modmail-web-session.md) | Modmail over a web session (Shreddit GraphQL). |

## The short version

```bash
# 1. Edit Sources/...
# 2. Compile PhoebusUI and the app (the only way to compile them):
scripts/build-for-simulator.sh 2>&1 | grep -E " error:|Build complete"
# 3. Host-side smoke tests (PhoebusCore only); skip the iOS rebuild you just did:
SMOKE_SKIP_IOS=1 scripts/smoke.sh       # must print "SMOKE: ok (N passed)"
# 4. Commit scoped paths with an imperative message.
```

- `swift build --target PhoebusCore` is the fast compile check for core
  code. `PhoebusUI` and the app only build through xtool
  (`scripts/build-for-simulator.sh`, or `xtool dev build`).
- `scripts/xtool-env.sh` is sourced by the build scripts. It sets
  `XTOOL`, `SANDBOX` and `SWIFT_BUILD`, and sources `scripts/local.sh`
  (gitignored) if present for machine-specific toolchain workarounds.
  Build with `"${SWIFT_BUILD[@]}"` rather than a bare `swift build`. See
  [docs/building-on-linux.md](docs/building-on-linux.md).
- The deployment target is iOS 17, so the iOS build fails on any newer
  API used without `#available`; see docs/conventions.md.
- `scripts/smoke.sh` exit codes: 1 assertion failures, 2 build failed,
  3 crashed mid-run, 4 ended without the `ALL CHECKS PASSED` terminator,
  5 iOS build failed, 6 App Intents metadata differs, 7 settings search
  index stale (regenerate it, see "A setting"). Do not grep for `FAIL` yourself; the script exists
  because that is unsafe.
- Long builds: a clean build takes several minutes, incremental ones
  seconds. Run anything over a minute in the background.

## Layout

| Target | Notes |
|---|---|
| `PhoebusCore` | Foundation only; builds on Linux. Models, networking, settings stores, theming, pure policies. All testable logic goes here. |
| `PhoebusUI` | Screens, components, media, gesture recognizers. A thin shell over Core policies. |
| `Phoebus` | `PhoebusApp.swift`, `AppIntents.swift`, `Siri*.swift`. |
| `PhoebusWidget`, `PhoebusOpenIn`, `PhoebusSafari` | Extensions. |
| `PhoebusCoreSmokeTest` | The test suite: `main.swift` plus `Checks/<Area>.swift`. |

See [docs/architecture.md](docs/architecture.md) for the full map.

## Conventions

Summarised from [docs/conventions.md](docs/conventions.md); read it
before writing code.

- Match the surrounding style, naming and comment density. Comments say
  which Apollo/Reborn feature something is and why, in one to three
  lines; no fix history, no citations into other projects.
- Pure logic lives in `PhoebusCore` so the smoke suite can assert it.
- Real Apollo `UserDefaults` keys are used verbatim where Apollo has the
  setting, so backups import. Do not invent constants when a real one
  exists; if Apollo never had one, say so in a line.
- Anything newer than iOS 17 goes behind `#available` or a shim in
  `Shared/Utilities/Compatibility.swift`.
- Swift 6 language mode.
- Add `.accessibilityIdentifier("area.thing")` to new interactive
  controls and `.accessibilityLabel` to icon-only buttons.
- No leftover debug `NSLog`s (grep `APOLLO_` before committing).

## Settings architecture

Every setting goes through one layer, `Sources/PhoebusCore/Settings/Store/SettingsStore.swift`:

- `SettingsStore<Model>`: a Codable model as JSON under one key.
- `DefaultsKey<Value>`: one plain value under a stock Apollo/Reborn key.
- `CustomSettingsSource<Value>`: a value spanning several keys or
  validated on read.

All share `load`, `save` (whole value, for restores and imports) and
`update { $0.field = x }` (read-modify-write, the only write the UI
uses), and every save posts `.apolloSettingsChanged`. Each group is a
`Codable` struct plus an `XStore` enum in its feature folder exposing
`storage`.

In views use `@Setting` only (`Settings/Rows/Setting.swift`):

```swift
@Setting(GeneralSettings.self) private var general
Toggle("…", isOn: $general.showUserProfilePictures)   // writes one field
$general.update { $0.a = 1; $0.b = 2 }                // several fields
```

Never keep a `@State` copy of a stored setting and never save a whole
value from the UI. `XStore.load()` is fine in actions, initializers and
non-view code.

With "Separate Settings per Account" on, a `SettingsStore` reads the
active account's partial override (`<key>@<username>`) over the global
value and writes changed fields there; a store holding credentials,
device state or data belongs in `AccountSettingsOverrides.globalOnlyKeys`.
See docs/components.md, "Separate Settings per Account".

## How to add things

Full recipes are in [docs/components.md](docs/components.md), "Recipes".

**An icon**: prefer an SF Symbol available on iOS 17, then an icon from
a kit already in `Resources/Glyphs`; never Apollo's art. Add a recipe to
`StockGlyph` (Core) sized optically, regenerate kit PDFs with
`scripts/generate/gen-glyph-pdfs.sh` (licence in `LICENSES.md` and
CREDITS.md), add the name to `checkStockGlyphs`, and check on the
simulator that it isn't clipped. See docs/components.md, "Interface
glyphs".

**A setting**
1. Add the property with a default to the settings struct in
   its `PhoebusCore/<Feature>/` folder; decoding must tolerate its absence
   (`decodeIfPresent`).
2. If Apollo or Reborn has it, import it in
   `ApolloSettingsMigration+Reborn.swift` (`rebornKeys` plus a `take(...)`
   line, or `notImported` with a reason) and use their registered default.
3. Add the row through `$settings.field`, ending with
   `.apolloSearchRow("Title")`.
4. Regenerate the search index:
   `python3 scripts/generate/gen-settings-search-index.py Sources/PhoebusUI Sources/PhoebusCore/Settings/Search/SettingsSearchIndexData.swift`.
   Never edit the data file by hand: `scripts/smoke.sh` runs the generator
   with `--check` and fails when it differs. To leave a row out, make it
   conditional or index a menu choice, put a `// search: skip`,
   `// search: requires <tag>` or `// search: item "Title"` comment on the
   row's line or the line above (see docs/components.md).
5. Add a Core value check if there is any logic.

**A settings screen**: `List` with `.apolloFlatListAppearance()` (never
`Form`), section headers/footers via `apolloSectionHeader` /
`apolloSectionFooter`, linked from its parent with `SettingsLink` so the
Settings tab's page swipes work.

**A screen that pushes**: `.navigationDestination` plus
`.apolloTracksForwardNavigation($binding)` on the pushing screen, and
`.apolloForwardSwipe()` on a new stack's root. Read
`@Environment(\.dismiss)` in a small leaf view.

**A smoke check**: add a `@MainActor func check...() async throws` to the
matching `Checks/<Area>.swift` and call it from `main.swift`. Use
`check("human-readable name", condition)` once per fact, on values
returned by real code.

## Rules

- **Smoke tests call real code.** Assert on results of `PhoebusCore`
  functions; never read source files as text (fixtures in
  `Tests/Fixtures` and `SafariExtension/Tests` and shipped assets may be
  read). Never delete a failing assertion to make the suite pass;
  correct it with a one-line reason.
- **Build before you finish.** The app build must be clean and
  `scripts/smoke.sh` must pass.
- **Reuse proven patterns.** When a mechanism already works somewhere
  (for example `AncestorGestureHost` for full-surface gestures), copy it
  rather than inventing a parallel one.
- **No Apollo client ID.** Phoebus never uses Apollo's Reddit client ID or
  any private credential. API keys come from the user.
- **No copyrighted binaries.** Do not commit Apollo's app or its
  artwork. Interface glyphs are SF Symbols, open-source kit icons in
  `Resources/Glyphs` (licence in its `LICENSES.md`, credit in
  CREDITS.md) or drawn in code. `Resources/StockIcons` holds only
  Reborn's two hub images, to be replaced separately.
- **Credit Reborn without notifying anyone.** Phoebus is not affiliated
  with Apollo Reborn. In commits, PR descriptions and docs, name Reborn
  contributors without an @, write Reborn PRs and issues as plain text in
  backticks (`` `Apollo-Reborn#1305` ``), never link them, and don't add
  `Co-authored-by` trailers for Reborn authors. See CREDITS.md,
  "Attribution style".
- **Record deliberate differences** in
  [docs/intentional-differences.md](docs/intentional-differences.md).
- Keep version bumps (`Config/Phoebus/Info.plist`) in their own commit.
