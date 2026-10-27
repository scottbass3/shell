pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "../theme"

// Copies this user's wallpaper, theme colors and avatar (~/.face) for
// scottbass3-greeter, which shows them on the login screen while this user is
// selected. Turning it off removes the copy.
QtObject {
    id: root

    readonly property string dir: "/var/lib/scottbass3-greeter/users/" + (Quickshell.env("USER") || "")
    readonly property bool installed: DependencyService.available("greeter")
    readonly property bool enabled: SettingsService.get("greeter.sync", false)
    property string error: ""

    // The saved wallpaper, not one being previewed in the picker.
    readonly property string _wallpaper: SettingsService.get("wallpaper.path", "")
    readonly property var _roles: [
        "primary", "onPrimary", "secondaryContainer", "surface", "surfaceContainer",
        "surfaceContainerHigh", "onSurface", "onSurfaceVariant", "outlineVariant", "error", "onError"
    ]

    readonly property var _watch: [enabled, installed, _wallpaper, ThemeManager.activeId, ThemeManager.themeData]
    on_WatchChanged: _debounce.restart()

    // Theme changes come in bursts (a new wallpaper regenerates its theme).
    property Timer _debounce: Timer {
        interval: 3000
        onTriggered: {
            if (!root.installed || Quickshell.env("USER") === "") return
            if (!root.enabled) { root._remove(); return }
            const shown = WallpaperService.current
            if (shown !== "" && shown !== root._wallpaper) { restart(); return }
            root._sync()
        }
    }

    // A failed copy (e.g. the greeter package not updated yet) is retried.
    property Timer _retry: Timer {
        interval: 30000
        repeat: true
        running: root.enabled && root.installed && root.error !== ""
        onTriggered: root._debounce.restart()
    }

    function _sync() {
        const colors = {}
        for (const r of _roles) colors[r] = ThemeManager.roleHex(r)
        _run(["sh", "-c", _syncScript, "sh", dir, _wallpaper, JSON.stringify(colors)])
    }
    function _remove() {
        _run(["sh", "-c", '[ ! -d "$1" ] || rm -rf -- "$1"', "sh", dir])
    }
    function _run(command) {
        _proc.running = false
        _proc.command = command
        _proc.running = true
    }

    readonly property string _syncScript: `
        set -e
        dir=$1 wall=$2 colors=$3
        [ -d "\${dir%/*}" ] || { echo "the greeter's shared directory is missing" >&2; exit 1; }
        mkdir -p "$dir"
        chmod 755 "$dir"
        name=
        if [ -f "$wall" ]; then
            ext=$(printf %s "\${wall##*.}" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
            name="wallpaper.\${ext:-img}"
            cmp -s "$wall" "$dir/$name" || cp -f "$wall" "$dir/$name"
        fi
        for f in "$dir"/wallpaper.*; do
            [ -e "$f" ] && [ "$f" != "$dir/$name" ] && rm -f "$f"
        done
        face=
        if [ -f "$HOME/.face" ]; then
            cmp -s "$HOME/.face" "$dir/face" || cp -f "$HOME/.face" "$dir/face"
            face=face
        else
            rm -f "$dir/face"
        fi
        printf '{"wallpaper":"%s","avatar":"%s","colors":%s}\\n' "$name" "$face" "$colors" > "$dir/theme.json.new"
        mv -f "$dir/theme.json.new" "$dir/theme.json"
        chmod 644 "$dir"/*`

    property Process _proc: Process {
        stderr: StdioCollector { onStreamFinished: root.error = text.trim() }
    }
}
