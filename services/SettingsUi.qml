pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."

// Open/close state for the Settings window (centered modal). Opens on the
// focused monitor; restores keyboard focus on close (shared bounce script).
QtObject {
    id: root

    property bool   open:       false
    property string screenName: ""
    property string category:   "appearance"   // selected settings category

    function _focusedName() { return Hyprland.focusedMonitor?.name ?? "" }

    property string _prevWin: ""

    function show() {
        screenName = _focusedName()
        _prevWin = FocusService.savePrev()
        open = true
    }
    function hide() { open = false; _refocusTimer.restart() }
    function toggle() { if (open) hide(); else show() }

    property Timer _refocusTimer: Timer {
        interval: 140
        onTriggered: FocusService.refocus(root._prevWin)
    }
}
