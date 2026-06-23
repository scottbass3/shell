import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../theme"

RowLayout {
    spacing: ThemeManager.spacing

    readonly property var toplevel: Hyprland.activeToplevel
    readonly property string title: toplevel ? toplevel.title : ""

    // App class for icon lookup later (from raw IPC data)
    readonly property string appClass: toplevel && toplevel.lastIpcObject
        ? (toplevel.lastIpcObject["class"] ?? "")
        : ""

    visible: title !== ""

    // Class label (compact, muted)
    Text {
        visible: appClass !== ""
        text: appClass
        color: ThemeManager.primary
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeSm
        font.weight: Font.Medium
        Layout.alignment: Qt.AlignVCenter
    }

    // Separator dot
    Rectangle {
        visible: appClass !== ""
        width: 3; height: 3; radius: 2
        color: ThemeManager.outlineVariant
        Layout.alignment: Qt.AlignVCenter
    }

    // Window title (truncated)
    Text {
        text: title
        color: ThemeManager.onSurface
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeSm
        font.weight: Font.Medium
        elide: Text.ElideRight
        maximumLineCount: 1
        Layout.maximumWidth: 280
        Layout.alignment: Qt.AlignVCenter
    }
}
