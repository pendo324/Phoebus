#!/bin/bash
# Builds the pinned xtool (XTOOL_REPO at XTOOL_COMMIT, from
# scripts/xtool-env.sh) and installs it into XTOOL_DIR, where the build
# scripts pick it up. With an Xcode .xip, also installs the Darwin SDK with
# that xtool, replacing any SDK already installed.
#
# Usage: scripts/install-xtool.sh [--slim] [path/to/Xcode.xip]
#   --slim installs only the parts of Xcode xtool uses (about 3 GB instead of
#   7); such an SDK cannot be updated in place. CI uses a slim SDK.
#   XTOOL_REPO=<url or local clone> overrides where the commit is fetched from.
#   XTOOL_BUNDLE_LIBS_FROM=<dir>[:<dir>...] also copies the libraries xtool
#   loads from these directories next to it (for a libimobiledevice built
#   from source, as scripts/ci/build-libimobiledevice.sh does).
#
# xtool is linked without the toolchain's library path, and the Swift
# runtime libraries it needs are copied next to it, so a later update of
# the system Swift cannot break it. The installed `xtool` is a wrapper that
# clears LD_LIBRARY_PATH, which would otherwise take precedence over the
# copied libraries, and gives xtool a pipe for stdin when it has none: with
# stdin on /dev/null (CI, containers), xtool crashes registering it with
# epoll ("epoll_ctl ... Operation not permitted").
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=scripts/xtool-env.sh
source scripts/xtool-env.sh
[ -n "${SHIM_DIR:-}" ] && trap 'rm -rf "$SHIM_DIR"' EXIT

src="$HOME/.cache/phoebus/xtool-src"
if [ ! -x "$XTOOL_DIR/xtool" ]; then
  [ -d "$src/.git" ] || git init -q "$src"
  # Only the pinned commit; local clones may not serve a bare commit, so
  # fall back to the branch.
  git -C "$src" fetch -q --depth 1 "$XTOOL_REPO" "$XTOOL_COMMIT" 2>/dev/null \
    || git -C "$src" fetch -q "$XTOOL_REPO" "$XTOOL_BRANCH"
  git -C "$src" checkout -q --detach "$XTOOL_COMMIT"
  echo "==> Building xtool ${XTOOL_COMMIT:0:12} (a few minutes)"
  (cd "$src" && env -u LD_LIBRARY_PATH swift build -c release --product xtool \
    -Xswiftc -no-toolchain-stdlib-rpath)
  bin=$(cd "$src" && swift build -c release --show-bin-path)
  runtime="$(dirname "$(dirname "$(readlink -f "$(command -v swift)")")")/lib/swift/linux"
  rm -rf "$XTOOL_DIR.tmp"
  mkdir -p "$XTOOL_DIR.tmp/lib"
  install -m755 "$bin/xtool" "$XTOOL_DIR.tmp/lib/"
  install -m644 "$bin"/*.so "$XTOOL_DIR.tmp/lib/"
  extra="${XTOOL_BUNDLE_LIBS_FROM:-}"
  LD_LIBRARY_PATH="$runtime:$bin${extra:+:$extra}" ldd "$bin/xtool" \
    | awk -v dirs="$runtime:$extra" '
        BEGIN { n = split(dirs, d, ":") }
        { for (i = 1; i <= n; i++) if (d[i] != "" && index($3, d[i] "/") == 1) { print $3; break } }' \
    | xargs -r install -m644 -t "$XTOOL_DIR.tmp/lib"
  printf '%s\n' '#!/bin/sh' \
    'bin="$(dirname "$(readlink -f "$0")")/lib/xtool"' \
    'if [ -t 0 ] || [ -p /dev/stdin ]; then exec env -u LD_LIBRARY_PATH "$bin" "$@"; fi' \
    'true | env -u LD_LIBRARY_PATH "$bin" "$@"' \
    > "$XTOOL_DIR.tmp/xtool"
  chmod +x "$XTOOL_DIR.tmp/xtool"
  rm -rf "$XTOOL_DIR"
  mv "$XTOOL_DIR.tmp" "$XTOOL_DIR"
fi
"$XTOOL_DIR/xtool" --version
echo "Installed $XTOOL_DIR/xtool"

slim=()
if [ "${1:-}" = --slim ]; then slim=(--slim); shift; fi
if [ -n "${1:-}" ]; then
  "${SANDBOX[@]}" "$XTOOL_DIR/xtool" sdk install "${slim[@]}" "$1"
fi
