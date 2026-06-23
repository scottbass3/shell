import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../theme"

Item {
    id: root

    implicitWidth:  190
    implicitHeight: _col.implicitHeight + ThemeManager.spacingLg * 2

    readonly property int _current: PowerProfiles.profile

    ColumnLayout {
        id: _col
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            margins: ThemeManager.spacingLg
        }
        spacing: 2

        Text {
            text:           "Power profile"
            color:          ThemeManager.onSurfaceVariant
            font.family:    ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            font.weight:    Font.Medium
            Layout.bottomMargin: 4
        }

        ProfileAction {
            icon:    "󰾆"; label: "Power Saver"
            profile: PowerProfile.PowerSaver
        }
        ProfileAction {
            icon:    "󰾅"; label: "Balanced"
            profile: PowerProfile.Balanced
        }
        ProfileAction {
            icon:    "󰓅"; label: "Performance"
            profile: PowerProfile.Performance
            // Hidden when firmware/daemon offers no performance profile
            visible: PowerProfiles.hasPerformanceProfile
        }
    }

    // ── M3 selectable profile row ───────────────────────────────────────────
    component ProfileAction: Item {
        id: pa

        property string icon:    ""
        property string label:   ""
        property int    profile: -1

        readonly property bool active: root._current === pa.profile

        Layout.fillWidth: true
        implicitHeight:   34
        visible:          true

        Rectangle {
            anchors.fill: parent; radius: 8
            color: pa.active
                ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g,
                          ThemeManager.primary.b, _hoverMa.containsMouse ? 0.20 : 0.13)
                : (_hoverMa.containsMouse
                   ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g,
                             ThemeManager.onSurface.b, 0.08)
                   : "transparent")
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 10

            Text {
                text:             pa.icon
                color:            pa.active ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                font.family:      ThemeManager.fontFamily
                font.pixelSize:   16
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 100 } }
            }

            Text {
                text:             pa.label
                color:            pa.active ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                font.family:      ThemeManager.fontFamily
                font.pixelSize:   ThemeManager.fontSizeSm
                font.weight:      Font.Medium
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 100 } }
            }

            // Active check mark
            Text {
                visible:          pa.active
                text:             "󰄬"
                color:            ThemeManager.primary
                font.family:      ThemeManager.fontFamily
                font.pixelSize:   13
                Layout.alignment: Qt.AlignVCenter
            }
        }

        MouseArea {
            id: _hoverMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked:    PowerProfiles.profile = pa.profile
        }
    }
}
