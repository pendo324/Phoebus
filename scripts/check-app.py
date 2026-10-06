#!/usr/bin/env python3
"""Checks a built Phoebus.app or .ipa for the ways a build can come out
broken without the build itself failing.

Usage: scripts/check-app.py <Phoebus.app | Phoebus.ipa>

Checked:
- every executable (app and extensions) is a 64-bit Mach-O, or a
  universal one with a slice per architecture, whose LC_BUILD_VERSION
  platform matches the others and whose minimum OS matches its Info.plist;
- extension executables have real code, not the few-kilobyte stubs a
  broken xtool links;
- extensions have an NSExtension point, an identifier under the app's,
  and no Frameworks/ of their own (the libraries belong to the app);
- the version strings are numeric;
- every icon file Info.plist declares is in the bundle;
- the widget extension carries Metadata.appintents (a warning only:
  generating it needs a Mac, see docs/building-on-linux.md).

Prints one line per failure and exits 1 if there are any.
"""
import plistlib
import re
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

LC_SEGMENT_64 = 0x19
LC_BUILD_VERSION = 0x32
PLATFORMS = {2: "iOS", 7: "iOS Simulator"}

failures = []


def fail(msg):
    failures.append(msg)
    print(f"FAIL {msg}")


def version(v):
    return f"{v >> 16}.{(v >> 8) & 0xff}.{v & 0xff}"


def macho(path):
    """[(platform, minos, sdk, __text size)] per slice, or None if a slice is
    not a 64-bit Mach-O with LC_BUILD_VERSION. Universal files have a slice
    per architecture (the simulator build)."""
    data = path.read_bytes()
    if len(data) >= 8 and struct.unpack_from(">I", data)[0] == 0xCAFEBABE:
        slices = []
        for i in range(struct.unpack_from(">I", data, 4)[0]):
            offset, size = struct.unpack_from(">II", data, 8 + i * 20 + 8)
            slices.append(thin(data[offset:offset + size]))
        return None if None in slices or not slices else slices
    one = thin(data)
    return None if one is None else [one]


def thin(data):
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        return None
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off, build, text = 32, None, 0
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == LC_BUILD_VERSION:
            build = struct.unpack_from("<III", data, off + 8)
        elif cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            for i in range(nsects):
                s = off + 72 + i * 80
                if data[s:s + 16].rstrip(b"\0") == b"__text":
                    text += struct.unpack_from("<Q", data, s + 40)[0]
        off += size
    if build is None:
        return None
    return build[0], build[1], build[2], text


def check_bundle(bundle, info, binaries):
    exe = bundle / info.get("CFBundleExecutable", "")
    if not exe.is_file():
        fail(f"{bundle.name}: executable {exe.name!r} is missing")
        return None
    slices = macho(exe)
    if slices is None:
        fail(f"{bundle.name}: {exe.name} is not a 64-bit Mach-O with LC_BUILD_VERSION")
        return None
    plist_min = (info.get("MinimumOSVersion", "") + ".0.0").split(".")[:3]
    for platform, minos, sdk, _ in slices:
        binaries.append((bundle.name, platform, sdk))
        if version(minos) != ".".join(plist_min):
            fail(f"{bundle.name}: Mach-O minimum OS {version(minos)} != MinimumOSVersion {info.get('MinimumOSVersion')}")
    return min(text for *_, text in slices)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[2])
    path = Path(sys.argv[1])
    tmp = None
    if path.suffix == ".ipa":
        tmp = tempfile.TemporaryDirectory()
        with zipfile.ZipFile(path) as z:
            z.extractall(tmp.name)
        apps = list((Path(tmp.name) / "Payload").glob("*.app"))
        if len(apps) != 1:
            sys.exit(f"FAIL expected one app in Payload/, found {len(apps)}")
        app = apps[0]
    else:
        app = path

    info = plistlib.loads((app / "Info.plist").read_bytes())
    app_id = info.get("CFBundleIdentifier", "")
    binaries = []
    check_bundle(app, info, binaries)

    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if not re.fullmatch(r"\d+(\.\d+){0,2}", str(info.get(key, ""))):
            fail(f"{key} {info.get(key)!r} is not up to three integers")

    icons = info.get("CFBundleIcons", {})
    declared = [icons.get("CFBundlePrimaryIcon", {})] + list(icons.get("CFBundleAlternateIcons", {}).values())
    missing = [f for icon in declared for f in icon.get("CFBundleIconFiles", [])
               if not any(app.glob(f"{f}*.png"))]
    if missing:
        fail(f"{len(missing)} declared icon files are missing, e.g. {missing[0]} (run scripts/generate-icons.sh)")

    for appex in sorted((app / "PlugIns").glob("*.appex")):
        ainfo = plistlib.loads((appex / "Info.plist").read_bytes())
        text = check_bundle(appex, ainfo, binaries)
        if text is not None and text < 1024:
            fail(f"{appex.name}: only {text} bytes of code, a stub rather than the extension")
        point = ainfo.get("NSExtension", {}).get("NSExtensionPointIdentifier")
        if not point:
            fail(f"{appex.name}: no NSExtension point")
        if not ainfo.get("CFBundleIdentifier", "").startswith(app_id + "."):
            fail(f"{appex.name}: identifier {ainfo.get('CFBundleIdentifier')} is not under {app_id}")
        if (appex / "Frameworks").exists():
            fail(f"{appex.name}: has its own Frameworks/")
        if point == "com.apple.widgetkit-extension" and not (appex / "Metadata.appintents").exists():
            print(f"warning: {appex.name}: no Metadata.appintents, configurable widgets will fail")

    if len({(p, s) for _, p, s in binaries}) > 1:
        fail("executables disagree on platform or SDK: " + ", ".join(
            f"{n} {PLATFORMS.get(p, p)} sdk {version(s)}" for n, p, s in binaries))

    if binaries:
        _, p, s = binaries[0]
        print(f"{app.name}: {len({n for n, _, _ in binaries})} executables, {PLATFORMS.get(p, p)}, "
              f"sdk {version(s)}, minimum {info.get('MinimumOSVersion')}"
              + (f", {len(failures)} failures" if failures else ", ok"))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
