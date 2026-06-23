import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

Item {
    id: root

    implicitWidth:  _row.implicitWidth
    implicitHeight: _row.implicitHeight

    property var barScreen: null

    readonly property bool muted: AudioService.sourceMuted

    RowLayout {
        id: _row
        anchors.fill: parent
        spacing: 4

        Text {
            text:           root.muted ? "󰍭" : "󰍬"
            color:          root.muted ? ThemeManager.error : ThemeManager.onSurface
            font.family:    ThemeManager.fontFamily
            font.pixelSize: 15
            Layout.alignment: Qt.AlignVCenter

            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    HoverHandler {
        onHoveredChanged: {
            const pos = root.mapToItem(null, root.width / 2, 0)
            if (hovered) {
                PopoutService.open("audio", pos.x, root.barScreen)
                PopoutService.widgetHovered = true
            } else {
                PopoutService.widgetHovered = false
            }
        }
    }

    MouseArea {
        anchors.fill:    parent
        acceptedButtons: Qt.NoButton

        onWheel: (ev) => {
            const delta = ev.angleDelta.y > 0 ? 0.05 : -0.05
            AudioService.adjustSourceVolume(delta)
        }
    }
}
