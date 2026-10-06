#!/bin/bash
# Prints the base name for this commit's IPAs:
#   Phoebus-v<version>                 at a tag v<version>, which must match
#                                      the app's CFBundleShortVersionString
#   Phoebus-v<latest tag>-<short sha>  anywhere else (v0.0.0 before the
#                                      first tag)
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(python3 -c "import plistlib; print(plistlib.load(open('Config/Phoebus/Info.plist', 'rb'))['CFBundleShortVersionString'])")
if tag=$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null); then
  if [ "$tag" != "v$version" ]; then
    echo "scripts/ipa-name.sh: tag $tag does not match the app version $version (Config/Phoebus/Info.plist)" >&2
    exit 1
  fi
  echo "Phoebus-$tag"
else
  latest=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)
  echo "Phoebus-$latest-$(git rev-parse --short HEAD)"
fi
