#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# steam-fps-test.sh LABEL DIST BOTTLE [ENV=VAL ...] — start Steam, launch Brawlhalla (291550), capture the top-left corner
# (Steam FPS counter) to LABEL_screen.png, try Shift+Tab, shut everything down. Example:
#   tests/steam-fps-test.sh check ~/Library/Application\ Support/Cuvee/runtime/dist ~/Library/Application\ Support/Cuvee/Bottles/Steam
S="$(cd "$(dirname "$0")" && pwd)"; OUT="${OUT:-$S/out}"; mkdir -p "$OUT"; LABEL="$1"; DIST="$2"; B="$3"; shift 3
LOG="$OUT/fps_$LABEL.log"; SD="$B/drive_c/Program Files (x86)/Steam"
run() { (cd "$SD" && env WINEPREFIX="$B" WINEDEBUG=-all WINEMSYNC=1 DYLD_FALLBACK_LIBRARY_PATH="$DIST/lib:/usr/lib" "$@" "$DIST/bin/wine" steam.exe $EXTRA); }
EXTRA="" run "$@" > "$LOG" 2>&1 &
for i in $(seq 1 60); do swift "$S/wine-windows.swift" 2>/dev/null | awk '$(NF-1)==1 && $(NF-3)>=1000' | grep -q '\[Steam\]' && break; sleep 3; done
sleep 10
EXTRA="steam://rungameid/291550" run "$@" >> "$LOG" 2>&1 &
W=""; for i in $(seq 1 60); do W=$(swift "$S/wine-windows.swift" 2>/dev/null | grep '\[Brawlhalla\]' | awk '$(NF-1)==1' | head -1); [ -n "$W" ] && break; sleep 3; done
if [ -z "$W" ]; then echo "no game window"; else
  sleep 45; P=$(echo "$W" | awk '{print $1}')
  for k in 1 2 3; do osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $P) to true"; sleep 2; done
  screencapture -x -R0,0,320,90 "$OUT/fps_${LABEL}_screen.png"
  F=$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true')
  if [ "$F" = "$P" ]; then
    osascript -e 'tell application "System Events" to key code 48 using shift down'; sleep 4
    screencapture -x "$OUT/fps_${LABEL}_overlay.png"
    osascript -e 'tell application "System Events" to key code 48 using shift down'; sleep 2
  else echo "game not frontmost ($F), overlay skipped"; fi
  echo "captured $LABEL"
fi
pkill -f '[B]rawlhalla.exe'; sleep 3
EXTRA="-shutdown" run "$@" >/dev/null 2>&1
for i in $(seq 1 30); do pgrep -f '[s]team.exe' >/dev/null || break; sleep 2; done
WINEPREFIX="$B" "$DIST/bin/wineserver" -k 2>/dev/null; sleep 2
