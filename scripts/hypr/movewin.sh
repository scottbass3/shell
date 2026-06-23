#!/usr/bin/env bash
# Move a window to a workspace from the overview WITHOUT changing keyboard focus
# or warping the cursor.
#   movewin.sh <address> <workspace-id>
# The lua `window.move` focuses the moved window (and Hyprland warps the cursor
# to it), so we: disable cursor warps, move silently, restore the previously
# focused window, then restore the warp setting.
addr="$1"
ws="$2"
[ -z "$addr" ] || [ -z "$ws" ] && exit 0

prev=$(hyprctl activewindow -j | jq -r '.address // empty')
orig=$(hyprctl getoption cursor:no_warps -j | jq -r '.int')

hyprctl keyword cursor:no_warps true >/dev/null

if [ -n "$prev" ] && [ "$prev" != "$addr" ]; then
    hyprctl --batch "dispatch hl.dsp.window.move({window=\"address:$addr\", workspace=$ws, silent=true}) ; dispatch hl.dsp.focus({window=\"address:$prev\"})" >/dev/null
else
    hyprctl dispatch "hl.dsp.window.move({window=\"address:$addr\", workspace=$ws, silent=true})" >/dev/null
fi

if [ "$orig" = "1" ]; then
    hyprctl keyword cursor:no_warps true  >/dev/null
else
    hyprctl keyword cursor:no_warps false >/dev/null
fi
