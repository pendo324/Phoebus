#!/bin/bash
# Runs Apple's appintentsmetadataprocessor (macOS, Xcode 27) on what
# scripts/ci/collect-appintents-input.sh gathered, and writes each target's
# fixture the way Tests/Fixtures/AppIntents/<target> holds it:
# input.swiftconstvalues (all of the target's const values in one array,
# source paths relative to the repository) and Apple's Metadata.appintents.
#
# Usage: scripts/ci/appintents-reference.sh <input dir> <fixtures dir>
#   run with the Xcode to use selected (xcode-select or DEVELOPER_DIR)
set -euo pipefail

input=$(cd "$1" && pwd -P)
mkdir -p "$2"
fixtures=$(cd "$2" && pwd -P)

TC=$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
XCV=$(xcodebuild -version | tail -1 | awk '{print $3}')

targets=$(python3 -c 'import json, sys; print(*json.load(open(sys.argv[1]))["targets"])' "$input/manifest.json")
for target in $targets; do
  work=$(mktemp -d)

  # The processor stops on a source it cannot find, so the const values'
  # paths must name the staged copies.
  python3 - "$input/values/$target" "$work/values" "$input" "$fixtures/$target/input.swiftconstvalues" <<'PY'
import glob, json, os, sys
source, staged, root, merged = sys.argv[1:]
os.makedirs(staged)
os.makedirs(os.path.dirname(merged), exist_ok=True)

def rewrite(x):
    if isinstance(x, dict):
        return {k: root + "/" + v if k == "file" and isinstance(v, str) and v.startswith("Sources/") else rewrite(v)
                for k, v in x.items()}
    if isinstance(x, list):
        return [rewrite(v) for v in x]
    return x

entries = []
for path in sorted(glob.glob(source + "/*.swiftconstvalues")):
    data = json.load(open(path))
    entries.extend(data)
    with open(os.path.join(staged, os.path.basename(path)), "w") as f:
        json.dump(rewrite(data), f, indent=1, ensure_ascii=False)
with open(merged, "w") as f:
    json.dump(entries, f, indent=1, ensure_ascii=False)
    f.write("\n")
PY

  ls -d "$input"/Sources/"$target"/*.swift > "$work/sources.txt"
  ls -d "$work"/values/*.swiftconstvalues > "$work/constvals.txt"

  "$TC/usr/bin/appintentsmetadataprocessor" \
    --output "$work/out" \
    --toolchain-dir "$TC" \
    --module-name "$target" \
    --sdk-root "$SDK" \
    --xcode-version "$XCV" \
    --platform-family iOS \
    --deployment-target 17.0 \
    --target-triple arm64-apple-ios17.0 \
    --source-file-list "$work/sources.txt" \
    --swift-const-vals-list "$work/constvals.txt" \
    --force

  test -f "$work/out/Metadata.appintents/extract.actionsdata"
  rm -rf "$fixtures/$target/Metadata.appintents"
  cp -R "$work/out/Metadata.appintents" "$fixtures/$target/Metadata.appintents"
  rm -rf "$work"
done
