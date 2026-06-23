#!/usr/bin/env bash
# Set wallpaper on all monitors and regenerate Quickshell theme via matugen.
# Usage: setwallpaper.sh <image_path>

set -euo pipefail

IMAGE="$1"
QS_THEME_DIR="$HOME/.config/quickshell/theme"
MATUGEN_CFG="$QS_THEME_DIR/matugen/matugen.toml"
ACTIVE_JSON="$QS_THEME_DIR/active.json"

# Apply wallpaper via hyprpaper IPC
hyprctl hyprpaper preload "$IMAGE"
hyprctl hyprpaper wallpaper ",$IMAGE"   # empty monitor = all monitors

# Generate Material You theme from the new wallpaper
matugen -c "$MATUGEN_CFG" image --source-color-index 0 "$IMAGE"

# Switch active theme to wallpaper (Quickshell watches active.json)
printf '{"theme":"wallpaper"}' > "$ACTIVE_JSON"
