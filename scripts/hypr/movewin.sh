#!/usr/bin/env bash
# Move a window to a workspace from the overview WITHOUT changing keyboard focus
# or warping the cursor.
#   movewin.sh <address> <workspace-id> [prev-address]
# The lua `window.move` focuses the moved window (and Hyprland warps the cursor
# to it), so we: disable cursor warps, move silently, restore the previously
# focused window, then restore the warp setting. The previously focused window
# is passed in by the caller (the shell already knows it) — no JSON parsing.
addr="$1"
ws="$2"
prev="$3"
[ -z "$addr" ] || [ -z "$ws" ] && exit 0

orig=$(hyprctl getoption cursor:no_warps | awk -F': ' '/^(int|bool):/{print $2; exit}')
case "$orig" in true|1) restore=true ;; *) restore=false ;; esac

hyprctl keyword cursor:no_warps true >/dev/null

if [ -n "$prev" ] && [ "$prev" != "$addr" ]; then
    hyprctl --batch "dispatch hl.dsp.window.move({window=\"address:$addr\", workspace=$ws, silent=true}) ; dispatch hl.dsp.focus({window=\"address:$prev\"})" >/dev/null
else
    hyprctl dispatch "hl.dsp.window.move({window=\"address:$addr\", workspace=$ws, silent=true})" >/dev/null
fi

hyprctl keyword cursor:no_warps "$restore" >/dev/null
