#!/usr/bin/env bash
# Restore keyboard focus to the window recorded in $1, after a layer-shell
# surface (launcher / tools toolbar) released its exclusive keyboard grab.
#
# Hyprland keeps that window as `activewindow` during the grab, so re-focusing
# it is a no-op and leaves the keyboard in limbo (the state escaped by manually
# switching window and back). We force a real focus change: bounce through
# another window on the same workspace, or — if it's the only window — through
# an empty workspace on this monitor, then return to the target.
#   refocus-prev.sh <prevwin-file>
file="$1"
[ -z "$file" ] && exit 0
a=$(cat "$file" 2>/dev/null)
[ -z "$a" ] && exit 0

other=$(hyprctl clients -j | jq -r --arg a "$a" '
    ([.[] | select(.address == $a)][0].workspace.id) as $ws
    | [.[] | select(.address != $a and .workspace.id == $ws and .mapped)][0].address // ""')

if [ -n "$other" ]; then
    # Bounce through another window on the same workspace (no view change).
    hyprctl --batch \
        "dispatch hl.dsp.focus({window = \"address:$other\"}) ; dispatch hl.dsp.focus({window = \"address:$a\"})" \
        >/dev/null 2>&1
else
    # Only one window: bounce through an empty workspace on this monitor and
    # back. The brief switch is the focus change needed to re-grant the keyboard.
    hyprctl --batch \
        "dispatch hl.dsp.focus({workspace = \"emptynm\"}) ; dispatch hl.dsp.focus({window = \"address:$a\"})" \
        >/dev/null 2>&1
fi
