#!/bin/bash
# Builds one variant of the app and copies it to <out.app>:
#   device             arm64 iOS, release
#   simulator-x86_64   x86_64 simulator, debug (compiles incrementally)
#   simulator-arm64    arm64 simulator, debug
# Run scripts/generate-icons.sh first.
#
# Usage: scripts/build-app.sh <variant> <out.app>
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  device)           triple=arm64-apple-ios;            config=release; platform=ios;;
  simulator-x86_64) triple=x86_64-apple-ios-simulator; config=debug;   platform=ios-simulator;;
  simulator-arm64)  triple=arm64-apple-ios-simulator;  config=debug;   platform=ios-simulator;;
  *) echo "usage: scripts/build-app.sh <device|simulator-x86_64|simulator-arm64> <out.app>" >&2; exit 1;;
esac
out=$(realpath -m "$2")

# shellcheck source=scripts/xtool-env.sh
source scripts/xtool-env.sh
[ -n "${SHIM_DIR:-}" ] && trap 'rm -rf "$SHIM_DIR"' EXIT

PHOEBUS_LINK_PLATFORM=$platform "${SANDBOX[@]}" "$XTOOL" dev build --triple "$triple" --configuration "$config"
scripts/add-appintents-metadata.sh "$triple" "$config"
rm -rf "$out"
mkdir -p "$(dirname "$out")"
cp -a xtool/Phoebus.app "$out"
