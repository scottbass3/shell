import QtQuick
import "../../theme"
import "../../services"

Item {
    id: root

    required property var barScreen

    implicitWidth:  _icon.implicitWidth + (badge.visible ? 4 : 0)
    implicitHeight: _icon.implicitHeight

    readonly property bool _thisScreenOpen:
        PopoutService.hasCurrent && PopoutService.currentName === "notif" &&
        PopoutService.anchorScreen?.name === root.barScreen?.name

    Text {
        id: _icon
        text: NotificationService.doNotDisturb ? "󰂛" : "󰂚"
        color: root._thisScreenOpen ? ThemeManager.primary : ThemeManager.onSurface
        font.family: ThemeManager.fontFamily
        font.pixelSize: 15
        anchors.verticalCenter: parent.verticalCenter

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Rectangle {
        id: badge
        visible: NotificationService.unreadCount > 0 && !NotificationService.doNotDisturb
        width:  Math.max(14, _badgeText.implicitWidth + 4)
        height: 14
        radius: 7
        color: ThemeManager.error
        anchors { top: _icon.top; right: parent.right; topMargin: -3; rightMargin: -4 }

        Text {
            id: _badgeText
            text: NotificationService.unreadCount > 99 ? "99+" : NotificationService.unreadCount
            color: ThemeManager.onError
            font.family: ThemeManager.fontFamily
            font.pixelSize: 8
            font.weight: Font.Bold
            anchors.centerIn: parent
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const pos = root.mapToItem(null, root.width / 2, 0)
            NotificationService.markRead()
            PopoutService.togglePin("notif", pos.x, root.barScreen)
        }
    }

    HoverHandler {
        onHoveredChanged: {
            const pos = root.mapToItem(null, root.width / 2, 0)
            if (hovered) {
                PopoutService.open("notif", pos.x, root.barScreen)
                PopoutService.widgetHovered = true
            } else {
                PopoutService.widgetHovered = false
            }
        }
    }
}
