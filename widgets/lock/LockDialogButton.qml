import QtQuick
import "../../theme"

// A dialog button of the lock screen; `strong` is the confirming one.
Rectangle {
    id: db
    property string label: ""
    property bool strong: false
    signal clicked()
    implicitWidth: _dbText.implicitWidth + 32
    implicitHeight: 38
    radius: 19
    color: strong ? (_dbMouse.containsMouse ? Qt.lighter(ThemeManager.primary, 1.1) : ThemeManager.primary)
         : (_dbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
    border.width: strong ? 0 : 1
    border.color: ThemeManager.outlineVariant
    Text {
        id: _dbText
        anchors.centerIn: parent
        text: db.label
        color: db.strong ? ThemeManager.onPrimary : ThemeManager.onSurface
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeSm
        font.weight: Font.Medium
    }
    MouseArea {
        id: _dbMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: db.clicked()
    }
}
