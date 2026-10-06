#!/usr/bin/env python3
"""Sets CFBundleVersion in a built app and its extensions, and their
CFBundleShortVersionString to the app's, as iOS expects the extensions to
match. The repository's Info.plist only changes for a release, so each
distributed build gets its build number here instead.

Usage: scripts/stamp-build-number.py <Phoebus.app> <build number>
"""
import glob
import plistlib
import sys


def main():
    if len(sys.argv) != 3 or not sys.argv[2].isdigit():
        sys.exit(__doc__.strip().splitlines()[-1])
    app, build = sys.argv[1], sys.argv[2]
    version = plistlib.load(open(f"{app}/Info.plist", "rb"))["CFBundleShortVersionString"]
    for path in [f"{app}/Info.plist"] + glob.glob(f"{app}/PlugIns/*.appex/Info.plist"):
        info = plistlib.load(open(path, "rb"))
        info["CFBundleShortVersionString"] = version
        info["CFBundleVersion"] = build
        with open(path, "wb") as f:
            plistlib.dump(info, f)
    print(f"{app}: {version} ({build})")


if __name__ == "__main__":
    main()
