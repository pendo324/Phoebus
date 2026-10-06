#!/bin/bash
# Prepares an Ubuntu 24.04 machine to build Phoebus: the packages the Swift
# toolchain, xtool, libimobiledevice and the icon renderer need, the
# swift.org Swift toolchain and Go (the version scripts/lgrender/go.mod
# asks for). scripts/ci/Dockerfile runs it for the CI image. Safe to re-run.
#
# Usage: scripts/ci/setup-linux.sh
#   SWIFT_VERSION  default 6.4.0
#   SWIFT_DIR, GO_DIR  where the toolchains go, by default under
#                      PHOEBUS_TOOLS (~/.local/lib/phoebus)
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_VERSION="${SWIFT_VERSION:-6.4.0}"
GO_VERSION=$(sed -n 's/^go //p' scripts/lgrender/go.mod)
tools="${PHOEBUS_TOOLS:-$HOME/.local/lib/phoebus}"
SWIFT_DIR="${SWIFT_DIR:-$tools/swift-$SWIFT_VERSION}"
GO_DIR="${GO_DIR:-$tools/go-$GO_VERSION}"
sudo=""
[ "$(id -u)" -eq 0 ] || sudo=sudo

$sudo apt-get update -q
$sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
  binutils ca-certificates git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libgcc-13-dev libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev \
  libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev \
  build-essential autoconf automake libtool-bin libssl-dev liblzma-dev \
  librsvg2-bin python3 curl zip zstd

if [ ! -x "$SWIFT_DIR/usr/bin/swift" ]; then
  url="https://download.swift.org/swift-$SWIFT_VERSION-release/ubuntu2404/swift-$SWIFT_VERSION-RELEASE/swift-$SWIFT_VERSION-RELEASE-ubuntu24.04.tar.gz"
  echo "==> Downloading $url"
  mkdir -p "$SWIFT_DIR"
  curl -fsSL --retry 3 "$url" | tar -xz -C "$SWIFT_DIR" --strip-components=1
fi
"$SWIFT_DIR/usr/bin/swift" --version

if [ ! -x "$GO_DIR/bin/go" ]; then
  mkdir -p "$GO_DIR"
  curl -fsSL --retry 3 "https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz" \
    | tar -xz -C "$GO_DIR" --strip-components=1
fi
"$GO_DIR/bin/go" version
