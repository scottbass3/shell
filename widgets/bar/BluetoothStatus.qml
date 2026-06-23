import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../../theme"
import "../../services"

Item {
    id: root

    property var barScreen: null

    implicitWidth:  _row.implicitWidth
    implicitHeight: _row.implicitHeight

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.enabled ?? false

    property var connectedDevice: null

    Repeater {
        model: Bluetooth.devices
        delegate: Item {
            required property var modelData
            Component.onCompleted: {
                if (modelData.connected && root.connectedDevice === null)
                    root.connectedDevice = modelData
            }
        }
    }

    RowLayout {
        id: _row
        anchors.fill: parent
        spacing: 4

        Text {
            text: enabled ? (root.connectedDevice ? "󰂱" : "󰂯") : "󰂲"
            color: root.connectedDevice
                ? ThemeManager.primary
                : enabled
                    ? ThemeManager.onSurface
                    : ThemeManager.onSurfaceVariant
            opacity: enabled ? 1.0 : 0.5
            font.family: ThemeManager.fontFamily
            font.pixelSize: 15
            Layout.alignment: Qt.AlignVCenter

            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    HoverHandler {
        onHoveredChanged: {
            const pos = root.mapToItem(null, root.width / 2, 0)
            if (hovered) {
                PopoutService.open("bluetooth", pos.x, root.barScreen)
                PopoutService.widgetHovered = true
            } else {
                PopoutService.widgetHovered = false
            }
        }
    }
}
