#!/bin/bash
# Adds a build of main to the rolling "nightly" pre-release: moves the
# nightly tag to the built commit, uploads the IPAs, keeps the device IPAs
# of the last 20 builds and only the newest simulator IPA, and rewrites the
# release notes. Runs in the workflow with GH_TOKEN (contents: write).
#
# Usage: scripts/ci/publish-nightly.sh <device.ipa> <simulator.ipa>
set -euo pipefail
cd "$(dirname "$0")/../.."

KEEP=20
TAG=nightly
device=$1 simulator=$2
sha=$(git rev-parse HEAD)
repo="${GITHUB_REPOSITORY:?}"

if gh api "repos/$repo/git/refs/tags/$TAG" >/dev/null 2>&1; then
  gh api -X PATCH "repos/$repo/git/refs/tags/$TAG" -f sha="$sha" -F force=true >/dev/null
else
  gh api -X POST "repos/$repo/git/refs" -f ref="refs/tags/$TAG" -f sha="$sha" >/dev/null
fi
if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" --prerelease --title "Nightly" --notes "Builds of main." --verify-tag
fi
gh release upload "$TAG" "$device" "$simulator" --clobber

# Newest first; the device IPAs are Phoebus-*.ipa without -simulator.
assets=$(gh release view "$TAG" --json assets --jq '.assets | sort_by(.createdAt) | reverse | .[] | .name')
keep_device=$(grep -v -- '-simulator\.ipa$' <<< "$assets" | head -n "$KEEP")
keep_simulator=$(basename "$simulator")
while read -r asset; do
  [ -n "$asset" ] || continue
  if ! grep -qxF "$asset" <<< "$keep_device"$'\n'"$keep_simulator"; then
    gh release delete-asset "$TAG" "$asset" --yes
  fi
done <<< "$assets"

{
  echo "Unsigned builds of \`main\`, newest first. Install with AltStore or SideStore,"
  echo "which sign the app on the device. The simulator IPA is a universal build"
  echo "for x86_64 and arm64 simulators: \`xcrun simctl install <device> <file>\`."
  echo
  while read -r asset; do
    short=${asset%.ipa}; short=${short##*-}
    subject=$(git log -1 --format=%s "$short" 2>/dev/null || echo "(commit no longer in the history)")
    echo "- \`$asset\`: $subject"
  done <<< "$keep_device"
} > notes.md
gh release edit "$TAG" --prerelease --target "$sha" --notes-file notes.md
rm -f notes.md
