#!/usr/bin/env bash
# Super+S behavior:
#   - if ANY special workspace is open on the focused monitor → close it
#   - otherwise → open special:magic
# (Hyprland 0.55 lua IPC: dispatch arg is evaluated as hl.dispatch(<arg>),
#  so we pass the dispatcher expression, not the legacy string.)

open=$(hyprctl monitors -j 2>/dev/null | python3 -c '
import sys, json
ms = json.load(sys.stdin)
f = next((m for m in ms if m.get("focused")), ms[0] if ms else None)
print((f or {}).get("specialWorkspace", {}).get("name", "") if f else "")
')

if [ -n "$open" ]; then
    ws="${open#special:}"
    hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$ws\")"
else
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("magic")'
fi
