#!/usr/bin/env python3
"""Sets the version (CFBundleShortVersionString), and optionally the build
number (CFBundleVersion), of a built app and its extensions, which iOS
expects to match the app's. The repository's Info.plist only holds a
placeholder: each build gets its version from the release tags
(scripts/version.sh) and its build number from CI or the local deploy.

Usage: scripts/stamp-version.py <Phoebus.app> <version> [build number]
"""
import glob
import plistlib
import re
import sys


def main():
    args = sys.argv[1:]
    if len(args) not in (2, 3) or not re.fullmatch(r"\d+\.\d+\.\d+", args[1]) \
            or (len(args) == 3 and not args[2].isdigit()):
        sys.exit(__doc__.strip().splitlines()[-1])
    app, version = args[0], args[1]
    build = args[2] if len(args) == 3 else None
    for path in [f"{app}/Info.plist"] + glob.glob(f"{app}/PlugIns/*.appex/Info.plist"):
        info = plistlib.load(open(path, "rb"))
        info["CFBundleShortVersionString"] = version
        if build is not None:
            info["CFBundleVersion"] = build
        with open(path, "wb") as f:
            plistlib.dump(info, f)
    app_info = plistlib.load(open(f"{app}/Info.plist", "rb"))
    print(f"{app}: {version} ({app_info['CFBundleVersion']})")


if __name__ == "__main__":
    main()
