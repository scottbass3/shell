import QtQuick
import Quickshell.Widgets
import "../../theme"

// An app icon from AppService.iconFor / iconForClass, or a generic glyph when
// the app has none (instead of Qt's missing-texture checkerboard).
Item {
    id: root
    property string source: ""
    property real implicitSize: 32
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    IconImage {
        anchors.fill: parent
        source: root.source
        visible: root.source !== ""
    }
    Text {
        anchors.centerIn: parent
        visible: root.source === ""
        text: "󰣆"
        color: ThemeManager.onSurfaceVariant
        font.family: ThemeManager.fontFamily
        font.pixelSize: root.implicitSize * 0.8
    }
}
