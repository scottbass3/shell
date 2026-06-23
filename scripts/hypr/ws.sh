#!/usr/bin/env bash
# Per-monitor workspace switch / move.
#   ws.sh <n> [move]
# Each monitor id k owns workspaces k*10+1 .. k*10+10:
#   eDP-1 (id 0)    → 1-10
#   HDMI-A-1 (id 1) → 11-20
#
#  - switch: use the FOCUSED monitor (cursor/keyboard)
#  - move:   use the ACTIVE WINDOW's monitor, so it stays on its own screen
#
# workspace_rule monitor= only applies when a workspace is first created; an
# existing workspace can drift onto the wrong monitor. So we pin the target
# workspace to its home monitor before acting (self-healing, idempotent).
n="$1"
action="$2"
[ -z "$n" ] && exit 0

mons=$(hyprctl monitors -j)

if [ "$action" = "move" ]; then
    monid=$(hyprctl activewindow -j | jq -r '.monitor')
else
    monid=$(echo "$mons" | jq -r '.[] | select(.focused) | .id')
fi
case "$monid" in
    ''|*[!0-9]*) monid=$(echo "$mons" | jq -r '.[] | select(.focused) | .id') ;;
esac
[ -z "$monid" ] && monid=0

monname=$(echo "$mons" | jq -r --argjson m "$monid" '.[] | select(.id==$m) | .name')
ws=$(( monid * 10 + n ))

# Pin the target workspace to its home monitor (fixes drift). Ignore errors
# when the workspace doesn't exist yet — focus/move below will create it on the
# correct monitor via its workspace_rule.
[ -n "$monname" ] && hyprctl dispatch "hl.dsp.workspace.move({workspace = \"$ws\", monitor = \"$monname\"})" >/dev/null 2>&1

if [ "$action" = "move" ]; then
    hyprctl dispatch "hl.dsp.window.move({workspace = $ws})"
else
    hyprctl dispatch "hl.dsp.focus({workspace = $ws})"
fi
