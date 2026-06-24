pragma Singleton
import QtQuick
import Quickshell.Io
import "."
import "../theme"

// Wallpaper backend (hyprpaper) + Material You theming (matugen), plus favorites
// and a timed rotation. Lists images under ~/wallpaper and the managed downloads
// dir (~/.local/state/quickshell/wallpapers).
//   preview(path) — set live + re-theme, no persistence
//   commit(path)  — preview + persist (settings + hyprpaper.conf)
QtObject {
    id: root

    property var    wallpapers: []   // absolute file paths (local + downloaded)
    property string current:    ""

    readonly property string downloadDir: Paths.stateDir + "/wallpapers"

    // hyprpaper is the wallpaper backend; without it the whole switcher is off.
    readonly property bool available: DependencyService.available("hyprpaper")

    // Listing the files needs no backend (only applying does), so don't gate it
    // on `available` — that's resolved asynchronously and would leave an empty
    // list on the first scan.
    function refresh() { _list.running = true }

    // ── Favorites ─────────────────────────────────────────────────────────────
    readonly property var favorites: SettingsService.get("wallpaper.favorites", [])
    function isFavorite(p) { return (favorites || []).indexOf(p) >= 0 }
    function toggleFavorite(p) {
        if (!p) return
        const f = (favorites || []).slice()
        const i = f.indexOf(p)
        if (i >= 0) f.splice(i, 1); else f.push(p)
        SettingsService.set("wallpaper.favorites", f)
    }

    // ── Rotation ──────────────────────────────────────────────────────────────
    readonly property bool rotationEnabled:     SettingsService.get("wallpaper.rotation.enabled", false)
    readonly property var  rotationPaths:        SettingsService.get("wallpaper.rotation.paths", [])
    readonly property int  rotationIntervalMin:  SettingsService.get("wallpaper.rotation.intervalMin", 15)
    property int           _rotIndex:            SettingsService.get("wallpaper.rotation.index", 0)

    function setRotationEnabled(b)  { SettingsService.set("wallpaper.rotation.enabled", !!b) }
    function setRotationInterval(m) { SettingsService.set("wallpaper.rotation.intervalMin", Math.max(1, Math.round(m))) }
    function isInRotation(p) { return (rotationPaths || []).indexOf(p) >= 0 }
    function toggleRotation(p) {
        if (!p) return
        const r = (rotationPaths || []).slice()
        const i = r.indexOf(p)
        if (i >= 0) r.splice(i, 1); else r.push(p)
        SettingsService.set("wallpaper.rotation.paths", r)
    }

    // Advance to the next wallpaper in the set (always re-themes via commit).
    function advance() {
        const ps = rotationPaths
        if (!ps || ps.length === 0) return
        _rotIndex = (_rotIndex + 1) % ps.length
        SettingsService.set("wallpaper.rotation.index", _rotIndex)
        commit(ps[_rotIndex])
    }

    // Apply the current rotation entry immediately (on enable / set change).
    function _applyRotationCurrent() {
        const ps = rotationPaths
        if (!ps || ps.length === 0) return
        if (_rotIndex >= ps.length) _rotIndex = 0
        commit(ps[_rotIndex])
    }
    onRotationEnabledChanged: if (rotationEnabled) _applyRotationCurrent()

    property Timer _rotTimer: Timer {
        interval: Math.max(1, root.rotationIntervalMin) * 60000
        repeat:   true
        running:  root.rotationEnabled && (root.rotationPaths?.length ?? 0) > 1
        onTriggered: root.advance()
    }

    // ── Apply / persist ───────────────────────────────────────────────────────
    // Live apply (hyprpaper) + matugen theme; no config persistence.
    function preview(path) {
        if (!path || !available) return
        current = path
        _live.command = ["sh", "-c", _liveScript, "sh", path]
        _live.running = true
        ThemeManager.generateWallpaperTheme(path)
    }

    // Preview + persist (settings + hyprpaper.conf) so it survives a restart.
    function commit(path) {
        if (!path || !available) return
        preview(path)
        SettingsService.set("wallpaper.path", path)
        _persistProc.command = ["sh", "-c", _persistScript, "sh", path]
        _persistProc.running = true
    }

    // Re-apply the saved wallpaper image on startup WITHOUT regenerating the
    // theme — the active theme is persisted separately by ThemeManager, so
    // running matugen here would clobber a theme the user kept.
    function _restore(path) {
        if (!path || !available) return
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

    // Scan ~/wallpaper and the managed downloads dir. POSIX-sh glob with an
    // existence guard so a non-matching pattern doesn't leak the literal.
    property Process _list: Process {
        command: ["sh", "-c",
            "for d in \"$HOME/wallpaper\" \"$1\"; do " +
            "for f in \"$d\"/*.jpg \"$d\"/*.jpeg \"$d\"/*.png \"$d\"/*.webp; do " +
            "[ -e \"$f\" ] && printf '%s\\n' \"$f\"; done; done",
            "sh", root.downloadDir]
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
