pragma Singleton
import QtQuick
import Quickshell.Io
import "."
import "../theme"

// Lists wallpapers in ~/wallpaper and applies one via hyprpaper + matugen theme.
//   preview(path) — set wallpaper live + regenerate theme, WITHOUT persisting
//   commit(path)  — preview + persist to hyprpaper.conf
QtObject {
    id: root

    property var    wallpapers: []   // absolute file paths
    property string current:    ""

    function refresh() { _list.running = true }

    // Live apply (hyprpaper) + matugen theme; no config persistence.
    function preview(path) {
        if (!path) return
        current = path
        _live.command = ["sh", "-c", _liveScript, "sh", path]
        _live.running = true
        ThemeManager.generateWallpaperTheme(path)
    }

    // Preview + persist (settings + hyprpaper.conf) so it survives a restart.
    function commit(path) {
        if (!path) return
        preview(path)
        SettingsService.set("wallpaper.path", path)
        _persistProc.command = ["sh", "-c", _persistScript, "sh", path]
        _persistProc.running = true
    }

    // Re-apply the saved wallpaper image on startup WITHOUT regenerating the
    // theme — the active theme is persisted separately by ThemeManager, so
    // running matugen here would clobber a theme the user kept.
    function _restore(path) {
        if (!path) return
        current = path
        _live.command = ["sh", "-c", _liveScript, "sh", path]
        _live.running = true
    }

    // Back-compat alias (mouse click = immediate commit)
    function apply(path) { commit(path) }

    readonly property string _liveScript:
        "WP=\"$1\"; " +
        "pgrep -x hyprpaper >/dev/null || { hyprpaper >/dev/null 2>&1 & sleep 0.6; }; " +
        "hyprctl hyprpaper preload \"$WP\" >/dev/null 2>&1; " +
        "hyprctl hyprpaper wallpaper \",$WP\" >/dev/null 2>&1"

    readonly property string _persistScript:
        "WP=\"$1\"; printf 'preload = %s\\nwallpaper = ,%s\\nsplash = false\\n' \"$WP\" \"$WP\" > \"$HOME/.config/hypr/hyprpaper.conf\""

    property Process _live:        Process { running: false }
    property Process _persistProc: Process { running: false }

    property Process _list: Process {
        command: ["sh", "-c",
            "ls -1 \"$HOME\"/wallpaper/*.jpg \"$HOME\"/wallpaper/*.jpeg \"$HOME\"/wallpaper/*.png \"$HOME\"/wallpaper/*.webp 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const list = []
                for (const ln of text.trim().split("\n"))
                    if (ln.trim() !== "") list.push(ln.trim())
                root.wallpapers = list
            }
        }
    }

    Component.onCompleted: {
        refresh()
        const saved = SettingsService.get("wallpaper.path", "")
        if (saved !== "") _restore(saved)
    }
}
