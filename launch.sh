#!/bin/sh
# Launcher for this shell: puts the Caelestia.Blobs plugin on QML_IMPORT_PATH
# (built into ./Caelestia by install.sh, or installed to
# /usr/lib/scottbass3-shell/qml by the AUR package) and runs this config.
# Started by hypr/quickshell.lua; the package links it as /usr/bin/scottbass3-shell.
here=$(dirname -- "$(readlink -f -- "$0")")
for d in /usr/lib/scottbass3-shell/qml "$here"; do
    [ -d "$d/Caelestia/Blobs" ] && QML_IMPORT_PATH="$d${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
done
export QML_IMPORT_PATH
exec quickshell -p "$here" "$@"
