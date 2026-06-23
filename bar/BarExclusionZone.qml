import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"

// Invisible PanelWindow whose sole job is claiming the exclusive zone so
// Hyprland pushes app windows below the bar. Visual rendering is in MainWindow.
PanelWindow {
    id: root
    required property var modelData

    screen:        modelData
    anchors        { top: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: ThemeManager.barHeight
    implicitHeight: ThemeManager.barHeight
    color:         "transparent"
    mask:          Region {}   // no input — MainWindow's bar handles clicks
}
