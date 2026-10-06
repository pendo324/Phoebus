#!/bin/bash
# Adds Metadata.appintents to the app and to its widget extension in the
# last `xtool dev build` (xtool/Phoebus.app), generated on Linux from each
# target's const values by scripts/appintents-metadata.py. Without it the
# configurable widgets get no settings (CHSErrorDomain 1103), and the app's
# intents and App Shortcuts don't reach Shortcuts, Siri or Spotlight.
#
# Usage: scripts/add-appintents-metadata.sh <triple> <configuration>
#   the same triple and configuration the app was built with
#
# Warns when a target's intents differ from the ones the generator was
# checked against (Tests/Fixtures/AppIntents/<target>); see the
# generator's header.
set -euo pipefail
cd "$(dirname "$0")/.."

triple=$1 configuration=$2
case "$triple" in
  *-simulator) sdk=iphonesimulator;;
  *) sdk=iphoneos;;
esac
config="$(tr '[:lower:]' '[:upper:]' <<< "${configuration:0:1}")${configuration:1}"

for target in Phoebus PhoebusWidget; do
  values=".build/out/Intermediates.noindex/Phoebus.build/$config-$sdk/$target-t.build/Objects-normal/${triple%%-*}"
  if [ "$target" = Phoebus ]; then bundle=xtool/Phoebus.app; else bundle=xtool/Phoebus.app/PlugIns/$target.appex; fi

  if ! compgen -G "$values/*.swiftconstvalues" >/dev/null; then
    echo "scripts/add-appintents-metadata.sh: no const values in $values" >&2
    exit 1
  fi
  rm -rf "$bundle/Metadata.appintents"
  scripts/appintents-metadata.py "$bundle/Metadata.appintents" "$values"/*.swiftconstvalues

  # Compare the intents with the checked fixture, ignoring source locations.
  python3 - "$values" "Tests/Fixtures/AppIntents/$target/input.swiftconstvalues" <<'PY'
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
if load(glob.glob(sys.argv[1] + "/*.swiftconstvalues")) != load([sys.argv[2]]):
    print(f"warning: the App Intents in {sys.argv[2].split('/')[-2]} changed since the generator "
          "was checked against Apple's processor; regenerate its fixture on a Mac "
          "(docs/building-on-linux.md, \"AppIntents metadata\")", file=sys.stderr)
PY
done
