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

    // Keyboard + automatic focus restore are handled by MainWindow's
    // HyprlandFocusGrab while the launcher is open.
    function show() {
        screenName = _focusedName()
        query = ""
        open = true
    }
    function hide() {
        open = false
        query = ""
    }
    function toggle() { if (open) hide(); else show() }
}
