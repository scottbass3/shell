import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../../theme"

Item {
    id: root

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

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (adapter) adapter.enabled = !adapter.enabled
        }
    }
}
