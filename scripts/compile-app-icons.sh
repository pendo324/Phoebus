#!/bin/bash
# Compiles the app icons into an asset catalog with actool, so the home
# screen icon follows iOS's Home Screen appearance setting (light, dark,
# tinted, clear, and iOS 26's live glass). Writes Icons/Catalog/:
#   Assets.car                              every icon, in Any, Dark and Tintable
#   LGIcon-phoebus60x60@2x.png,
#   LGIcon-phoebus76x76@2x~ipad.png         the primary icon's loose PNGs
#   partial.plist                           CFBundleIcons and CFBundleIcons~ipad
# xtool.yml ships the first three at the app root; scripts/add-app-icons.py
# merges the plist into the built app's Info.plist.
#
# Each pack icon is three alternate icons, the App Icon picker's appearance
# menu: LGIcon-<id> (System) is Icons/LiquidGlass/<pack>/<id>/<id>.icon,
# LGIcon-<id>__apollo_light (Light) and LGIcon-<id>__apollo_dark (Dark) are
# its single-look variants beside it. actool names an icon after its bundle,
# so they are linked under those names. LGIcon-phoebus is the primary icon.
#
# actool is a reimplementation that runs on Linux
# (https://github.com/pendo324/actool; the build image installs it, see
# docker/build.Dockerfile for the pinned commit): set PHOEBUS_ACTOOL to its
# binary. The catalog is rebuilt only when an icon
# source, this script or the binary changes.
#
# Usage: scripts/compile-app-icons.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."

actool=${PHOEBUS_ACTOOL:-}
if [ -z "$actool" ] || [ ! -x "$actool" ]; then
  cat >&2 <<'MSG'
scripts/compile-app-icons.sh: no actool. The app icons are compiled into an
asset catalog by actool, a reimplementation that runs on Linux:
  cargo install --locked --git https://github.com/pendo324/actool \
    --rev <the ACTOOL_REV pinned in docker/build.Dockerfile> actool
then set PHOEBUS_ACTOOL to the installed binary (~/.cargo/bin/actool).
MSG
  exit 1
fi

primary=LGIcon-phoebus
out=Icons/Catalog
bundles=(Icons/LiquidGlass/*/*/*.icon)

want=$({ cat "$0" "$actool"; find Icons/LiquidGlass -path '*.icon/*' -type f -print0 | sort -z | xargs -0 sha256sum; } | sha256sum | cut -d' ' -f1)
if [ "${1:-}" != --force ] && [ "$(cat "$out/.compiled" 2>/dev/null)" = "$want" ]; then
  echo "compile-app-icons: catalog up to date"
  exit 0
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
alternates=()
for bundle in "${bundles[@]}"; do
  name=LGIcon-$(basename "$bundle" .icon)
  ln -s "$PWD/$bundle" "$stage/$name.icon"
  [ "$name" = "$primary" ] || alternates+=(--alternate-app-icon "$name")
done

rm -rf "$out"
mkdir -p "$out"
"$actool" "$stage"/*.icon --compile "$out" --platform iphoneos \
  --minimum-deployment-target 17.0 --app-icon "$primary" "${alternates[@]}" \
  --target-device iphone --target-device ipad \
  --output-partial-info-plist "$out/partial.plist" >/dev/null
echo "$want" > "$out/.compiled"
echo "compile-app-icons: $((${#alternates[@]} / 2 + 1)) icons compiled into $out/Assets.car ($(du -h "$out/Assets.car" | cut -f1))"
