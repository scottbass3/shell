import QtQuick
import "../../theme"
import "../../services"

Item {
    id: root

    implicitWidth:  24
    implicitHeight: 24

    property var barScreen: null

    Text {
        anchors.centerIn: parent
        text:           "󰐥"
        color:          _hoverMa.containsMouse
                        ? ThemeManager.error
                        : ThemeManager.onSurfaceVariant
        font.family:    ThemeManager.fontFamily
        font.pixelSize: 15
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    HoverHandler {
        onHoveredChanged: {
            const pos = root.mapToItem(null, root.width / 2, 0)
            if (hovered) {
                PopoutService.open("power", pos.x, root.barScreen)
                PopoutService.widgetHovered = true
            } else {
                PopoutService.widgetHovered = false
            }
        }
    }

    // Invisible MouseArea just for cursor shape + containsMouse
    MouseArea {
        id: _hoverMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
    }
}
