# Builds and releases

How Phoebus is built in GitHub Actions, where the builds go, and how to
cut a release. Building on your own machine is in
[building-on-linux.md](building-on-linux.md).

## Overview

```
Release (.github/workflows/release.yml, by hand): semantic-release
  ─▶ tag v<version> and its GitHub release, with notes

push to main / tag v*
        │
        ▼
Build IPA (.github/workflows/build-ipa.yml)
  resolve-image ─▶ build ×3 (in parallel, in the phoebus-builder image)
                     device · simulator-x86_64 · simulator-arm64
                 ─▶ package ─▶ artifacts: Phoebus-<name>.ipa, Phoebus-<name>-simulator.ipa
                 ─▶ nightly (main): the rolling "nightly" pre-release
                 ─▶ release (tag): the tag's GitHub release
        │ on success
        ▼
Publish to AltStore sources (.github/workflows/publish-altstore.yml)
  adds the device IPA to pendo324/AltStoreRepo:
    main ─▶ nightly/source.json   ("Phoebus Nightly")
    tag  ─▶ source.json           ("pendo324", stable)
```

Build container image (`build-image.yml`) builds the image the builds run
in.

## The build image

`docker/build.Dockerfile` is Ubuntu 24.04 with:

- the swift.org Swift toolchain and Go (for the icon renderer), and the
  packages the build needs (`scripts/ci/setup-linux.sh`);
- the pinned xtool fork (`scripts/install-xtool.sh`), built against a
  libimobiledevice from `scripts/ci/build-libimobiledevice.sh`, since
  Ubuntu's is older than xtool needs.

`build-image.yml` pushes it to `ghcr.io/<owner>/phoebus-builder` as
`:latest` and `:<commit>` when the Dockerfile or a script it copies changes
on `main`, or when run by hand. Layers are cached in the Actions cache, and
the image is built without provenance attestations, so an unchanged image
keeps its digest. After a push that rewrites history, run it by hand: path
filters only see the files of the new tip commit.

The image can also be built locally and pushed by hand:

```bash
docker build -f docker/build.Dockerfile -t ghcr.io/<owner>/phoebus-builder:latest .
docker push ghcr.io/<owner>/phoebus-builder:latest
```

The Darwin SDK is not in the image: it comes from Xcode, which Apple does
not allow to be redistributed (see "Secrets" below).

## Build IPA

Runs on tags `v*`, by hand, and on pushes to `main` that change something
that ends up in the app or in how it is built: `Sources/`, `Config/`,
`Icons/`, the Safari extension's resources, the package manifest and
lockfile, `xtool.yml`, the build scripts and the workflow itself (the
`paths` list in `build-ipa.yml`). A push that changes only docs, tests or
other scripts builds nothing and adds no nightly; run the workflow by hand
if one is needed anyway. Keep the list in step when a new file starts to
affect the build.

1. **resolve-image** reads the digest `phoebus-builder:latest` points at,
   so every job uses the same image even if a new one is pushed mid-run.
2. **build** (three jobs, in parallel) each run `scripts/build-app.sh` for
   one variant: `device` (release), `simulator-x86_64` and `simulator-arm64`
   (debug, which compiles incrementally). Each job installs the SDK
   (`scripts/ci/install-sdk.sh`) and renders the icons
   (`scripts/generate-icons.sh`) first.
3. **package** numbers the builds with the workflow's run number
   (`scripts/stamp-version.py`, which also sets the version), merges the two simulator builds into
   one universal app (`scripts/merge-apps.py`), packs both IPAs
   (`scripts/package-ipa.sh`, which also runs `scripts/check-app.py`) and
   uploads them as the run's artifacts, each the file itself.
4. **nightly** (builds of `main`) runs `scripts/ci/publish-nightly.sh`: it
   moves the `nightly` tag to the built commit and adds the IPAs to the
   `nightly` pre-release, keeping the device IPAs of the last 20 builds
   and the newest simulator IPA, and lists them in the release notes.
