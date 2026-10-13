#!/bin/bash
# Renders the app icons from their Icon Composer sources
# (Icons/LiquidGlass/<pack>/<id>/<id>.icon, listed in
# Icons/LiquidGlass/icons.json), beside each source, and the App Icon
# picker's previews in Sources/PhoebusUI/Resources/LiquidGlassIcons. Icons
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
