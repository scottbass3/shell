import QtQuick
import QtQuick.Controls
import "../../theme"

// A translucent pill over the wallpaper: an icon, optionally a label.
Rectangle {
    id: pill
    property string icon: ""
    property string label: ""
    property string tip: ""
    signal clicked()
    implicitWidth: label !== "" ? _pillRow.implicitWidth + 28 : 44
    implicitHeight: 44
    radius: height / 2
    color: _pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
    Row {
        id: _pillRow
        anchors.centerIn: parent
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.icon
            color: "white"
            font.family: ThemeManager.fontFamily
            font.pixelSize: 18
        }
        Text {
            visible: pill.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            color: "white"
            font.family: ThemeManager.fontFamily
            font.pixelSize: 14
        }
    }
    MouseArea {
        id: _pillMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
    ToolTip.visible: _pillMouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 500
}
