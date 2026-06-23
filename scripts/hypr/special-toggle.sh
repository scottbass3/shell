#!/usr/bin/env bash
# Super+S behavior:
#   - if ANY special workspace is open on the focused monitor → close it
#   - otherwise → open special:magic
# (Hyprland 0.55 lua IPC: dispatch arg is evaluated as hl.dispatch(<arg>),
#  so we pass the dispatcher expression, not the legacy string.)

open=$(hyprctl monitors -j 2>/dev/null | jq -r 'map(select(.focused))[0].specialWorkspace.name // ""')

if [ -n "$open" ]; then
    ws="${open#special:}"
    hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$ws\")"
else
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("magic")'
fi
