#!/bin/bash
# Shared build environment, sourced by build-for-simulator.sh and smoke.sh.
#
# Sets, for the caller:
#   XTOOL       the xtool binary to run (default: the one installed by
#               scripts/install-xtool.sh, else xtool from PATH)
#   SANDBOX     a command prefix array run in front of xtool (default: empty)
#   SWIFT_BUILD the complete `swift build` command as an array
#               (default: swift build). Callers append their own arguments:
#                 "${SWIFT_BUILD[@]}" --product PhoebusCoreSmokeTest
#   SHIM_DIR    a temporary directory the caller should delete on exit, if
#               set (default: empty)
#
# Machine-specific overrides belong in scripts/local.sh, which is sourced
# when present and is gitignored. It may reassign any of the variables
# above. See docs/building-on-linux.md for what it is for.

# The xtool Phoebus is built with: a fork carrying fixes that are not in an
# xtool release yet (see docs/building-on-linux.md). scripts/install-xtool.sh
# builds this commit into XTOOL_DIR, under PHOEBUS_TOOLS (the CI image sets
# it to /opt/phoebus).
XTOOL_REPO="${XTOOL_REPO:-https://github.com/pendo324/xtool}"
XTOOL_BRANCH=xcode-27-fixes
XTOOL_COMMIT=386787a9e47cd714d9f40e2c38ac6ef29db155fc
XTOOL_DIR="${PHOEBUS_TOOLS:-$HOME/.local/lib/phoebus}/xtool-$XTOOL_COMMIT"

if [ -z "${XTOOL:-}" ]; then
  if [ -x "$XTOOL_DIR/xtool" ]; then XTOOL="$XTOOL_DIR/xtool"; else XTOOL=xtool; fi
fi
SANDBOX=()
SWIFT_BUILD=(swift build)
SHIM_DIR=""

# A full iOS build opens more files at once than the usual soft limit of
# 1024 allows ("Too many open files").
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

LOCAL_SH="$(dirname "${BASH_SOURCE[0]}")/local.sh"
# shellcheck source=/dev/null
if [ -f "$LOCAL_SH" ]; then source "$LOCAL_SH"; fi
