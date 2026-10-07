#!/bin/bash
# Attaches files to the GitHub release of a tag. semantic-release normally
# creates that release, with its notes, before the build finishes; for a tag
# pushed by hand this creates it, with GitHub's notes for the changes since
# the previous v* tag (not since the nightly tag, which GitHub would
# otherwise compare against). Runs in the workflow with GH_TOKEN
# (contents: write).
#
# Usage: scripts/ci/publish-release.sh <tag> <file>...
set -euo pipefail
cd "$(dirname "$0")/../.."

tag=$1; shift
repo="${GITHUB_REPOSITORY:?}"

if ! gh release view "$tag" >/dev/null 2>&1; then
  args=(-f tag_name="$tag")
  if previous=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$tag^" 2>/dev/null); then
    args+=(-f previous_tag_name="$previous")
  fi
  gh api "repos/$repo/releases/generate-notes" "${args[@]}" --jq .body > notes.md
  gh release create "$tag" --verify-tag --title "$tag" --notes-file notes.md
  rm -f notes.md
fi
gh release upload "$tag" "$@" --clobber
