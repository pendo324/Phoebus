#!/bin/bash
# Prints the base name for this commit's IPAs:
#   Phoebus-v<version>                 at a tag v<version>
#   Phoebus-v<latest tag>-<short sha>  anywhere else (v0.0.0 before the
#                                      first tag)
# The version is scripts/version.sh's.
set -euo pipefail
cd "$(dirname "$0")/.."

name="Phoebus-v$(scripts/version.sh)"
if git describe --tags --exact-match --match 'v[0-9]*.[0-9]*.[0-9]*' >/dev/null 2>&1; then
  echo "$name"
else
  echo "$name-$(git rev-parse --short HEAD)"
fi
