#!/bin/bash
# Prints the app version for this commit, from the release tags:
#   at a tag v<version>  <version>
#   anywhere else        the latest v<version> tag before it (a nightly
#                        reports the release it builds on), 0.0.0 before
#                        the first one
# Releases are tagged by semantic-release (docs/releases.md); the version in
# Config/Phoebus/Info.plist is only a placeholder for unstamped local builds.
set -euo pipefail
cd "$(dirname "$0")/.."

tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || echo v0.0.0)
echo "${tag#v}"
