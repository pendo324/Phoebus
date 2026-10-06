#!/bin/bash
# Sets each tracked file's modification time to the time of the last
# commit that changed it. SwiftBuild decides what to rebuild from file
# times, so a fresh checkout over a restored .build would otherwise
# rebuild everything. Needs the full history (fetch-depth: 0).
set -euo pipefail
cd "$(dirname "$0")/../.."

git log --format='%x01%ct' --name-only -z HEAD | python3 -c '
import os, sys
done = set()
for record in sys.stdin.buffer.read().split(b"\x01"):
    header, _, files = record.partition(b"\n")
    if not header.strip(b"\0"):
        continue
    when = int(header.strip(b"\0"))
    for name in files.split(b"\0"):
        path = name.decode()
        if path and path not in done and os.path.lexists(path):
            done.add(path)
            os.utime(path, (when, when), follow_symlinks=False)
'