5. **release** (tags) attaches both IPAs to the tag's release
   (`scripts/ci/publish-release.sh`). semantic-release has normally created
   the release with its notes by then; for a tag pushed by hand the script
   creates it, with GitHub's notes for the changes since the previous `v*`
   tag.

### Names and numbers

| | Device | Simulator |
|---|---|---|
| Tag `v1.2.0` | `Phoebus-v1.2.0.ipa` | `Phoebus-v1.2.0-simulator.ipa` |
| Other builds | `Phoebus-v<latest tag>-<short commit>.ipa` (`v0.0.0` before the first tag) | `…-simulator.ipa` |

The version comes from the release tags, not from the repository:
`scripts/version.sh` gives `1.2.0` at the tag `v1.2.0`, and for any other
commit the version of the latest release before it (`0.0.0` before the
first), so a nightly reports the release it builds on. The
`CFBundleShortVersionString` in `Config/Phoebus/Info.plist` is a placeholder
(`0.0.0`) for local builds, and no commit changes it for a release.
`scripts/ipa-name.sh` makes the IPAs' name from the same version.

The build number (`CFBundleVersion`) is the Build IPA run number. Both are
stamped into the app and its extensions when packaging
(`scripts/stamp-version.py`). It only goes up and is shared by nightly
and stable builds, so AltStore and SideStore see every new build as an
update. Local AltStore deploys number their builds from their own counter
instead, so nothing is committed for a build.

Both IPAs are unsigned and keep their symbols, which the crash reports the
app records need (stripping would save only about 5 MB of a 36 MB IPA).
The device IPA is a release build for arm64 iPhones and iPads; the
simulator IPA is a universal debug build that installs with
`xcrun simctl install <device> <file>`. Both carry the App Intents metadata
of the app and the widget, generated on Linux by
`scripts/appintents-metadata.py` (see
[building-on-linux.md](building-on-linux.md), "AppIntents metadata").

### Caching

A run after the first only compiles what changed:

- Each build job restores the newest `.build` and SwiftPM repository cache
  for the same variant, xtool commit, image definition and
  `Package.resolved`.
- SwiftBuild decides what to rebuild from file times, which a fresh
  checkout resets, so `scripts/ci/restore-mtimes.sh` first sets every
  tracked file's time to its last commit's. The workspace path is the same
  in every run, which the restored build also depends on.
