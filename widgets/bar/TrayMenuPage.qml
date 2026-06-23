import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../../theme"
import "../../services"

ColumnLayout {
    id: root

    spacing: 2

    QsMenuOpener {
        id: _opener
        menu: PopoutService.menuHandle
    }

    Repeater {
        model: _opener.children

        delegate: Item {
            id: _entry
            required property var modelData   // QsMenuEntry

            // Measure natural text width so the column can size to fit
            TextMetrics {
                id: _metrics
                font.family:    ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm
                text:           _entry.modelData.text
            }

            readonly property real _iconW: _entry.modelData.icon !== "" ? 14 + 8 : 0

            Layout.fillWidth:  true
            Layout.minimumWidth: _entry.modelData.isSeparator
                ? 0
                : 8 + _iconW + _metrics.advanceWidth + 8   // left + icon? + text + right

            implicitHeight: modelData.isSeparator ? 9 : 30

            // Separator
            Rectangle {
                visible: _entry.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.right: parent.right
                height: 1; color: ThemeManager.outlineVariant; opacity: 0.35
            }

            // Menu item
            Item {
                visible: !_entry.modelData.isSeparator
                anchors.fill: parent

                Rectangle {
                    anchors.fill: parent; radius: 6
                    color: _ema.containsMouse && _entry.modelData.enabled
                           ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g,
                                     ThemeManager.primary.b, 0.10)
                           : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    spacing: 8

                    IconImage {
                        visible:      _entry.modelData.icon !== ""
                        implicitSize: 14
                        source:       _entry.modelData.icon
                        opacity:      _entry.modelData.enabled ? 1 : 0.4
                    }

                    Text {
                        Layout.fillWidth: true
                        text:           _entry.modelData.text
                        color:          _entry.modelData.enabled
                                        ? ThemeManager.onSurface
                                        : ThemeManager.onSurfaceVariant
                        font.family:    ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                        opacity:        _entry.modelData.enabled ? 1 : 0.5
                    }
                }

                MouseArea {
                    id: _ema
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled:      _entry.modelData.enabled
                    cursorShape:  Qt.PointingHandCursor

                    onClicked: {
                        _entry.modelData.triggered()
                        PopoutService.close()
                    }
                }
            }
        }
    }
}
