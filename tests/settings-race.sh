#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# settings-race.sh [CUVEE] — two `cuvee set` at once (as Cuvee.app does) must both land in cuvee.conf.
# Uses a throwaway bottle folder, never a real one. Default CUVEE: ./cuvee next to this folder.
set -euo pipefail
CUVEE="${1:-$(dirname "$0")/../cuvee}"
export CUVEE_BOTTLES="$(mktemp -d)" CUVEE_NO_SETUP=1
trap 'rm -rf "$CUVEE_BOTTLES"' EXIT
mkdir -p "$CUVEE_BOTTLES/race/drive_c"
conf="$CUVEE_BOTTLES/race/cuvee.conf"
for i in $(seq 1 20); do
  printf 'graphics=vulkan\nmetalfx=off\n' > "$conf"
  bash "$CUVEE" set race graphics dxmt >/dev/null & bash "$CUVEE" set race metalfx on >/dev/null & wait
  [ "$(sort "$conf" | tr '\n' ' ')" = "graphics=dxmt metalfx=on " ] || { echo "FAIL run $i:"; cat "$conf"; exit 1; }
done
echo "ok: 20 concurrent runs"