- The rendered icons are cached on the icon sources and Apollo's IPA, so
  they are not rendered again (and don't change the resources) when
  nothing changed.
- The Darwin SDK and Apollo's IPA are cached by their hashes.

A change to a module still recompiles that whole module in the release
device build. Cold, the three builds take about 6, 8 and 11 minutes in
parallel.

## AltStore and SideStore sources

[pendo324/AltStoreRepo](https://github.com/pendo324/AltStoreRepo) is served
with GitHub Pages at https://pendo324.github.io/AltStoreRepo/ and holds two
sources:

| Source | URL | Contents |
|---|---|---|
| pendo324 | `https://pendo324.github.io/AltStoreRepo/source.json` | Stable releases of every app published there, Phoebus among them |
| Phoebus Nightly | `https://pendo324.github.io/AltStoreRepo/nightly/source.json` | The last 20 builds of Phoebus's `main` |

Both list Phoebus as `com.pendo324.Phoebus`, so to AltStore it is one app:
a device has either a stable or a nightly build installed.

`publish-altstore.yml` runs when Build IPA succeeds for a push to `main` or
a `v*` tag. It downloads the device IPA from that run, and
`scripts/ci/update-altstore-source.py` adds it as the newest version of the
app in the matching source: version, build number, date, download URL,
size, SHA-256, minimum iOS, the privacy usage descriptions from
`Info.plist` and the entitlements from the code signature. The app's
name, description and icon come from `scripts/ci/altstore-app.json` the
first time it is added. Nightly versions beyond 20 are dropped, matching
the IPAs the nightly release keeps; stable versions are all kept. The
change is pushed to AltStoreRepo by PhoebusBot. Runs are serialized, so
two builds never update a source at once.

The downloads point at this repository's releases (`nightly` or the tag),
so the sources only install builds while this repository is public.

## Cutting a release

Releases are cut by [semantic-release](https://semantic-release.gitbook.io/)
from the Conventional Commits on `main` (`.releaserc.json`):

1. Run the **Release** workflow (`.github/workflows/release.yml`) on `main`
   (Actions › Release › Run workflow, or `gh workflow run release.yml`).
2. semantic-release reads the commits since the last `v*` tag and picks the
   next version: `feat` raises the minor version, `fix` and `perf` the
   patch, and a breaking change (`feat!:` or a `BREAKING CHANGE:` footer)
   the major. With no such commits it releases nothing.
3. It pushes the tag `v<version>` and creates the GitHub release, with notes
   listing the features and fixes. The tag is pushed by PhoebusBot, since a
   tag pushed with the workflow's own token would not start other
   workflows.
4. Build IPA builds the tag, stamps the version and attaches both IPAs to
   the release; Publish to AltStore sources then adds it to the stable
   source.

Pushing a `v<version>` tag by hand also works; the release job then
creates the release itself (see Build IPA above). Tags other than `v*`,
such as `nightly`, are ignored by both.

## Secrets

| Secret | Used for |
|---|---|
| `DARWIN_SDK_URL` | The packed Darwin SDK in private storage. How it is made, and its pinned SHA-256, are in [building-on-linux.md](building-on-linux.md), "The Darwin SDK". |
| `XCODE_XIP_URL` | Optional: an Xcode `.xip` to install the SDK from instead (slower). |
| `PHOEBUSBOT_APP_CLIENT_ID`, `PHOEBUSBOT_APP_PRIVATE_KEY` | PhoebusBot, a GitHub App installed on the SDK's storage repository, on AltStoreRepo and on this repository, with Contents: read and write. The builds make a read-only token for the SDK download; the publishing workflow makes one that can write to AltStoreRepo; the Release workflow makes one that can push tags here. The workflows' own `GITHUB_TOKEN` cannot reach other repositories. |

`scripts/ci/install-sdk.sh` checks the SDK against the SHA-256 pinned in
it, and the SDK cache is keyed on that hash, so replacing the SDK means
updating the pin and `DARWIN_SDK_URL` together. Outside the workflows the
script takes the authorization header as `DOWNLOAD_AUTH_HEADER`.

Workflows for pull requests from forks get no secrets, which is why none of
these run for pull requests.

## Scripts

| Script | Role |
|---|---|
| `scripts/build-app.sh` | Builds one variant (`device`, `simulator-x86_64`, `simulator-arm64`). |
| `scripts/build-ipa.sh` | Everything Build IPA does, on your own machine: `scripts/build-ipa.sh --simulator dist`. |
| `scripts/version.sh`, `scripts/ipa-name.sh` | The app version from the release tags, and the IPAs' base name. |
| `scripts/stamp-version.py` | Sets the version and build number in a built app and its extensions. |
| `scripts/merge-apps.py` | Merges per-architecture builds into one universal app. |
| `scripts/package-ipa.sh` | Packs an app into an IPA and checks it. |
| `scripts/check-app.py` | Checks a built app or IPA for what can go wrong without failing the build. |
| `scripts/appintents-metadata.py`, `scripts/add-appintents-metadata.sh` | Write the app's and the widget's App Intents metadata after each build. |
| `scripts/ci/setup-linux.sh`, `scripts/ci/build-libimobiledevice.sh` | The image's packages and libimobiledevice. |
| `scripts/ci/install-sdk.sh` | Installs (or packs) the Darwin SDK. |
| `scripts/ci/restore-mtimes.sh` | Resets file times to their commits'. |
| `scripts/ci/publish-nightly.sh` | Updates the `nightly` pre-release. |
| `scripts/ci/publish-release.sh` | Attaches the IPAs to a tag's release, creating it if needed. |
| `.releaserc.json`, `.github/workflows/release.yml` | semantic-release's configuration and the workflow that runs it. |
| `scripts/ci/update-altstore-source.py`, `scripts/ci/altstore-app.json` | Add a build to an AltStore source. |
