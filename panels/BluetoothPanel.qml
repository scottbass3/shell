import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../theme"
import "../services"

// In-shell Bluetooth manager (replaces blueman-manager). Adapter toggle + scan;
// left-click a device to connect/disconnect, right-click for the context menu
// (trust, rename, forget, audio profile). Menu lives in ContextMenu.qml.
Item {
    id: root

    implicitWidth:  280
    implicitHeight: Math.min(_col.implicitHeight + 16, 460)

    readonly property var  adapter:   Bluetooth.defaultAdapter
    readonly property bool btEnabled: adapter?.enabled ?? false

    readonly property bool active: PopoutService.currentName === "bluetooth"
    onActiveChanged: if (!active && adapter) adapter.discovering = false

    Flickable {
        id: _flick
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        contentWidth:  width
        contentHeight: _col.implicitHeight
        interactive:   contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: _col
            width: _flick.width
            spacing: 4

            // ── Header: title + scan + power ──────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Bluetooth"
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
                    Layout.fillWidth: true
                }
                Rectangle {
                    id: _scanBtn
                    visible: root.btEnabled
                    implicitWidth: 24; implicitHeight: 20; radius: ThemeManager.chipRadius
                    readonly property bool _on: root.adapter?.discovering ?? false
                    color: _on ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.2)
                               : (_scanMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                    Text {
                        anchors.centerIn: parent
                        text: "󰜉"
                        color: _scanBtn._on ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily; font.pixelSize: 13
                        RotationAnimation on rotation {
                            running: _scanBtn._on; from: 0; to: 360; duration: 1400; loops: Animation.Infinite
                        }
                    }
                    MouseArea {
                        id: _scanMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.adapter) root.adapter.discovering = !root.adapter.discovering
                    }
                }
                Rectangle {
                    width: 36; height: 20; radius: 10
                    color: root.btEnabled ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2; x: root.btEnabled ? 18 : 2
                        color: root.btEnabled ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { const a = root.adapter; if (a) a.enabled = !a.enabled }
                    }
                }
            }

            Text {
                visible: !root.btEnabled
                text: "Adapter off"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
                Layout.topMargin: 4
            }

            // ── Devices ───────────────────────────────────────────────────────
            Repeater {
                model: root.btEnabled ? (Bluetooth.devices?.values ?? []) : []
                delegate: Rectangle {
                    id: _devRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: ThemeManager.chipRadius
                    color: modelData.connected
                        ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.13)
                        : (_devMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                    Behavior on color { ColorAnimation { duration: 100 } }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        spacing: 8
                        Text {
                            text: _devRow.modelData.connected ? "󰂱" : "󰂯"
                            color: _devRow.modelData.connected ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: 14
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (_devRow.modelData.name && _devRow.modelData.name !== "")
                                  ? _devRow.modelData.name
                                  : (_devRow.modelData.deviceName || ("" + _devRow.modelData.address))
                            color: _devRow.modelData.connected ? ThemeManager.primary : ThemeManager.onSurface
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: _devRow.modelData.connected && (_devRow.modelData.batteryAvailable ?? false)
                            text: Math.round((_devRow.modelData.battery ?? 0) * 100) + "%"
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: 10
                        }
                        Text {
                            visible: !_devRow.modelData.connected && _devRow.modelData.paired
                            text: "Paired"
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: 10
                        }
                    }
                    MouseArea {
                        id: _devMa; anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        // Left = connect/disconnect, right = context menu.
                        onClicked: (m) => {
                            const d = _devRow.modelData
                            if (m.button === Qt.RightButton) {
                                const p = mapToItem(null, m.x, m.y)
                                ContextMenuService.show("bt", d, p.x, p.y, PopoutService.anchorScreen)
                            } else {
                                d.connected ? d.disconnect() : d.connect()
                                ContextMenuService.close()
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.btEnabled && (Bluetooth.devices?.values?.length ?? 0) > 0
                Layout.topMargin: 4
                text: "Left-click to connect · right-click for options"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: 9
                opacity: 0.5
            }
        }
    }
}
