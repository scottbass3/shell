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
    onActiveChanged: {
        if (active && _vpnAvailable) _vpnScan.running = true
        if (!active) expandedSsid = ""
    }

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

    // Only one wifi row's actions/password are expanded at a time.
    property string expandedSsid: ""

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
                delegate: ColumnLayout {
                    id: _wrow
                    required property var modelData
                    readonly property string _ssid: "" + modelData.name
                    readonly property bool _exp: root.expandedSsid === _ssid
                    Layout.fillWidth: true
                    spacing: 2

                    MenuRow {
                        text: _wrow._ssid
                        icon: {
                            const s = _wrow.modelData.signalStrength   // 0..1
                            if (s >= 0.8)  return "󰤨"
                            if (s >= 0.55) return "󰤥"
                            if (s >= 0.3)  return "󰤢"
                            return "󰤟"
                        }
                        active:   _wrow.modelData.connected
                        // 󰤇 = saved/known network marker
                        trailing: _wrow.modelData.connected ? "Connected"
                                : (_wrow.modelData.known ? "Saved" : "")
                        onClicked: {
                            // Known/open networks connect on tap; otherwise expand
                            // for a password (and to expose disconnect/forget).
                            if (!_wrow.modelData.connected && !_wrow._exp
                                && (_wrow.modelData.known)) {
                                _wrow.modelData.connect()
                            } else {
                                root.expandedSsid = _wrow._exp ? "" : _wrow._ssid
                                _pskField.text = ""
                            }
                        }
                    }

                    // Expanded actions: password (unknown nets) + connect/forget.
                    ColumnLayout {
                        visible: _wrow._exp
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 4
                        Layout.bottomMargin: 4
                        spacing: 4

                        Rectangle {
                            visible: !_wrow.modelData.connected && !_wrow.modelData.known
                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: ThemeManager.chipRadius
                            color: ThemeManager.surfaceContainer
                            border.width: _pskField.activeFocus ? 1 : 0
                            border.color: ThemeManager.primary
                            TextInput {
                                id: _pskField
                                anchors { fill: parent; leftMargin: 10; rightMargin: 34 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: ThemeManager.onSurface
                                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                echoMode: _pskReveal.checked ? TextInput.Normal : TextInput.Password
                                clip: true
                                onActiveFocusChanged: PopoutService.keyboardActive = activeFocus
                                onAccepted: _wrow.modelData.connectWithPsk(text)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: _pskField.text === ""
                                    text: "Password"
                                    color: ThemeManager.onSurfaceVariant; opacity: 0.5
                                    font: _pskField.font
                                }
                            }
                            Text {
                                id: _pskReveal
                                property bool checked: false
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 8 }
                                text: checked ? "󰈉" : "󰈈"
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 14
                                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: _pskReveal.checked = !_pskReveal.checked }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            NetBtn {
                                visible: !_wrow.modelData.connected
                                text: "Connect"
                                onClicked: {
                                    if (_wrow.modelData.known) _wrow.modelData.connect()
                                    else _wrow.modelData.connectWithPsk(_pskField.text)
                                }
                            }
                            NetBtn {
                                visible: _wrow.modelData.connected
                                text: "Disconnect"
                                onClicked: _wrow.modelData.disconnect()
                            }
                            NetBtn {
                                visible: _wrow.modelData.known
                                text: "Forget"
                                danger: true
                                onClicked: { _wrow.modelData.forget(); root.expandedSsid = "" }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
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
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: mr.clicked()
        }
    }

    // Small action button used in the expanded wifi row.
    component NetBtn: Rectangle {
        id: nb
        property string text: ""
        property bool   danger: false
        signal clicked()
        implicitWidth:  _nbLabel.implicitWidth + 20
        implicitHeight: 28
        radius: ThemeManager.chipRadius
        readonly property color _accent: danger ? ThemeManager.error : ThemeManager.primary
        color: _nbMa.containsMouse
            ? Qt.rgba(nb._accent.r, nb._accent.g, nb._accent.b, 0.22)
            : Qt.rgba(nb._accent.r, nb._accent.g, nb._accent.b, 0.13)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            id: _nbLabel
            anchors.centerIn: parent
            text: nb.text
            color: nb._accent
            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
        }
        MouseArea {
            id: _nbMa; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: nb.clicked()
        }
    }
}
