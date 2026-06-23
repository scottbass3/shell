import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

Item {
    id: root

    implicitWidth:  _row.implicitWidth
    implicitHeight: _row.implicitHeight

    property var barScreen: null

    readonly property real volume: AudioService.sinkVolume
    readonly property bool muted:  AudioService.sinkMuted
    readonly property int  volPct: AudioService.sinkVolPct

    RowLayout {
        id: _row
        anchors.fill: parent
        spacing: 4

        Text {
            text: {
                if (root.muted || root.volPct === 0) return "󰝟"
                if (root.volPct < 33)                return "󰕿"
                if (root.volPct < 66)                return "󰖀"
                return "󰕾"
            }
            color:          root.muted ? ThemeManager.onSurfaceVariant : ThemeManager.onSurface
            font.family:    ThemeManager.fontFamily
            font.pixelSize: 15
            opacity:        root.muted ? 0.5 : 1.0
            Layout.alignment: Qt.AlignVCenter

            Behavior on color   { ColorAnimation  { duration: 100 } }
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }

        Text {
            text:           root.muted ? "—" : root.volPct + "%"
            color:          ThemeManager.onSurface
            font.family:    ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            font.weight:    Font.Medium
            Layout.alignment: Qt.AlignVCenter
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
            AudioService.adjustSinkVolume(delta)
        }
    }
}
