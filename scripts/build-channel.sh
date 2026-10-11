#!/bin/bash
# Prints the release channel of this commit's build:
#   stable   at a tag v<version>
#   nightly  anywhere else
# CI stamps it into the app (PhoebusBuildChannel, scripts/stamp-version.py)
# so the app knows which AltStore source to check for updates.
set -euo pipefail
cd "$(dirname "$0")/.."

if git describe --tags --exact-match --match 'v[0-9]*.[0-9]*.[0-9]*' >/dev/null 2>&1; then
  echo stable
else
  echo nightly
fi
