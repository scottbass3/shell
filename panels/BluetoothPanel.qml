import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Bluetooth
import "../theme"
import "../services"

// Bar hover popout for Bluetooth — same controls as the dashboard quick
// settings (toggle adapter, connect/disconnect/pair devices, open manager).
Item {
    id: root

    implicitWidth:  250
    implicitHeight: Math.min(_col.implicitHeight + 16, 400)

    property Process _blueman: Process { command: ["blueman-manager"] }
    function _launch(proc) { proc.running = true; PopoutService.close() }

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

            MenuHeader {
                title: "Bluetooth"
                on: Bluetooth.defaultAdapter?.enabled ?? false
                onToggled: { const a = Bluetooth.defaultAdapter; if (a) a.enabled = !a.enabled }
            }

            Text {
                visible: !(Bluetooth.defaultAdapter?.enabled ?? false)
                text: "Adapter off"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
                Layout.topMargin: 4
            }

            Repeater {
                model: (Bluetooth.defaultAdapter?.enabled ?? false) ? (Bluetooth.devices?.values ?? []) : []
                delegate: MenuRow {
                    required property var modelData
                    text:     (modelData.deviceName && modelData.deviceName !== "")
                              ? modelData.deviceName : modelData.address
                    icon:     modelData.connected ? "󰂱" : "󰂯"
                    active:   modelData.connected
                    trailing: modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                }
            }

            MenuFooter { text: "Open blueman-manager"; onClicked: root._launch(root._blueman) }
        }
    }

    // ── Shared submenu pieces (mirrors Dashboard quick settings) ───────────────
    component MenuHeader: RowLayout {
        id: mh
        property string title: ""
        property bool   on:    false
        signal toggled()
        Layout.fillWidth: true
        Text {
            text: mh.title
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
            Layout.fillWidth: true
        }
        Rectangle {
            width: 36; height: 20; radius: 10
            color: mh.on ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 16; height: 16; radius: 8
                y: 2; x: mh.on ? 18 : 2
                color: mh.on ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mh.toggled() }
        }
    }

    component MenuRow: Rectangle {
        id: mr
        property string text:     ""
        property string icon:     ""
        property string trailing: ""
        property bool   active:   false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 32
        radius: ThemeManager.chipRadius
        color: active
            ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, _mrMa.containsMouse ? 0.22 : 0.13)
            : (_mrMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 8
            Text {
                text: mr.icon
                color: mr.active ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: 14
            }
            Text {
                text: mr.text
                color: mr.active ? ThemeManager.primary : ThemeManager.onSurface
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: mr.trailing !== ""
                text: mr.trailing
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: 10
            }
        }
        MouseArea {
            id: _mrMa; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: mr.clicked()
        }
    }

    component MenuFooter: Rectangle {
        id: mf
        property string text: ""
        signal clicked()
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: 30
        radius: ThemeManager.chipRadius
        color: _mfMa.containsMouse ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.14) : ThemeManager.surfaceContainer
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 6
            Text {
                text: "󰏌"
                color: ThemeManager.primary
                font.family: ThemeManager.fontFamily; font.pixelSize: 13
            }
            Text {
                text: mf.text
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                Layout.fillWidth: true
            }
        }
        MouseArea {
            id: _mfMa; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: mf.clicked()
        }
    }
}
