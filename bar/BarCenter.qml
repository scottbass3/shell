import QtQuick
import QtQuick.Layouts
import "../theme"
import "../widgets/bar"

RowLayout {
    id: root

    required property var barScreen

    spacing: ThemeManager.spacingLg

    Workspaces {
        barScreen: root.barScreen
        Layout.alignment: Qt.AlignVCenter
    }

    // Separator
    Rectangle {
        width: 1; height: 14
        color: ThemeManager.outlineVariant
        opacity: 0.4
        Layout.alignment: Qt.AlignVCenter
    }

    Clock {
        barScreen: root.barScreen
        Layout.alignment: Qt.AlignVCenter
    }
}
