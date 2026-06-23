import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"
import "../widgets/bar"

RowLayout {
    id: root

    required property var barScreen

    spacing: 6

    // Status row (network/bt/mic/audio/battery) is an opt-in group.
    readonly property bool _showStatus: SettingsService.get("bar.widgets.status", true)

    // ── Tray ──────────────────────────────────────────────────────────────
    Tray {
        barScreen:        root.barScreen   // hide list + special-ws map come from Settings → Tray
        Layout.alignment: Qt.AlignVCenter
    }

    BarSeparator { visible: root._showStatus; Layout.alignment: Qt.AlignVCenter }

    // ── Status group (opt-in) ─────────────────────────────────────────────
    NetworkStatus   { visible: root._showStatus; Layout.alignment: Qt.AlignVCenter }
    BarSeparator    { visible: root._showStatus; Layout.alignment: Qt.AlignVCenter }
    BluetoothStatus { visible: root._showStatus; Layout.alignment: Qt.AlignVCenter }
    BarSeparator    { visible: root._showStatus; Layout.alignment: Qt.AlignVCenter }
    Microphone      { visible: root._showStatus; barScreen: root.barScreen; Layout.alignment: Qt.AlignVCenter }
    Audio           { visible: root._showStatus; barScreen: root.barScreen; Layout.alignment: Qt.AlignVCenter }
    BarSeparator    { visible: root._showStatus; Layout.alignment: Qt.AlignVCenter }
    Battery         { visible: root._showStatus; barScreen: root.barScreen; Layout.alignment: Qt.AlignVCenter }

    BarSeparator { Layout.alignment: Qt.AlignVCenter }

    // ── Notifications ─────────────────────────────────────────────────────
    NotifButton {
        barScreen: root.barScreen
        Layout.alignment: Qt.AlignVCenter
    }

    BarSeparator { Layout.alignment: Qt.AlignVCenter }

    // ── Power ─────────────────────────────────────────────────────────────
    PowerButton {
        barScreen:        root.barScreen
        Layout.alignment: Qt.AlignVCenter
    }
}
