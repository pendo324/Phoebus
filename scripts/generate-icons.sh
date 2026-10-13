#!/bin/bash
# Renders the App Icon picker's previews of the app icons
# (Icons/LiquidGlass/<pack>/<id>/<id>.icon, listed in
# Icons/LiquidGlass/icons.json) into Sources/PhoebusUI/Resources/LiquidGlassIcons
# with scripts/lgrender, then compiles the icons themselves into an asset
# catalog (scripts/compile-app-icons.sh, which needs PHOEBUS_ACTOOL). Icons
# whose source is unchanged are skipped. Needs Go and rsvg-convert (librsvg).
#
# The sources themselves are generated from Icons/source by
# scripts/generate/gen-phoebus-icons.py.
#
# Usage: scripts/generate-icons.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in go rsvg-convert; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "scripts/generate-icons.sh: $tool is required to render the icons" >&2
    exit 1
  fi
done

bin=.build/lgrender
(cd scripts/lgrender && go build -o "../../$bin" .)
"$bin" -root . "$@"
scripts/compile-app-icons.sh "$@"
