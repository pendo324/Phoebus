#!/bin/bash
# Installs the Darwin SDK for CI. Apple does not allow Xcode to be
# redistributed, so it comes from private storage, as one of:
#   DARWIN_SDK_URL  a slim SDK packed with --pack below (about 450 MB)
#   XCODE_XIP_URL   the Xcode .xip, installed with scripts/install-xtool.sh
#                   (about 2 GB to download, plus the time to extract it)
# Either download must match its pinned SHA-256 below; how the pinned files
# were made is in docs/building-on-linux.md ("The Darwin SDK").
# DOWNLOAD_AUTH_HEADER, when set, is sent with the download (for example
# "Authorization: Bearer <token>").
#
# Usage: scripts/ci/install-sdk.sh
#        scripts/ci/install-sdk.sh --pack <out.tar.zst>   pack the installed SDK
set -euo pipefail
cd "$(dirname "$0")/../.."

# Xcode 27.0 (27A266a) installed with --slim by the xtool commit in
# scripts/xtool-env.sh, then packed with --pack.
DARWIN_SDK_SHA256=88f9f6c481c00dd41b9125fdd7e3a9b040c523fb339b0097077ab6d51e51b01b
# Xcode_27.xip, Xcode 27.0 (27A266a).
XCODE_XIP_SHA256=6a270c53a5a0c5e0ac78125342d44c3cfff2716ec390373cd5e30834d80a67c3

# Where SwiftPM and xtool look: XDG_CONFIG_HOME when it is set (the CI job
# sets it, since in a container job HOME is not the user's home directory,
# which they use otherwise), else ~/.swiftpm.
if [ -n "${XDG_CONFIG_HOME:-}" ]; then
  sdks="$XDG_CONFIG_HOME/swiftpm/swift-sdks"
else
  sdks="$HOME/.swiftpm/swift-sdks"
fi
bundle="$sdks/darwin.artifactbundle"

if [ "${1:-}" = --pack ]; then
  tar -C "$sdks" -I 'zstd -T0 -19' -cf "$2" darwin.artifactbundle
  ls -lh "$2"
  sha256sum "$2"
  exit 0
fi

download() { # url dest sha256
  # Asks for the raw bytes: some storage APIs answer with metadata otherwise.
  curl -fL --retry 3 --progress-bar -H "Accept: application/octet-stream" \
    ${DOWNLOAD_AUTH_HEADER:+-H "$DOWNLOAD_AUTH_HEADER"} -o "$2" "$1"
  if ! echo "$3  $2" | sha256sum -c --quiet -; then
    echo "scripts/ci/install-sdk.sh: the download does not match the pinned SHA-256 $3" >&2
    exit 1
  fi
}

if [ -d "$bundle" ]; then
  echo "Darwin SDK already installed in $bundle"
elif [ -n "${DARWIN_SDK_URL:-}" ]; then
  mkdir -p "$sdks"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  download "$DARWIN_SDK_URL" "$tmp/sdk.tar.zst" "$DARWIN_SDK_SHA256"
  tar -C "$sdks" -I zstd -xf "$tmp/sdk.tar.zst"
elif [ -n "${XCODE_XIP_URL:-}" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  download "$XCODE_XIP_URL" "$tmp/Xcode.xip" "$XCODE_XIP_SHA256"
  scripts/install-xtool.sh --slim "$tmp/Xcode.xip"
else
  echo "scripts/ci/install-sdk.sh: set DARWIN_SDK_URL or XCODE_XIP_URL (see docs/building-on-linux.md)" >&2
  exit 1
fi
