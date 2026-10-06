#!/bin/bash
# Packages a built Phoebus.app as an unsigned .ipa (Payload/Phoebus.app,
# compressed) and checks it with check-app.py. AltStore and SideStore sign
# the IPA on the device.
#
# Usage: scripts/package-ipa.sh <Phoebus.app> <output.ipa>
set -euo pipefail

app=$(realpath "$1")
ipa=$(realpath -m "$2")
mkdir -p "$(dirname "$ipa")"
rm -f "$ipa"

payload=$(mktemp -d)
trap 'rm -rf "$payload"' EXIT
mkdir "$payload/Payload"
# The bundle is named after its executable, whatever the input is called.
exe=$(python3 -c "import plistlib, sys; print(plistlib.load(open(sys.argv[1], 'rb'))['CFBundleExecutable'])" "$app/Info.plist")
cp -R "$app" "$payload/Payload/$exe.app"
(cd "$payload" && zip -yqr "$ipa" Payload)

"$(dirname "$0")/check-app.py" "$ipa"
