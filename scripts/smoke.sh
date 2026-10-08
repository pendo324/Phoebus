#!/bin/bash
# Build and run the smoke test, reporting HOW it ended.
#
# Piping the binary into `grep FAIL` is not a safe check: a crash prints no
# FAIL line, so every assertion after the crash point silently never runs.
# This checks the exit status and the explicit terminator line instead.
set -uo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=scripts/xtool-env.sh
source scripts/xtool-env.sh
[ -n "${SHIM_DIR:-}" ] && trap 'rm -rf "$SHIM_DIR"' EXIT

# Gate on the build's exit status, not on whether its output contains
# "error:": otherwise a failed build can leave the previous binary to run
# and report a clean pass against code that did not compile. Only
# diagnostics count: SwiftPM warnings can contain "an error: ..." too.
build_log="$("${SWIFT_BUILD[@]}" --product PhoebusCoreSmokeTest 2>&1)"
build_status=$?
if [ "$build_status" -ne 0 ] || printf '%s\n' "$build_log" | grep -qE "(^|: )error:"; then
  printf '%s\n' "$build_log" | grep -E "(^|: )error:" | head -5 | sed 's/^/  /'
  echo "SMOKE: BUILD FAILED"
  exit 2
fi

out="$(./.build/debug/PhoebusCoreSmokeTest 2>&1)"
status=$?

fails="$(printf '%s\n' "$out" | grep -E "^FAIL" || true)"
passes="$(printf '%s\n' "$out" | grep -cE "^PASS" || true)"

if printf '%s\n' "$out" | grep -q "Fatal error"; then
  echo "SMOKE: CRASHED after $passes passes"
  printf '%s\n' "$out" | grep -B 2 "Fatal error" | tail -3
  exit 3
fi

if [ -n "$fails" ]; then
  printf '%s\n' "$fails" | sed 's/^/  /'
  echo "SMOKE: $(printf '%s\n' "$fails" | wc -l) failed, $passes passed"
  exit 1
fi

if ! printf '%s\n' "$out" | grep -q "ALL CHECKS PASSED"; then
  echo "SMOKE: ENDED WITHOUT THE TERMINATOR after $passes passes (exit $status)"
  exit 4
fi

# The App Intents metadata generator, against Apple's output.
if ! appintents_log="$(python3 scripts/appintents-metadata.py --self-test 2>&1)"; then
  printf '%s\n' "$appintents_log" | tail -20 | sed 's/^/  /'
  echo "SMOKE: APP INTENTS METADATA DIFFERS ($passes assertions passed)"
  exit 6
fi

# Also compile the iOS app, unless SMOKE_SKIP_IOS=1. The steps above only
# build PhoebusCore, so without this a green run says nothing about
# PhoebusUI or the app target.
#
# It runs last because scripts/build-for-simulator.sh rebuilds for the iOS
# triple and clears `.build/debug`, deleting the binary the assertions need.
#
# Judged by exit status as well as output.
if [ "${SMOKE_SKIP_IOS:-0}" != "1" ]; then
  ios_log="$(scripts/build-for-simulator.sh 2>&1)"
  ios_status=$?
  ios_errors="$(printf '%s\n' "$ios_log" | grep -E "(^|: )error:|^ERROR:" || true)"
  if [ "$ios_status" -ne 0 ] || [ -n "$ios_errors" ]; then
    printf '%s\n' "${ios_errors:-$(printf '%s\n' "$ios_log" | tail -5)}" | head -5 | sed 's/^/  /'
    echo "SMOKE: iOS BUILD FAILED ($passes assertions passed)"
    exit 5
  fi
fi

echo "SMOKE: ok ($passes passed)"
