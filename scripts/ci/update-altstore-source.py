#!/usr/bin/env python3
"""Adds a build to an AltStore source (source.json, format v2).

Usage: scripts/ci/update-altstore-source.py <source.json> <app.ipa>
           --url <download URL> --notes <text> [--keep N] [--app <app.json>]

Reads the version, build number, minimum iOS, privacy usage descriptions
and entitlements from the IPA, and adds it as the newest version of its app
(by bundle identifier), replacing an entry with the same build number. The
app's entry is created from --app (scripts/ci/altstore-app.json by default)
the first time. With --keep, only the newest N versions are kept.
"""
import argparse
import datetime
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path

ENTITLEMENTS_BLOB = 0xFADE7171


def entitlements(binary):
    """The entitlement keys in a thin or universal Mach-O's code signature."""
    if struct.unpack_from(">I", binary)[0] == 0xCAFEBABE:
        offset, size = struct.unpack_from(">II", binary, 8 + 8)
        binary = binary[offset:offset + size]
    ncmds = struct.unpack_from("<I", binary, 16)[0]
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", binary, off)
        if cmd == 0x1D:  # LC_CODE_SIGNATURE
            sig = struct.unpack_from("<I", binary, off + 8)[0]
            count = struct.unpack_from(">I", binary, sig + 8)[0]
            for i in range(count):
                blob = sig + struct.unpack_from(">II", binary, sig + 12 + i * 8)[1]
                magic, length = struct.unpack_from(">II", binary, blob)
                if magic == ENTITLEMENTS_BLOB:
                    return sorted(plistlib.loads(binary[blob + 8:blob + length]).keys())
        off += size
    return []


def read_ipa(path):
    with zipfile.ZipFile(path) as z:
        app = next(n.split("/")[1] for n in z.namelist() if n.startswith("Payload/") and n.count("/") >= 2)
        info = plistlib.loads(z.read(f"Payload/{app}/Info.plist"))
        binary = z.read(f"Payload/{app}/{info['CFBundleExecutable']}")
    privacy = {k: v for k, v in sorted(info.items()) if k.startswith("NS") and k.endswith("UsageDescription")}
    return info, privacy, entitlements(binary)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("ipa")
    parser.add_argument("--url", required=True)
    parser.add_argument("--notes", required=True)
    parser.add_argument("--keep", type=int, default=0)
    parser.add_argument("--app", default=str(Path(__file__).with_name("altstore-app.json")))
    args = parser.parse_args()

    source_path = Path(args.source)
    source = json.loads(source_path.read_text())
    info, privacy, ents = read_ipa(args.ipa)
    data = Path(args.ipa).read_bytes()

    bundle_id = info["CFBundleIdentifier"]
    app = next((a for a in source.setdefault("apps", []) if a["bundleIdentifier"] == bundle_id), None)
    if app is None:
        app = json.loads(Path(args.app).read_text())
        app["bundleIdentifier"] = bundle_id
        app["versions"] = []
        source["apps"].append(app)
    app["appPermissions"] = {"entitlements": ents, "privacy": privacy}

    version = {
        "version": info["CFBundleShortVersionString"],
        "buildVersion": info["CFBundleVersion"],
        "date": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
        "localizedDescription": args.notes,
        "downloadURL": args.url,
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "minOSVersion": info.get("MinimumOSVersion", "17.0"),
    }
    versions = [v for v in app["versions"] if v["buildVersion"] != version["buildVersion"]]
    versions.insert(0, version)
    if args.keep:
        versions = versions[:args.keep]
    app["versions"] = versions

    source_path.write_text(json.dumps(source, indent=2, ensure_ascii=False) + "\n")
    print(f"{source_path}: {app['name']} {version['version']} ({version['buildVersion']}), "
          f"{len(versions)} versions")


if __name__ == "__main__":
    main()
