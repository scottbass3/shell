import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../services"

RowLayout {
    id: root

    required property var barScreen

    spacing: 4

    property var hyprMonitor: Hyprland.monitorFor(barScreen)

    readonly property bool _hideSpecial: SettingsService.get("bar.workspaces.hideSpecial", true)
    readonly property bool _numbers:     SettingsService.get("bar.workspaces.numbers", false)
    readonly property int  _base:        hyprMonitor ? hyprMonitor.id * 10 : 0

    // Hover anywhere over the dots → open the workspace overview popout,
    // anchored to the row's horizontal centre.
    HoverHandler {
        id: _wsHover
        onHoveredChanged: {
            if (hovered) {
                const c = root.mapToItem(null, root.width / 2, 0)
                PopoutService.open("workspaces", c.x, root.barScreen)
                PopoutService.widgetHovered = true
            } else if (PopoutService.currentName === "workspaces") {
                PopoutService.widgetHovered = false
            }
        }
    }

    Repeater {
        model: Hyprland.workspaces

        delegate: Item {
            required property var modelData  // HyprlandWorkspace

            readonly property bool isActive:  modelData.active
            readonly property bool isFocused: modelData.focused
            readonly property bool isUrgent:  modelData.urgent

            // Workspaces on this monitor; special (id < 0) hidden unless opted in.
            visible: root.hyprMonitor && modelData.monitor === root.hyprMonitor
                     && (root._hideSpecial ? modelData.id >= 0 : true)
            implicitWidth:  visible ? (root._numbers ? numText.implicitWidth + 8 : dot.implicitWidth) : 0
            implicitHeight: dot.implicitHeight
            Layout.alignment: Qt.AlignVCenter

            readonly property color _accent: isUrgent ? ThemeManager.error
                : isActive ? ThemeManager.primary : ThemeManager.onSurfaceVariant

            Rectangle {
                id: dot
                visible: !root._numbers
                anchors.centerIn: parent

                readonly property int dotSize: isActive ? 10 : 7
                implicitWidth:  dotSize
                implicitHeight: dotSize
                radius: dotSize / 2
                color:  parent._accent
                opacity: isActive ? 1.0 : 0.5

                Behavior on implicitWidth  { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on implicitHeight { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color          { ColorAnimation   { duration: 120 } }
                Behavior on opacity        { NumberAnimation  { duration: 120 } }
            }

            Text {
                id: numText
                visible: root._numbers
                anchors.centerIn: parent
                text: modelData.id >= 0 ? (modelData.id - root._base) : "S"
                color: parent._accent
                opacity: isActive ? 1.0 : 0.6
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm
                font.bold: isActive
            }

            MouseArea {
                anchors.fill: parent
                // Larger hit target than the dot
                anchors.margins: -6
                onClicked: modelData.activate()
                cursorShape: Qt.PointingHandCursor
            }
        }
    }
}
