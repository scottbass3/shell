import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

// Bar content only — no PanelWindow wrapper.
// MainWindow owns the window, exclusive zone, and (in frame/topbar modes) the
// blob background. In "islands" mode each section gets its own floating pill.
//
// Pill backgrounds are SIBLINGS of the sections (not parents) so deriving a
// pill's width from its section's implicitWidth isn't a parent→child binding
// loop (which QML would resolve to width 0).
Item {
    id: bar
    required property var barScreen


    readonly property bool _islands: SettingsService.get("appearance.mode", "frame") === "islands"
    readonly property int  _pad:  ThemeManager.spacing + 4
    readonly property int  _edge: ThemeManager.spacingLg

    // ── Pill backgrounds (behind the sections) ────────────────────────────────
    Rectangle {
        visible: bar._islands
        anchors { left: parent.left; leftMargin: bar._edge; verticalCenter: parent.verticalCenter }
        height: ThemeManager.barHeight
        width:  leftSection.implicitWidth + bar._pad * 2
        radius: ThemeManager.barRadius
        color:  ThemeManager.surfaceContainerHigh
        border.width: 1; border.color: ThemeManager.outlineVariant
    }
    Rectangle {
        visible: bar._islands
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
        height: ThemeManager.barHeight
        width:  centerSection.implicitWidth + bar._pad * 2
        radius: ThemeManager.barRadius
        color:  ThemeManager.surfaceContainerHigh
        border.width: 1; border.color: ThemeManager.outlineVariant
    }
    Rectangle {
        visible: bar._islands
        anchors { right: parent.right; rightMargin: bar._edge; verticalCenter: parent.verticalCenter }
        height: ThemeManager.barHeight
        width:  rightSection.implicitWidth + bar._pad * 2
        radius: ThemeManager.barRadius
        color:  ThemeManager.surfaceContainerHigh
        border.width: 1; border.color: ThemeManager.outlineVariant
    }

    // ── Sections (on top of the pills) ────────────────────────────────────────
    BarLeft {
        id: leftSection
        barScreen: bar.barScreen
        anchors { left: parent.left; leftMargin: bar._edge + (bar._islands ? bar._pad : 0); verticalCenter: parent.verticalCenter }
    }
    BarCenter {
        id: centerSection
        barScreen: bar.barScreen
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
    }
    BarRight {
        id: rightSection
        barScreen: bar.barScreen
        anchors { right: parent.right; rightMargin: bar._edge + (bar._islands ? bar._pad : 0); verticalCenter: parent.verticalCenter }
    }
}
