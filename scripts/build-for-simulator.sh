#!/bin/bash
# Builds Phoebus as an iOS Simulator .app entirely on Linux, using the
# Darwin cross-compilation SDK installed by `xtool sdk install`.
#
# Usage: scripts/build-for-simulator.sh [triple]
#   triple defaults to x86_64-apple-ios-simulator; pass
#   arm64-apple-ios-simulator for an Apple Silicon Mac's simulator.
set -euo pipefail

TRIPLE="${1:-x86_64-apple-ios-simulator}"

cd "$(dirname "$0")/.."

# shellcheck source=scripts/xtool-env.sh
source scripts/xtool-env.sh
[ -n "${SHIM_DIR:-}" ] && trap 'rm -rf "$SHIM_DIR"' EXIT

scripts/generate-icons.sh
# Links with the simulator's platform name (see Package.swift).
export PHOEBUS_LINK_PLATFORM=ios-simulator
"${SANDBOX[@]}" "$XTOOL" dev build --triple "$TRIPLE"
scripts/add-appintents-metadata.sh "$TRIPLE" debug
scripts/check-app.py xtool/Phoebus.app

echo "Built xtool/Phoebus.app for $TRIPLE"
