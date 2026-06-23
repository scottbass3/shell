pragma Singleton
import QtQuick
import Quickshell.Io
import "."
import "../theme"

// State + keyboard navigation for the right-edge tools toolbar.
QtObject {
    id: root

    property bool open:       false   // keyboard mode (rail focused via Super+R)
    property bool wpOpen:     false   // wallpaper picker open
    property int  selected:   0       // highlighted rail button (keyboard)
    property int  wpSelected: 0       // highlighted wallpaper (keyboard)
    readonly property int count: 4    // rail buttons

    // Wallpaper preview/revert bookkeeping
    property string _origWp:    ""
    property string _origTheme: ""
    property bool   _committing: false

    // ── Launchers ──────────────────────────────────────────────────────────--
    property Process _files:  Process { command: ["kitty", "--class", "superfile", "-e", "spf"] }
    property Process _beacon: Process { command: ["kitty", "--class", "beacon", "-e", "beacon"] }

    function toggle() { if (open || wpOpen) close(); else openKbd() }
    function openKbd() { open = true; wpOpen = false; selected = 0 }
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
        else selected = (selected - 1 + count) % count
    }
    function down() {
        if (wpOpen) { const n = WallpaperService.wallpapers.length; if (n) wpSelected = (wpSelected + 1) % n }
        else selected = (selected + 1) % count
    }

    // Left / Enter → enter / activate / confirm
    function activate() {
        if (wpOpen) {
            commitWallpaper(WallpaperService.wallpapers[wpSelected])
            return
        }
        switch (selected) {
            case 0: _files.running = true;  close(); break
            case 1: ScreenRecorderService.toggle(); close(); break   // close so slurp overlay gets input
            case 2: _beacon.running = true; close(); break
            case 3: wpOpen = true; break                    // onWpOpenChanged sets up preview
        }
    }

    // Right / Escape → back out / close (reverts the live preview)
    function back() {
        if (wpOpen) { wpOpen = false; open = true }   // → onWpOpenChanged reverts
        else close()
    }
}
