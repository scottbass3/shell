import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

RowLayout {
    id: root
    spacing: 6

    property var now: new Date()
    property var barScreen: null

    Timer {
        interval: 1000
        running:  true
        repeat:   true
        onTriggered: root.now = new Date()
    }

    HoverHandler {
        onHoveredChanged: {
            const pos = root.mapToItem(null, root.width / 2, 0)
            if (hovered) {
                PopoutService.open("dashboard", pos.x, root.barScreen)
                PopoutService.widgetHovered = true
            } else {
                PopoutService.widgetHovered = false
            }
        }
    }

    readonly property string _timeFmt: {
        const h24  = SettingsService.get("bar.clock.use24h", true)
        const secs = SettingsService.get("bar.clock.seconds", false)
        return (h24 ? "hh:mm" : "h:mm") + (secs ? ":ss" : "") + (h24 ? "" : " AP")
    }

    Text {
        id: timeText
        text: Qt.formatTime(root.now, root._timeFmt)
        color: ThemeManager.onSurface
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeMd
        font.weight: Font.Medium
    }

    Rectangle {
        width: 1; height: 12
        color: ThemeManager.outlineVariant
        opacity: 0.6
        Layout.alignment: Qt.AlignVCenter
    }

    Text {
        id: dateText
        text: Qt.formatDate(parent.now, "ddd d MMM")
        color: ThemeManager.onSurface
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeSm
        font.weight: Font.Medium
    }
}
