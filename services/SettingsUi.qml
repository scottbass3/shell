pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."

// Open/close state for the Settings window (centered modal). Opens on the
// focused monitor. Keyboard + focus restore are handled by the window's
// HyprlandFocusGrab (see Settings.qml).
QtObject {
    id: root

    property bool   open:       false
    property string screenName: ""
    property string category:   "appearance"   // selected settings category

    function _focusedName() { return Hyprland.focusedMonitor?.name ?? "" }

    function show() { screenName = _focusedName(); open = true }
    function hide() { open = false }
    function toggle() { if (open) hide(); else show() }
}
