#!/bin/bash
# Collects what Apple's appintentsmetadataprocessor needs from the last
# `scripts/build-app.sh device` build: each target's const values (with the
# build machine's absolute source paths made relative to the repository)
# and its sources. Run by the App Intents reference workflow; the macOS
# half is scripts/ci/appintents-reference.sh.
#
# Usage: scripts/ci/collect-appintents-input.sh <out dir>
set -euo pipefail
cd "$(dirname "$0")/../.."
out=$1
roots=("$PWD" "$(pwd -P)")

rm -rf "$out"
for target in Phoebus PhoebusWidget; do
  values=".build/out/Intermediates.noindex/Phoebus.build/Release-iphoneos/$target-t.build/Objects-normal/arm64"
  if ! compgen -G "$values/*.swiftconstvalues" >/dev/null; then
    echo "scripts/ci/collect-appintents-input.sh: no const values in $values" >&2
    exit 1
  fi
  mkdir -p "$out/values/$target" "$out/Sources/$target"
  cp "$values"/*.swiftconstvalues "$out/values/$target/"
  cp Sources/"$target"/*.swift "$out/Sources/$target/"
  for root in "${roots[@]}"; do
    sed -i "s|$root/||g" "$out/values/$target"/*.swiftconstvalues
  done
  if grep -E '"file" *: *"/' "$out/values/$target"/*.swiftconstvalues; then
    echo "scripts/ci/collect-appintents-input.sh: absolute source paths remain in $target's const values" >&2
    exit 1
  fi
done

cat > "$out/manifest.json" <<JSON
{
  "targets": ["Phoebus", "PhoebusWidget"],
  "commit": "$(git rev-parse HEAD)"
}
JSON
