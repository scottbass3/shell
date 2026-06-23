pragma Singleton
import QtQuick
import Quickshell
import "."
import "../theme"

// State + keyboard navigation for the right-edge tools toolbar.
// The rail is user-defined custom tools (tools.custom = [{name, icon, command}])
// followed by the built-in wallpaper/background picker. Selection 0..N-1 are the
// custom tools; index `wpIndex` (== custom count) is the wallpaper button.
QtObject {
    id: root

    property bool open:       false   // keyboard mode (rail focused via Super+R)
    property bool wpOpen:     false   // wallpaper picker open
    property int  selected:   0       // highlighted rail button (keyboard)
    property int  wpSelected: 0       // highlighted wallpaper (keyboard)

    // User tools + the built-in wallpaper button.
    readonly property var  customTools: SettingsService.get("tools.custom", [])
    readonly property bool wpEnabled:   SettingsService.get("tools.wallpaper", true)
                                        && DependencyService.available("matugen")
    readonly property int  wpIndex: customTools.length
    readonly property int  count:   customTools.length + (wpEnabled ? 1 : 0)

    function _launch(cmd) {
        if (cmd && ("" + cmd).trim() !== "") Quickshell.execDetached(["sh", "-c", "" + cmd])
    }

    // Wallpaper preview/revert bookkeeping
    property string _origWp:    ""
    property string _origTheme: ""
    property bool   _committing: false

    property string _prevWin: ""   // window focused before the rail grabbed keys

    function toggle() { if (open || wpOpen) close(); else openKbd() }
    function openKbd() { _prevWin = FocusService.savePrev(); open = true; wpOpen = false; selected = 0 }
    function close()   { open = false; wpOpen = false }

    // ── Wallpaper preview lifecycle ───────────────────────────────────────────
    onWpOpenChanged: {
        if (wpOpen) {
            _origWp     = WallpaperService.current
            _origTheme  = ThemeManager.activeId
            _committing = false
            const i = WallpaperService.wallpapers.indexOf(WallpaperService.current)
            wpSelected = i >= 0 ? i : 0
            _previewTimer.restart()
        } else if (!_committing) {
            _revert()
        }
    }
    onWpSelectedChanged: if (wpOpen) _previewTimer.restart()

    property Timer _previewTimer: Timer {
        interval: 350   // debounce so fast arrowing doesn't spam matugen
        onTriggered: {
            const w = WallpaperService.wallpapers[root.wpSelected]
            if (w && w !== WallpaperService.current) WallpaperService.preview(w)
        }
    }

    function _revert() {
        if (_origWp !== "") WallpaperService.preview(_origWp)
        if (_origTheme !== "") ThemeManager.setTheme(_origTheme)
    }

    function commitWallpaper(path) {
        _committing = true
        WallpaperService.commit(path)
        close()
    }

    // Up / Down move the selection (rail, or wallpaper list when picker open)
    function up() {
        if (wpOpen) { const n = WallpaperService.wallpapers.length; if (n) wpSelected = (wpSelected - 1 + n) % n }
        else if (count > 0) selected = (selected - 1 + count) % count
    }
    function down() {
        if (wpOpen) { const n = WallpaperService.wallpapers.length; if (n) wpSelected = (wpSelected + 1) % n }
        else if (count > 0) selected = (selected + 1) % count
    }

    // Left / Enter → enter / activate / confirm
    function activate() {
        if (wpOpen) {
            commitWallpaper(WallpaperService.wallpapers[wpSelected])
            return
        }
        if (selected < customTools.length) {
            _launch(customTools[selected].command)
            close()
        } else if (wpEnabled && selected === wpIndex) {
            wpOpen = true                                   // onWpOpenChanged sets up preview
        }
    }

    // Right / Escape → back out / close (reverts the live preview)
    function back() {
        if (wpOpen) { wpOpen = false; open = true }   // → onWpOpenChanged reverts
        else close()
    }
}
