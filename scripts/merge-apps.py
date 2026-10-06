#!/usr/bin/env python3
"""Merges builds of the same .app for different architectures into one
universal .app, like `lipo -create` applied to every Mach-O file in the
bundle (the toolchain on Linux has no lipo).

Usage: scripts/merge-apps.py <out.app> <in.app> <in.app> [...]

The first input supplies everything that is not a Mach-O file. Each slice
keeps its own code signature.
"""
import shutil
import struct
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
ALIGN = 14  # 16 KB, what arm64 requires


def is_macho(path):
    with open(path, "rb") as f:
        head = f.read(4)
    return len(head) == 4 and struct.unpack("<I", head)[0] == MH_MAGIC_64


def fat(slices):
    """A fat binary from thin 64-bit Mach-O slices."""
    header = struct.pack(">II", FAT_MAGIC, len(slices))
    offset = 1 << ALIGN
    arches, body = [], b""
    for data in slices:
        cputype, cpusubtype = struct.unpack_from("<ii", data, 4)
        arches.append(struct.pack(">iiIII", cputype, cpusubtype, offset, len(data), ALIGN))
        padded = data + b"\0" * (-len(data) % (1 << ALIGN))
        body += padded
        offset += len(padded)
    head = header + b"".join(arches)
    return head + b"\0" * ((1 << ALIGN) - len(head)) + body


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__.strip().splitlines()[3])
    out, inputs = Path(sys.argv[1]), [Path(p) for p in sys.argv[2:]]
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(inputs[0], out, symlinks=True)
    merged = 0
    for path in sorted(p for p in out.rglob("*") if p.is_file() and not p.is_symlink()):
        if not is_macho(path):
            continue
        rel = path.relative_to(out)
        slices = [(src / rel).read_bytes() for src in inputs]
        cpus = {struct.unpack_from("<i", s, 4)[0] for s in slices}
        if len(cpus) != len(slices):
            sys.exit(f"merge-apps: {rel} has the same architecture twice")
        mode = path.stat().st_mode
        path.write_bytes(fat(slices))
        path.chmod(mode)
        merged += 1
    print(f"{out.name}: {merged} Mach-O files merged from {len(inputs)} builds")


if __name__ == "__main__":
    main()
