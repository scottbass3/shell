#!/usr/bin/env bash
# Capture the currently-focused window (before Quickshell grabs the keyboard)
# so it can be re-focused when the toolbar closes, then toggle the toolbar.
a=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // ""')
[ -n "$a" ] && printf '%s' "$a" > /tmp/qs-tools-prevwin
qs ipc call tools toggle
