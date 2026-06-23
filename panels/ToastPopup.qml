import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: root

    required property var modelData

    screen:        modelData
    anchors        { bottom: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color:         "transparent"

    implicitWidth:  320
    implicitHeight: _column.implicitHeight + ThemeManager.spacing * 2

    // Only primary screen shows toasts (or whichever screen the center belongs to)
    // Show on all screens — each fires the same signal, so guard with a flag
    // We use the first screen (index 0 in Quickshell.screens) as toast screen.
    readonly property bool _isToastScreen: {
        const screens = Quickshell.screens
        return screens.length === 0 || screens[0]?.name === root.modelData?.name
    }

    property var _toasts: []

    Component.onCompleted: {
        NotificationService.toastRequested.connect(_onToast)
    }

    function _onToast(notif) {
        if (!root._isToastScreen) return
        const entry = { notif: notif, id: notif.id }
        const updated = root._toasts.concat([entry])
        root._toasts = updated
        _expireTimer.createObject(root, {
            interval: Math.max(3000, notif.expireTimeout > 0 ? notif.expireTimeout : 5000),
            _notifId: notif.id
        }).start()
    }

    function _removeToast(notifId) {
        root._toasts = root._toasts.filter(t => t.id !== notifId)
    }

    Component {
        id: _expireTimer
        Timer {
            property int _notifId: -1
            repeat: false
            onTriggered: { root._removeToast(_notifId); destroy() }
        }
    }

    // Input region: only the toast stack
    mask: Region {
        x: 0; y: 0
        width:  root._toasts.length > 0 ? root.width  : 0
        height: root._toasts.length > 0 ? root.height : 0
    }

    Column {
        id: _column
        anchors {
            bottom: parent.bottom
            left: parent.left; right: parent.right
            margins: ThemeManager.spacing
        }
        spacing: ThemeManager.spacing

        Repeater {
            model: root._toasts

            delegate: Rectangle {
                required property var modelData
                readonly property var notif: modelData.notif

                width: _column.width
                height: _toastContent.implicitHeight + ThemeManager.spacingLg
                radius: ThemeManager.chipRadius
                color: ThemeManager.surfaceContainerHigh

                ColumnLayout {
                    id: _toastContent
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        margins: ThemeManager.spacing
                    }
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "󰭹"
                            color: ThemeManager.primary
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: notif?.appName || ""
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: "󰅖"
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: 13
                            opacity: _closeArea.containsMouse ? 1.0 : 0.5
                            Layout.alignment: Qt.AlignVCenter

                            MouseArea {
                                id: _closeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root._removeToast(modelData.id)
                            }
                        }
                    }

                    Text {
                        visible: (notif?.summary || "").length > 0
                        text: notif?.summary || ""
                        color: ThemeManager.onSurface
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                        font.weight: Font.Medium
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: (notif?.body || "").length > 0
                        text: notif?.body || ""
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: {
                        root._removeToast(modelData.id)
                        NotificationService.openCenter(root.modelData)
                    }
                }
            }
        }
    }
}
