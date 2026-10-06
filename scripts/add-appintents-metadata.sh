#!/bin/bash
# Adds Metadata.appintents to the widget extension of the last
# `xtool dev build` (xtool/Phoebus.app), generated on Linux from the
# widget's const values by scripts/appintents-metadata.py. Without it the
# configurable widgets get no settings (CHSErrorDomain 1103).
#
# Usage: scripts/add-appintents-metadata.sh <triple> <configuration>
#   the same triple and configuration the app was built with
#
# Warns when the widget's intents differ from the ones the generator was
# checked against (Tests/Fixtures/AppIntents); see the generator's header.
set -euo pipefail
cd "$(dirname "$0")/.."

triple=$1 configuration=$2
case "$triple" in
  *-simulator) sdk=iphonesimulator;;
  *) sdk=iphoneos;;
esac
config="$(tr '[:lower:]' '[:upper:]' <<< "${configuration:0:1}")${configuration:1}"
values=".build/out/Intermediates.noindex/Phoebus.build/$config-$sdk/PhoebusWidget-t.build/Objects-normal/${triple%%-*}"
appex=xtool/Phoebus.app/PlugIns/PhoebusWidget.appex

if ! compgen -G "$values/*.swiftconstvalues" >/dev/null; then
  echo "scripts/add-appintents-metadata.sh: no const values in $values" >&2
  exit 1
fi
rm -rf "$appex/Metadata.appintents"
scripts/appintents-metadata.py "$appex/Metadata.appintents" "$values"/*.swiftconstvalues

# Compare the intents with the checked fixture, ignoring source locations.
python3 - "$values" <<'PY'
import glob, json, sys
def strip(x):
    if isinstance(x, dict):
        return {k: strip(v) for k, v in x.items() if k not in ("file", "line")}
    if isinstance(x, list):
        return [strip(v) for v in x]
    return x
def load(paths):
    entries = [e for p in paths for e in json.load(open(p))]
    return sorted((strip(e) for e in entries), key=lambda e: e["typeName"])
current = load(glob.glob(sys.argv[1] + "/*.swiftconstvalues"))
checked = load(["Tests/Fixtures/AppIntents/input.swiftconstvalues"])
if current != checked:
    print("warning: the widget's App Intents changed since the generator was checked against "
          "Apple's processor; regenerate Tests/Fixtures/AppIntents on a Mac "
          "(scripts/appintents-metadata.py --help)", file=sys.stderr)
PY
