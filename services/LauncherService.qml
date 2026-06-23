pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."

// Open/close state for the app launcher (Win11-style start menu).
// Opens on the currently focused monitor. MainWindow draws the launcher blob +
// content for the screen whose name matches `screenName` while `open`.
QtObject {
    id: root

    property bool   open:       false
    property string screenName: ""   // monitor the launcher should appear on
    property string query:      ""   // live search text

    function _focusedName() {
        const m = Hyprland.focusedMonitor
        return m?.name ?? ""
    }

    property string _prevWin: ""   // window focused before our layer grabbed

    function show() {
        screenName = _focusedName()
        query = ""
        // Save the window focused before our layer grabs the keyboard, so we can
        // hand focus back on close.
        _prevWin = FocusService.savePrev()
        open = true
    }
    function hide() {
        open = false
        query = ""
        _refocusTimer.restart()
    }
    function toggle() { if (open) hide(); else show() }

    // ── Keyboard focus restore (Hyprland won't auto-restore after the layer
    //    releases its exclusive keyboard grab) ──────────────────────────────--
    property Timer _refocusTimer: Timer {
        interval: 140
        onTriggered: FocusService.refocus(root._prevWin)
    }
}
