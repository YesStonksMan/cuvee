#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# msync-leak.sh [SECONDS] — runs tests/msync-leak.exe in a throwaway bottle and fails if wineserver reports its msync
# node pool exhausted (see msync-leak.c and patches/msync-wait-leak.patch). Uses ./dist, never a real bottle.
# Loads 4 CPU cores for SECONDS (default 60); stops as soon as the leak shows.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x dist/bin/wine ] || { echo "skip: build Wine first (dist/bin/wine)"; exit 0; }
[ -f tests/msync-leak.exe ] || x86_64-w64-mingw32-gcc -O2 tests/msync-leak.c -o tests/msync-leak.exe
seconds="${1:-60}"
CUVEE_BOTTLES="$(mktemp -d)"; export CUVEE_BOTTLES CUVEE_NO_SETUP=1
err="$CUVEE_BOTTLES/server.err"
trap './cuvee kill leak >/dev/null 2>&1 || true; rm -rf "$CUVEE_BOTTLES"' EXIT
./cuvee create leak >/dev/null 2>&1
# the wineserver is started by this wine and inherits its stderr
nice ./cuvee run leak "$PWD/tests/msync-leak.exe" "$seconds" 2>"$err" &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  if grep -q "node memory pool exhausted" "$err"; then echo "FAIL: msync leaks wait nodes (pool exhausted)"; exit 1; fi
  sleep 2
done
wait "$pid" || { echo "FAIL: msync-leak.exe did not run"; cat "$err"; exit 1; }
if grep -q "node memory pool exhausted" "$err"; then echo "FAIL: msync leaks wait nodes (pool exhausted)"; exit 1; fi
echo "ok: no msync node leak in ${seconds}s"
