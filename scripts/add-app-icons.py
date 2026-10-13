#!/usr/bin/env python3
"""Declares the compiled app icons in a built app: merges CFBundleIcons and
CFBundleIcons~ipad from scripts/compile-app-icons.sh's partial plist into the
app's Info.plist, replacing what is there, after checking that xtool put the
catalog and the primary icon's PNGs at the app's root.

Usage: add-app-icons.py <app>
"""

import plistlib
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[1] / "Icons" / "Catalog"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[-1])
    app = Path(sys.argv[1])
    partial = plistlib.loads((CATALOG / "partial.plist").read_bytes())
    for name in ["Assets.car"] + [p.name for p in CATALOG.glob("*.png")]:
        if (app / name).read_bytes() != (CATALOG / name).read_bytes():
            sys.exit(f"add-app-icons.py: {app}/{name} is not {CATALOG}/{name}; is it in xtool.yml?")
    path = app / "Info.plist"
    info = plistlib.loads(path.read_bytes())
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        info[key] = partial[key]
    path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY if path.read_bytes().startswith(b"bplist") else plistlib.FMT_XML))
    alternates = len(partial["CFBundleIcons"].get("CFBundleAlternateIcons", {}))
    print(f"add-app-icons.py: {app.name}: primary {partial['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName']}, {alternates} alternates")


if __name__ == "__main__":
    main()
