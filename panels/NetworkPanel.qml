import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../theme"
import "../services"

// Bar hover popout for Wi-Fi + VPN — same controls as the dashboard quick
// settings (toggle radio, pick a network, toggle VPN connections). Backed by
// nmcli; scans only while the popout is the active one.
Item {
    id: root

    implicitWidth:  260
    implicitHeight: Math.min(_col.implicitHeight + 16, 400)

    readonly property bool active: PopoutService.currentName === "network"
    onActiveChanged: if (active) _rescan()

    // Warm the AP cache once at startup so the very first open paints instantly
    // instead of waiting on a cold radio scan.
    Component.onCompleted: _rescan()

    // ── nmcli-backed state ────────────────────────────────────────────────────
    property bool wifiEnabled: false
    property var  wifiNetworks: []   // [{ ssid, signal, active }]
    property var  vpnList:      []   // [{ name, active }]
    property bool scanning:     false

    function _rescan() {
        _wifiState.running = true
        _wifiScan.running  = true   // instant cached list (--rescan no)
        _wifiRescan.running = true  // background radio rescan, refreshes when done
        _vpnScan.running   = true
        scanning = true
    }

    // Shared parser for both the cached and rescanned `nmcli ... wifi list`.
    // Merge by SSID across BSSIDs: keep max signal, OR the in-use flag.
    function _parseWifi(text) {
        const byId = {}
        for (const ln of text.trim().split("\n")) {
            if (!ln) continue
            const f = ln.split(":")
            const ssid = f.slice(2).join(":")
            if (!ssid) continue
            const sig = parseInt(f[1]) || 0
            const act = f[0] === "*"
            if (byId[ssid]) {
                byId[ssid].signal = Math.max(byId[ssid].signal, sig)
                byId[ssid].active = byId[ssid].active || act
            } else {
                byId[ssid] = { ssid: ssid, signal: sig, active: act }
            }
        }
        const rows = Object.keys(byId).map(k => byId[k])
        rows.sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
        root.wifiNetworks = rows
        root.scanning = false
    }

    // Run an nmcli action then re-scan shortly after.
    property Process _nmAction: Process { running: false }
    function _nm(args) {
        _nmAction.command = args
        _nmAction.running = true
        _rescanTimer.restart()
    }
    property Timer _rescanTimer: Timer {
        interval: 1500; repeat: false
        onTriggered: root._rescan()
    }

    property Process _wifiState: Process {
        command: ["sh", "-c", "nmcli -t -f WIFI radio 2>/dev/null"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.wifiEnabled = text.trim() === "enabled" }
    }
    // Cached list — returns immediately without forcing a radio scan.
    property Process _wifiScan: Process {
        command: ["sh", "-c", "nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null"]
        running: false
        stdout: StdioCollector { onStreamFinished: root._parseWifi(text) }
    }
    // Fresh radio rescan — slower, refreshes the list once it completes.
    property Process _wifiRescan: Process {
        command: ["sh", "-c", "nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan yes 2>/dev/null"]
        running: false
        stdout: StdioCollector { onStreamFinished: root._parseWifi(text) }
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

    property Process _nmEditor: Process { command: ["nm-connection-editor"] }
    function _launch(proc) { proc.running = true; PopoutService.close() }

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
                onToggled: {
                    root._nm(["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"])
                    root.wifiEnabled = !root.wifiEnabled
                }
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
                visible: root.wifiEnabled && root.scanning && root.wifiNetworks.length === 0
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
                    text: modelData.ssid
                    icon: {
                        const s = modelData.signal
                        if (s >= 80) return "󰤨"
                        if (s >= 55) return "󰤥"
                        if (s >= 30) return "󰤢"
                        return "󰤟"
                    }
                    active:   modelData.active
                    trailing: modelData.active ? "Connected" : ""
                    onClicked: if (!modelData.active)
                        root._nm(["nmcli", "device", "wifi", "connect", modelData.ssid])
                }
            }

            // ── VPN ───────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; Layout.topMargin: 6; Layout.bottomMargin: 2
                height: 1; color: ThemeManager.outlineVariant; opacity: 0.3
            }
            Text {
                text: "VPN"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
            }
            Text {
                visible: root.vpnList.length === 0
                text: "No VPN connections"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
                Layout.topMargin: 4
            }
            Repeater {
                model: root.vpnList
                delegate: MenuRow {
                    required property var modelData
                    text:     modelData.name
                    icon:     "󰖂"
                    active:   modelData.active
                    trailing: modelData.active ? "On" : "Off"
                    onClicked: root._nm(["nmcli", "connection", modelData.active ? "down" : "up", "id", modelData.name])
                }
            }

            MenuFooter { text: "Open network settings"; onClicked: root._launch(root._nmEditor) }
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

    component MenuFooter: Rectangle {
        id: mf
        property string text: ""
        signal clicked()
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: 30
        radius: ThemeManager.chipRadius
        color: _mfMa.containsMouse ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.14) : ThemeManager.surfaceContainer
        Behavior on color { ColorAnimation { duration: 100 } }
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 6
            Text {
                text: "󰏌"
                color: ThemeManager.primary
                font.family: ThemeManager.fontFamily; font.pixelSize: 13
            }
            Text {
                text: mf.text
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                Layout.fillWidth: true
            }
        }
        MouseArea {
            id: _mfMa; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: mf.clicked()
        }
    }
}
