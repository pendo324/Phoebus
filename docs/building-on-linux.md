# Building on Linux

Phoebus is built without a Mac: SwiftPM compiles it for iOS with a
Darwin cross-compilation SDK, and [xtool](https://github.com/xtool-org/xtool)
packages the result into an `.app` (and optionally an `.ipa`). This page
lists what you need, what each script does, the workarounds the scripts
apply and why, and how a CI job on GitHub-hosted runners could look.

## Requirements

| Piece | Notes |
|---|---|
| Swift 6.4 | Use the official toolchain from swift.org, which has the layout `usr/bin`, `usr/lib/swift`. Distro packages that put the tools somewhere else need the workaround under "swift-autolink-extract" below. |
| xtool | A fork with fixes that are not in a release yet, built by `scripts/install-xtool.sh`. See "The xtool fork" below. |
| Darwin SDK | Built from **Xcode 27** (the SDK's Swift must match the toolchain: Xcode 27 for Swift 6.4) and installed with the forked xtool: `scripts/install-xtool.sh <Xcode.xip>`. Apple does not allow Xcode to be redistributed, so you supply the `.xip` yourself (an Apple ID is needed to download it). |
| Go and rsvg-convert | Render the Liquid Glass icons from their vector sources during the iOS build (`scripts/generate-icons.sh`). rsvg-convert is librsvg's command-line tool (`librsvg2-bin` on Debian and Ubuntu). |
| Apollo's IPA | The standard icons are Apollo's artwork and are not in the repository; the iOS build extracts them from Apollo's IPA. By default it is downloaded once (about 100 MB) from Apollo Reborn's mirror into `~/.cache/phoebus/`; set `PHOEBUS_APOLLO_IPA` to a path or URL to supply your own. |
| Python 3 | Only for the generators in `scripts/generate/` and `scripts/code-unchanged.py`. |
| Network | The first resolve fetches KSCrash from GitHub; the first iOS build downloads Apollo's IPA unless `PHOEBUS_APOLLO_IPA` points at a local copy. |

Dependencies:

- **KSCrash** (the `Recording` product) comes from upstream through SwiftPM,
  pinned by revision in `Package.swift` and recorded in `Package.resolved`.
  Upstream's manifest uses `unsafeFlags`, which SwiftPM only accepts for
  revision or branch pins, not version ranges.
- **AnimatedImage** comes from upstream through SwiftPM. Its `@Entry`,
  like SwiftUI's `@State` in the Xcode 27 SDK, is a macro whose Apple
  implementation only runs on macOS; on Linux xtool's SDK expands them
  with [OpenAppleMacros](https://github.com/xtool-org/OpenAppleMacros).

## Scripts

All scripts can be run from any directory; they `cd` to the repository
root. Run them as `scripts/<name>`.

| Script | What it does |
|---|---|
| `install-xtool.sh [Xcode.xip]` | Builds the pinned xtool fork into `~/.local/lib/phoebus/` (once per commit, a few minutes), and with a `.xip` installs the Darwin SDK with it. |
| `build-for-simulator.sh [triple]` | Renders the icons (`generate-icons.sh`), then runs `xtool dev build` for an iOS Simulator triple (`x86_64-apple-ios-simulator` by default, `arm64-apple-ios-simulator` for Apple Silicon) and produces `xtool/Phoebus.app` with the three app extensions, then checks it with `check-app.py`. This is also the only compile check for `PhoebusUI` and the app target. |
| `check-app.py <app or ipa>` | Checks a built app for what can go wrong without failing the build: extensions linked as stubs, executables that disagree on platform or minimum OS, extensions with their own `Frameworks/`, declared icons missing from the bundle, malformed version strings. Warns when the widget has no `Metadata.appintents`. |
| `smoke.sh` | Builds and runs `PhoebusCoreSmokeTest` on the host and checks the exit status and the `ALL CHECKS PASSED` line (a crash must not look like a pass). Then runs `build-for-simulator.sh`, unless `SMOKE_SKIP_IOS=1`. Exit codes: 1 failed assertions, 2 build failed, 3 crashed mid-run, 4 no terminator line, 5 iOS build failed. |
| `code-unchanged.py [rev] [paths]` | Compares Swift files with all comments stripped between a git revision and the working tree; proves that an edit changed only comments. |
| `generate-icons.sh [--force]` | Renders the Liquid Glass alternate icons and the App Icon picker's previews from the Icon Composer sources in `Icons/LiquidGlass`, and extracts the standard icons from Apollo's IPA into `Icons/Standard`, with `scripts/lgrender`. Unchanged icons are skipped. Run it before any `xtool dev build` you invoke yourself. |
| `xtool-env.sh` | Sourced by the build scripts. Sets `XTOOL`, `SANDBOX` and `SWIFT_BUILD` (see "Local overrides"). |
| `generate/gen-settings-search-index.py <Screens dir> <out.swift>` | Regenerates `SettingsSearchIndexData.swift` from the settings screens. |
| `generate/gen-theme-gallery.py <themes dir> <out.swift>` | Regenerates `ThemeGalleryData.swift` from the theme JSON files. |
| `generate/check-segmented-controls.py` | Audit: every segmented picker has a matching case count. |

Typical loop:

```bash
scripts/build-for-simulator.sh 2>&1 | grep -E " error:|Build complete"
SMOKE_SKIP_IOS=1 scripts/smoke.sh      # prints "SMOKE: ok (N passed)"
```

For the host-only core library, `swift build --product PhoebusCoreSmokeTest`
is enough.

## Workarounds and why

### swift-autolink-extract

SwiftPM and the Swift driver look for `swift-autolink-extract` next to the
`swift` binary they were started as. With the official toolchain layout
(`<root>/usr/bin/swift`) it is found. Some distro packages put the
toolchain elsewhere and only link a few tools into `/usr/bin`; every
package that has a dependency then fails at link time with `unable to
spawn process '/usr/sbin/swift-autolink-extract'`. Either link the tool
(`sudo ln -s <toolchain>/bin/swift-autolink-extract /usr/bin/`) or run
the build inside a mount namespace that overlays the missing entry onto
`/usr/bin` (see "Local overrides"). PATH shims do not help, because the
driver spawns it by absolute path.

### The xtool fork

The build needs xtool 1.21 (it drives Swift 6.4's SwiftBuild engine, and
its SDK carries OpenAppleMacros) plus fixes that are open upstream. They
live on the `xcode-27-fixes` branch of
[pendo324/xtool](https://github.com/pendo324/xtool), and
`scripts/xtool-env.sh` pins the commit:

| Fix | Upstream |
|---|---|
| Copy the root `Package.resolved` into xtool's builder package, so it resolves the same versions | xtool-org/xtool#290 |
| Embed each dynamic library once | xtool-org/xtool#291 |
| Link dynamic library products into the app | xtool-org/xtool#292 |
| Give dynamic library links the Swift runtime | xtool-org/xtool#293 |
| Keep extensions' libraries in the host app; Xcode's extension runpaths. Without it and #292, the extensions come out as stub binaries and signing fails. | xtool-org/xtool#295 |
| Enable cross-import overlays in the SwiftBuild toolset, so `PhotosPicker` (`_PhotosUI_SwiftUI`) resolves | none yet |

Three of them (#293 and the last two) change the SDK, so the SDK has to be
installed by the forked xtool. When they are all in an xtool release, the
fork can go and `install-xtool.sh` can build the release instead.

SwiftPM's SwiftBuild integration records two build-machine paths as
runpaths in every executable: `<repo>/.build/out/Products/<config>/PackageFrameworks`
and the toolchain's `lib/swift-6.2/<platform>`. Neither exists on a device,
so they are inert.

## Local overrides: `scripts/local.sh`

`scripts/xtool-env.sh` holds only generic logic:

| Variable | Default | Meaning |
|---|---|---|
| `XTOOL` | the one `install-xtool.sh` installed, else `xtool` | The xtool binary to run. |
| `SANDBOX` | empty array | A command prefix run in front of xtool. |
| `SWIFT_BUILD` | `swift build` | The complete command used to build with SwiftPM; scripts append their own arguments. |
| `SHIM_DIR` | empty | A temporary directory the calling script deletes on exit. |

If `scripts/local.sh` exists, `xtool-env.sh` sources it afterwards, so it
can override any of them. The file is gitignored, so each machine can keep
its own workarounds. An example for a machine whose toolchain lacks
`swift-autolink-extract` in `/usr/bin`:

```bash
#!/bin/bash
# scripts/local.sh
TOOLS=/opt/swift/usr/bin
SHIM_DIR="$(mktemp -d)"
ln -s "$TOOLS/swift-autolink-extract" "$SHIM_DIR/swift-autolink-extract"
SANDBOX=(bwrap --dev-bind / / --overlay-src /usr/bin --overlay-src "$SHIM_DIR" --tmp-overlay /usr/bin)
SWIFT_BUILD=("${SANDBOX[@]}" swift build)
```

## AppIntents metadata needs macOS

The configurable widgets are App Intents widgets. At runtime the system
needs `Metadata.appintents` inside the widget extension to construct their
default configuration; without it each configurable widget fails with
`CHSErrorDomain` 1103 ("Intent configuration is required but was not
provided"). Xcode produces that file with Apple's
`appintentsmetadataprocessor`, which only exists on macOS, and xtool has no
equivalent step. On Linux the build only prepares the input: the widget
target is compiled with `-emit-const-values` and the protocol list in
`Config/PhoebusWidget/AppIntentsProtocols.json`, which writes
`*.swiftconstvalues` under `.build/`. Running the processor on a Mac over
those files and the widget sources, then copying `Metadata.appintents`
into `PhoebusWidget.appex`, is a separate step that this repository does
not automate. Everything except the configurable widgets works without it.

## Liquid Glass icons

The Liquid Glass icons are kept as their Icon Composer sources: a folder
of SVG (and a few bitmap) layers plus an `icon.json` describing the fill,
layer placement, opacity, blend modes, shadows and glass. Apple's renderer
for that format only runs on a Mac with a GPU, so `scripts/lgrender`
composites them on Linux: it rasterizes each layer with rsvg-convert and
draws the fill, placement, opacity, blend modes and shadows as described.
Glass, translucency and specular highlights are approximated, so the
results are close to Apple's rendering rather than identical. Every icon
is rendered in its Default, Dark, Clear Light and Clear Dark looks where it
has them.

The standard icons are Apollo's own PNGs. Apollo's bundle ships them as
loose `app-icon-<device>-<name>.png` files in Apple's CgBI PNG variant
(raw deflate, BGRA, premultiplied alpha), which `lgrender` converts back to
standard PNGs. The names don't always match the sizes, so each icon is
taken by measured size (120 and 180 px), reducing a larger file where
there is no exact one. Reborn's additions that Apollo never shipped are
rendered from their Liquid Glass sources in `Icons/LiquidGlass/ultra`.

## CI on GitHub runners (planned, not set up)

There is no CI workflow yet. An outline of what it would need:

1. An `ubuntu-latest` runner (x86_64).
2. Install the official Swift 6.4 tarball for Ubuntu from swift.org and
   put its `usr/bin` on `PATH`.
3. Build xtool with `scripts/install-xtool.sh` and cache
   `~/.local/lib/phoebus` keyed on the pinned commit. Install Go
   (`actions/setup-go`) and `librsvg2-bin` for the icon renderer.
4. Provide the Darwin SDK. The Xcode `.xip` cannot be redistributed, so
   the project owner has to supply it: install the SDK once with
   `scripts/install-xtool.sh <Xcode.xip>` and cache the resulting
   `~/.swiftpm/swift-sdks/darwin.artifactbundle` with `actions/cache`
   (or restore it from private storage). Pull requests from forks have no
   access to secrets or private caches, so jobs that need the SDK should
   only run for trusted branches.
5. Cache `.build` and SwiftPM's package cache keyed on `Package.resolved`.
   The rendered icons can be cached too, keyed on `Icons/LiquidGlass` and
   `scripts/lgrender`. Cache `~/.cache/phoebus` as well, so Apollo's IPA is
   downloaded once.
6. Run `SMOKE_SKIP_IOS=1 scripts/smoke.sh`, which needs only the
   toolchain, then `scripts/build-for-simulator.sh` once the SDK is
   available.

With the official toolchain the runner needs no `scripts/local.sh`.
