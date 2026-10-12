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
# You supply the IPA: PHOEBUS_APOLLO_IPA is its path or a URL. A URL is
# downloaded once into the user cache, sending PHOEBUS_APOLLO_IPA_AUTH_HEADER
# with the request if it is set, and must match APOLLO_IPA_SHA256. Once the
# IPA is cached, PHOEBUS_APOLLO_IPA can be left unset.
#
# Usage: scripts/generate-icons.sh [--force]
#        scripts/generate-icons.sh --download-only   # only fetch the IPA
set -euo pipefail
cd "$(dirname "$0")/.."

APOLLO_IPA_SHA256="9526010ba4c52a5d1ad608f2c0262cefcb0d0740e8a960362642cbaec8b62f40"
cached="${XDG_CACHE_HOME:-$HOME/.cache}/phoebus/apollobase.ipa"
ipa="${PHOEBUS_APOLLO_IPA:-}"
if [[ $ipa == http://* || $ipa == https://* ]]; then
  if [ ! -f "$cached" ]; then
    mkdir -p "$(dirname "$cached")"
    echo "==> Downloading the Apollo IPA from PHOEBUS_APOLLO_IPA"
    # Asks for the raw bytes: some storage APIs answer with metadata otherwise.
    curl -fsSL --retry 3 -H "Accept: application/octet-stream" \
      ${PHOEBUS_APOLLO_IPA_AUTH_HEADER:+-H "$PHOEBUS_APOLLO_IPA_AUTH_HEADER"} \
      -o "$cached.part" "$ipa"
    if [ "$(sha256sum "$cached.part" | cut -d' ' -f1)" != "$APOLLO_IPA_SHA256" ]; then
      rm -f "$cached.part"
      echo "scripts/generate-icons.sh: the download does not match the pinned SHA-256 $APOLLO_IPA_SHA256" >&2
      exit 1
    fi
    mv "$cached.part" "$cached"
  fi
  ipa="$cached"
elif [ -z "$ipa" ]; then
  if [ ! -f "$cached" ]; then
    echo "scripts/generate-icons.sh: no Apollo IPA. Apollo's standard icons are extracted from an Apollo IPA you supply: set PHOEBUS_APOLLO_IPA to its path or URL (see docs/building-on-linux.md)." >&2
    exit 1
  fi
  ipa="$cached"
fi
if [ "$ipa" = "$cached" ] && [ "$(sha256sum "$cached" | cut -d' ' -f1)" != "$APOLLO_IPA_SHA256" ]; then
  echo "scripts/generate-icons.sh: $cached is not the expected Apollo IPA (sha256 mismatch); delete it to download again" >&2
  exit 1
fi
if [ "${1:-}" = "--download-only" ]; then
  exit 0
fi

for tool in go rsvg-convert; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "scripts/generate-icons.sh: $tool is required to render the icons" >&2
    exit 1
  fi
done

bin=.build/lgrender
(cd scripts/lgrender && go build -o "../../$bin" .)
"$bin" -root . -apollo-ipa "$ipa" "$@"
