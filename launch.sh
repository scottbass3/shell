#!/bin/sh
# Quickshell launcher — adds this config dir to QML_IMPORT_PATH so the bundled
# Caelestia.Blobs plugin (built by install.sh into ./Caelestia/Blobs) is found.
# Add to Hyprland autostart, e.g.:  exec-once = ~/.config/quickshell/launch.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
export QML_IMPORT_PATH="${here}:${QML_IMPORT_PATH}"
exec quickshell "$@"
