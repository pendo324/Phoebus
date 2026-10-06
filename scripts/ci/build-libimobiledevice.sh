#!/bin/bash
# Builds libimobiledevice and the libraries it needs into a prefix, for
# building xtool on a distribution whose packages are older than xtool
# needs (Ubuntu 24.04 among them). The versions are the latest releases.
#
# Usage: scripts/ci/build-libimobiledevice.sh <prefix>
# Then build xtool with PKG_CONFIG_PATH=<prefix>/lib/pkgconfig and
# XTOOL_BUNDLE_LIBS_FROM=<prefix>/lib (see scripts/install-xtool.sh).
set -euo pipefail

prefix=$(realpath -m "$1")
src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

for lib in libplist@2.7.0 libimobiledevice-glue@1.3.3 libusbmuxd@2.1.1 libtatsu@1.0.5 libimobiledevice@1.4.0; do
  name=${lib%@*} version=${lib#*@}
  echo "==> $name $version"
  git clone -q --depth 1 --branch "$version" "https://github.com/libimobiledevice/$name" "$src/$name"
  (
    cd "$src/$name"
    ./autogen.sh --prefix="$prefix" --without-cython >/dev/null
    make -j"$(nproc)" >/dev/null
    make install >/dev/null
  )
done
