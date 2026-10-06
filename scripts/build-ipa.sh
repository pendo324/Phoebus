#!/bin/bash
# Builds unsigned IPAs into an output directory (default: xtool):
#   <name>.ipa            for devices (arm64, release). Its symbols are kept:
#                         stripping saves only about 5 MB of the compressed
#                         IPA, and the crash reports the app records need them.
#   <name>-simulator.ipa  with --simulator: one universal debug build for
#                         x86_64 and arm64 simulators
#                         (`xcrun simctl install <device> <file>`)
# <name> comes from scripts/ipa-name.sh. With PHOEBUS_BUILD_NUMBER set, the
# apps get that CFBundleVersion (scripts/stamp-build-number.py).
#
# Usage: scripts/build-ipa.sh [--simulator] [output directory]
#
# The paths are printed last, and written as `ipa=` and `simulator=` to
# $GITHUB_OUTPUT when that is set. xtool/Phoebus.app is left as the device
# build. CI builds the variants in parallel with scripts/build-app.sh
# instead, then packages them the same way.
set -euo pipefail
cd "$(dirname "$0")/.."

simulator=0
if [ "${1:-}" = --simulator ]; then simulator=1; shift; fi
out=$(realpath -m "${1:-xtool}")
name=$(scripts/ipa-name.sh)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
outputs=()

stamp() { [ -z "${PHOEBUS_BUILD_NUMBER:-}" ] || scripts/stamp-build-number.py "$1" "$PHOEBUS_BUILD_NUMBER"; }

scripts/generate-icons.sh

if [ "$simulator" = 1 ]; then
  scripts/build-app.sh simulator-x86_64 "$work/x86_64.app"
  scripts/build-app.sh simulator-arm64 "$work/arm64.app"
  scripts/merge-apps.py "$work/Phoebus.app" "$work/x86_64.app" "$work/arm64.app"
  stamp "$work/Phoebus.app"
  scripts/package-ipa.sh "$work/Phoebus.app" "$out/$name-simulator.ipa"
  outputs+=("simulator=$out/$name-simulator.ipa")
fi

scripts/build-app.sh device "$work/device.app"
stamp "$work/device.app"
scripts/package-ipa.sh "$work/device.app" "$out/$name.ipa"
outputs+=("ipa=$out/$name.ipa")

for output in "${outputs[@]}"; do
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "$output" >> "$GITHUB_OUTPUT"
  echo "${output#*=}"
done
