#!/bin/bash
# Renders the app's alternate icons:
#  - the Liquid Glass icons from their Icon Composer sources
#    (Icons/LiquidGlass/<group>/<id>/<id>.icon), beside each source, and the
#    App Icon picker's previews in Sources/PhoebusUI/Resources/LiquidGlassIcons;
#  - the standard icons (Icons/Standard/<id>/), extracted from Apollo's own
#    IPA, which is not part of this repository.
# Icons whose source is unchanged are skipped. Needs Go and rsvg-convert
# (librsvg).
#
# The IPA comes from PHOEBUS_APOLLO_IPA (a path or URL), else it is
# downloaded once from Apollo Reborn's mirror into the user cache.
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

DEFAULT_IPA_URL="https://downloads.apolloreborn.app/apollobase.ipa"
DEFAULT_IPA_SHA256="9526010ba4c52a5d1ad608f2c0262cefcb0d0740e8a960362642cbaec8b62f40"
ipa="${PHOEBUS_APOLLO_IPA:-$DEFAULT_IPA_URL}"
if [[ $ipa == http://* || $ipa == https://* ]]; then
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/phoebus"
  file="$cache/$(basename "$ipa")"
  if [ ! -f "$file" ]; then
    mkdir -p "$cache"
    echo "==> Downloading $ipa"
    curl -fsSL --retry 3 -o "$file.part" "$ipa"
    mv "$file.part" "$file"
  fi
  if [ "$ipa" = "$DEFAULT_IPA_URL" ] && [ "$(sha256sum "$file" | cut -d' ' -f1)" != "$DEFAULT_IPA_SHA256" ]; then
    echo "scripts/generate-icons.sh: $file is not the expected Apollo IPA (sha256 mismatch); delete it to download again" >&2
    exit 1
  fi
  ipa="$file"
fi

bin=.build/lgrender
(cd scripts/lgrender && go build -o "../../$bin" .)
"$bin" -root . -apollo-ipa "$ipa" "$@"
