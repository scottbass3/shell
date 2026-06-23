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

    function show() {
        screenName = _focusedName()
        _savePrev.running = false
        _savePrev.running = true
        open = true
    }
    function hide() { open = false; _refocusTimer.restart() }
    function toggle() { if (open) hide(); else show() }

    property Process _savePrev: Process {
        command: ["sh", "-c",
            "hyprctl activewindow -j | jq -r '.address // empty' > /tmp/qs-settings-prevwin"]
    }
    property Process _refocus: Process {
        command: [Paths.script("refocus-prev.sh"), "/tmp/qs-settings-prevwin"]
    }
    property Timer _refocusTimer: Timer {
        interval: 140
        onTriggered: { root._refocus.running = false; root._refocus.running = true }
    }
}
