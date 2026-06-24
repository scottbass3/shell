import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Networking
import "../theme"
import "../services"

// Bar hover popout for Wi-Fi + VPN. Wi-Fi is driven natively by
// Quickshell.Networking (reactive — no nmcli). VPN connections aren't exposed by
// that module, so the VPN section uses nmcli and only appears when nmcli is
// installed (soft dependency). The network-settings GUI button likewise shows
// only when nm-connection-editor is present.
Item {
    id: root

    implicitWidth:  260
    implicitHeight: Math.min(_col.implicitHeight + 16, 400)

    readonly property bool active: PopoutService.currentName === "network"
    onActiveChanged: if (active && _vpnAvailable) _vpnScan.running = true

    // ── Wi-Fi (Quickshell.Networking, reactive) ──────────────────────────────
    readonly property bool wifiEnabled: Networking.wifiEnabled

    // First wifi device — drives the network list and the AP scanner.
    readonly property var _wifiDev: {
        const ds = Networking.devices?.values ?? []
        for (const d of ds) if (d && d.type === DeviceType.Wifi) return d
        return null
    }

    // Run the AP scanner only while the panel is open (keeps the list fresh
    // without polling the radio constantly when idle).
    Binding {
        target: root._wifiDev
        property: "scannerEnabled"
        value: root.active
        when: root._wifiDev !== null
    }

    // Connected first, then by signal. WifiNetwork.name is the SSID,
    // signalStrength is a 0..1 fraction.
    readonly property var wifiNetworks: {
        const dev = root._wifiDev
        if (!dev || !root.wifiEnabled) return []
        const ns = (dev.networks?.values ?? []).filter(n => n && n.name && n.name !== "")
        ns.sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
        return ns
    }

    function _toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled }

    // ── VPN (nmcli — soft dependency) ─────────────────────────────────────────
    readonly property bool _vpnAvailable: DependencyService.available("nmcli")
    property var vpnList: []   // [{ name, active }]

    property Process _nmAction: Process { running: false }
    function _nm(args) {
        _nmAction.command = args
        _nmAction.running = true
        _vpnRescan.restart()
    }
    property Timer _vpnRescan: Timer {
        interval: 1500; repeat: false
        onTriggered: if (root._vpnAvailable) root._vpnScan.running = true
    }
    property Process _vpnScan: Process {
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE,STATE connection show 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = []
                for (const ln of text.trim().split("\n")) {
                    if (!ln) continue
                    const f = ln.split(":")
                    const type = f[1] ?? ""
                    if (type.indexOf("vpn") < 0 && type.indexOf("wireguard") < 0) continue
                    rows.push({ name: f[0], active: (f[2] ?? "").indexOf("activated") >= 0 })
                }
                root.vpnList = rows
            }
        }
    }


    Flickable {
        id: _flick
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        contentWidth:  width
        contentHeight: _col.implicitHeight
        interactive:   contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: _col
            width: _flick.width
            spacing: 4

            // ── Wi-Fi ─────────────────────────────────────────────────────────
            MenuHeader {
                title: "Wi-Fi"
                on: root.wifiEnabled
                onToggled: root._toggleWifi()
            }
            Text {
                visible: !root.wifiEnabled
                text: "Wi-Fi off"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
                Layout.topMargin: 4
            }
            Text {
                visible: root.wifiEnabled && root.wifiNetworks.length === 0
                text: "Scanning…"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
                Layout.topMargin: 4
            }
            Repeater {
                model: root.wifiEnabled ? root.wifiNetworks : []
                delegate: MenuRow {
                    required property var modelData
                    text: "" + modelData.name
                    icon: {
                        const s = modelData.signalStrength   // 0..1
                        if (s >= 0.8)  return "󰤨"
                        if (s >= 0.55) return "󰤥"
                        if (s >= 0.3)  return "󰤢"
                        return "󰤟"
                    }
                    active:   modelData.connected
                    trailing: modelData.connected ? "Connected" : (modelData.known ? "Saved" : "")
                    // Left click = connect/disconnect; a secured unknown network has
                    // no saved password so it opens the menu. Right click = menu.
                    onClicked: {
                        if (modelData.connected) { modelData.disconnect(); ContextMenuService.close() }
                        else if (modelData.known) { modelData.connect(); ContextMenuService.close() }
                        else {
                            const p = mapToItem(null, width / 2, height)
                            ContextMenuService.show("wifi", modelData, p.x, p.y, PopoutService.anchorScreen)
                        }
                    }
                    onRightClicked: (gx, gy) => ContextMenuService.show("wifi", modelData, gx, gy, PopoutService.anchorScreen)
                }
            }

            // ── VPN (only when nmcli is available) ─────────────────────────────
            Rectangle {
                visible: root._vpnAvailable
                Layout.fillWidth: true; Layout.topMargin: 6; Layout.bottomMargin: 2
                height: 1; color: ThemeManager.outlineVariant; opacity: 0.3
            }
            Text {
                visible: root._vpnAvailable
                text: "VPN"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
            }
            Text {
                visible: root._vpnAvailable && root.vpnList.length === 0
                text: "No VPN connections"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
                Layout.topMargin: 4
            }
            Repeater {
                model: root._vpnAvailable ? root.vpnList : []
                delegate: MenuRow {
                    required property var modelData
                    text:     modelData.name
                    icon:     "󰖂"
                    active:   modelData.active
                    trailing: modelData.active ? "On" : "Off"
                    onClicked: root._nm(["nmcli", "connection", modelData.active ? "down" : "up", "id", modelData.name])
                }
            }

        }
    }

    // ── Shared submenu pieces (mirrors Dashboard quick settings) ───────────────
    component MenuHeader: RowLayout {
        id: mh
        property string title: ""
        property bool   on:    false
        signal toggled()
        Layout.fillWidth: true
        Text {
            text: mh.title
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
            Layout.fillWidth: true
        }
        Rectangle {
            width: 36; height: 20; radius: 10
            color: mh.on ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 16; height: 16; radius: 8
                y: 2; x: mh.on ? 18 : 2
                color: mh.on ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mh.toggled() }
        }
    }

    component MenuRow: Rectangle {
        id: mr
        property string text:     ""
        property string icon:     ""
        property string trailing: ""
        property bool   active:   false
        signal clicked()
        signal rightClicked(real gx, real gy)
        Layout.fillWidth: true
        implicitHeight: 32
        radius: ThemeManager.chipRadius
        color: active
            ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, _mrMa.containsMouse ? 0.22 : 0.13)
            : (_mrMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 8
            Text {
                text: mr.icon
                color: mr.active ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: 14
            }
            Text {
                text: mr.text
                color: mr.active ? ThemeManager.primary : ThemeManager.onSurface
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: mr.trailing !== ""
                text: mr.trailing
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: 10
            }
        }
        MouseArea {
            id: _mrMa; anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: (m) => {
                if (m.button === Qt.RightButton) {
                    const p = mapToItem(null, m.x, m.y)
                    mr.rightClicked(p.x, p.y)
                } else mr.clicked()
            }
        }
    }

}
