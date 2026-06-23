import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../theme"
import "../services"
import "../widgets/bar"

Item {
    id: root

    readonly property int _pad: ThemeManager.spacing

    // Width = widest item (from TextMetrics via Layout.minimumWidth), capped 140–400
    implicitWidth:  Math.max(140, Math.min(_page.implicitWidth + _pad * 2, 400))
    implicitHeight: _page.implicitHeight + _pad * 2

    TrayMenuPage {
        id: _page
        // Explicit width (not anchors.fill) so implicitWidth stays content-driven
        width:  root.implicitWidth - root._pad * 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top:              parent.top
        anchors.topMargin:        root._pad
    }
}
