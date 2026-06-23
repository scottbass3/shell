import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Hyprland
import "../theme"
import "../services"

Item {
    id: root

    implicitWidth:  900
    // Fixed size across tabs (use the taller Home/bento height); the Media tab
    // fills the same area.
    implicitHeight: _tabBar.height + ThemeManager.spacing
                  + _grid.implicitHeight
                  + ThemeManager.spacingLg * 2

    property var now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    readonly property var _fr: Qt.locale("fr_FR")

    // Active dashboard tab ("home" bento | "media" player)
    property string tab: "home"
    property bool   _playerMenu: false
    property real   _pmX:   0      // dropdown-button centre x (root coords)
    property real   _pmTop: 0      // dropdown-button top y (root coords)
    onTabChanged: { qsKey = ""; _playerMenu = false }

    // Map the active player → its Hyprland special workspace (matches hyprland.lua)
    readonly property string _playerWs: {
        const n = (MprisService.identity || "").toLowerCase()
        if (n.indexOf("spotify") >= 0) return "spotify"
        if (n.indexOf("youtube") >= 0) return "ytmusic"
        return ""
    }
    function _openPlayerWs() {
        if (_playerWs === "") return
        Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + _playerWs + '")')
        PopoutService.close()
    }

    // Currently open QuickSettings submenu key ("" = none)
    property string qsKey: ""

    // Calendar day overlay (YYYY-MM-DD, "" = closed) + create-form toggle
    property string calSelectedDate: ""
    property bool   calCreating:     false
    onCalSelectedDateChanged: calCreating = false

    // Pending dangerous power action awaiting confirmation ("" | "reboot" | "shutdown")
    property string _confirmAction: ""
    Connections {
        target: PopoutService
        function onCurrentNameChanged() {
            if (PopoutService.currentName !== "dashboard") { root._confirmAction = ""; root.calSelectedDate = ""; root.qsKey = ""; root.tab = "home"; root._playerMenu = false }
        }
    }
    function _runConfirm() {
        if      (_confirmAction === "reboot")   _rebootProc.running   = true
        else if (_confirmAction === "shutdown") _shutdownProc.running = true
        else if (_confirmAction === "logout")   _logoutProc.running   = true
        _confirmAction = ""
        PopoutService.close()
    }

    // ── nmcli-backed lists (Wi-Fi networks, VPN connections) ──────────────────
    property bool wifiEnabled: false
    property var  wifiNetworks: []   // [{ ssid, signal, active }]
    property var  vpnList:      []   // [{ name, active }]

    onQsKeyChanged: {
        if (qsKey === "wifi") { _wifiState.running = true; _wifiScan.running = true }
        else if (qsKey === "vpn") _vpnScan.running = true
    }

    // Run an nmcli action then re-scan shortly after.
    property Process _nmAction: Process { running: false }
    function _nm(args, rescan) {
        _nmAction.command = args
        _nmAction.running = true
        _rescanTimer.restart()
        _rescanKey = rescan
    }
    property string _rescanKey: ""
    property Timer _rescanTimer: Timer {
        interval: 1500; repeat: false
        onTriggered: {
            if (root._rescanKey === "wifi") { root._wifiState.running = true; root._wifiScan.running = true }
            else if (root._rescanKey === "vpn") root._vpnScan.running = true
        }
    }

    // Wi-Fi radio state
    property Process _wifiState: Process {
        command: ["sh", "-c", "nmcli -t -f WIFI radio 2>/dev/null"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.wifiEnabled = text.trim() === "enabled" }
    }
    // Wi-Fi network list
    property Process _wifiScan: Process {
        command: ["sh", "-c", "nmcli -t -f IN-USE,SIGNAL,SSID device wifi list 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                // Merge by SSID across BSSIDs: keep max signal, OR the in-use flag.
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
            }
        }
    }
    // VPN connection list
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

    // External config apps. Floating/centered handled by hyprland.conf windowrules.
    property Process _blueman:  Process { command: ["blueman-manager"] }
    property Process _nmEditor: Process { command: ["nm-connection-editor"] }

    // Launch an external app, then dismiss the whole dashboard.
    function _launch(proc) {
        proc.running = true
        qsKey = ""
        PopoutService.close()
    }

    // Open a URL in the default browser, then dismiss the dashboard.
    property Process _openUrlProc: Process { running: false }
    function _openUrl(url) {
        if (!url) return
        _openUrlProc.command = ["xdg-open", url]
        _openUrlProc.running = true
        calSelectedDate = ""
        PopoutService.close()
    }

    // Escape HTML + turn URLs into <a> links + keep line breaks (for StyledText).
    function _linkify(s) {
        if (!s) return ""
        const A = String.fromCharCode(1), B = String.fromCharCode(2)
        const urls = []
        let tmp = s.replace(/https?:\/\/[^\s]+/g, (m) => {
            let trail = ""
            const mt = m.match(/[>.,)\]]+$/)
            if (mt) { trail = mt[0]; m = m.slice(0, m.length - trail.length) }
            urls.push(m)
            return A + (urls.length - 1) + B + trail
        })
        tmp = tmp.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const re = new RegExp(A + "(\\d+)" + B, "g")
        tmp = tmp.replace(re, (m, i) => {
            const ue = urls[+i].replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            return '<a href="' + ue + '">' + ue + '</a>'
        })
        return tmp.replace(/\n/g, "<br>")
    }

    // ── Session info ──────────────────────────────────────────────────────────
    property string userName: ""
    property string homeDir:  ""
    property string uptime:   ""
    property Process _sysInfo: Process {
        command: ["sh", "-c", "whoami; printf '%s\\n' \"$HOME\"; uptime -p"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n")
                root.userName = l[0] ?? ""
                root.homeDir  = l[1] ?? ""
                root.uptime   = (l[2] ?? "").replace(/^up\s+/, "")
            }
        }
    }
    property Timer _uptimeTimer: Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: root._sysInfo.running = true
    }

    // ── Session processes ─────────────────────────────────────────────────────
    // Lock uses the custom WlSessionLock (LockService), not hyprlock.
    property Process _suspendProc:  Process { command: ["systemctl", "suspend"] }
    property Process _logoutProc:   Process { command: ["hyprctl", "dispatch", "exit"] }
    property Process _rebootProc:   Process { command: ["systemctl", "reboot"] }
    property Process _shutdownProc: Process { command: ["systemctl", "poweroff"] }

    Component.onCompleted: root._sysInfo.running = true

    // ════════════════════════ TAB BAR ═══════════════════════════════════════
    RowLayout {
        id: _tabBar
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            topMargin: ThemeManager.spacingLg; leftMargin: ThemeManager.spacingLg; rightMargin: ThemeManager.spacingLg
        }
        height: 38
        spacing: 8

        Item { Layout.fillWidth: true }
        DashTab { icon: "󰕮"; active: root.tab === "home";  onClicked: root.tab = "home" }
        DashTab { icon: "󰎈"; active: root.tab === "media"; onClicked: root.tab = "media" }
        Item { Layout.fillWidth: true }
    }

    component DashTab: Rectangle {
        property string icon: ""
        property bool active: false
        signal clicked()
        implicitWidth: 56
        implicitHeight: 38
        radius: ThemeManager.chipRadius
        color: active
            ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, _tabMa.containsMouse ? 0.28 : 0.18)
            : (_tabMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            anchors.centerIn: parent
            text: parent.icon
            color: parent.active ? ThemeManager.primary : ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: 22
        }
        MouseArea { id: _tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    // ════════════════════════ BENTO GRID (Home) ═════════════════════════════
    RowLayout {
        id: _grid
        visible: root.tab === "home"
        anchors {
            top: _tabBar.bottom; left: parent.left; right: parent.right
            topMargin: ThemeManager.spacing; leftMargin: ThemeManager.spacingLg; rightMargin: ThemeManager.spacingLg
        }
        spacing: ThemeManager.spacing

        // ── Left block (2 rows) ──────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth:  true
            Layout.fillHeight: true
            spacing: ThemeManager.spacing

            // Row 1: profile + weather
            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacing
                ProfileCard  { Layout.fillWidth: true; Layout.fillHeight: true }
                WeatherCard  { Layout.preferredWidth: 270; Layout.maximumWidth: 270; Layout.fillHeight: true }
            }

            // Row 2: clock + calendar + metrics
            RowLayout {
                Layout.fillWidth: true
                spacing: ThemeManager.spacing

                Card {
                    Layout.preferredWidth: 120
                    Layout.fillHeight: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: root.now.toLocaleTimeString(root._fr, "HH:mm")
                            color: ThemeManager.onSurface
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: 26; font.weight: Font.Bold
                        }
                        Text {
                            text: root.now.toLocaleDateString(root._fr, "ddd")
                            color: ThemeManager.primary
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
                        }
                        Text {
                            text: root.now.toLocaleDateString(root._fr, "d MMM")
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    MonthCalendar { Layout.fillWidth: true }
                }

                MetricsCard { Layout.preferredWidth: 70; Layout.fillHeight: true }
            }
        }

        // ── QuickSettings rail spacer (real rail is an overlay, see below) ─────
        Item { Layout.preferredWidth: 48; Layout.fillHeight: true }

        // ── MPRIS controls ───────────────────────────────────────────────────
        MprisCard { Layout.preferredWidth: 200; Layout.fillHeight: true }
    }

    // ════════════════════════ MEDIA TAB ═════════════════════════════════════
    Rectangle {
        id: _mediaView
        visible: root.tab === "media"
        // Visualizer runs only while the media tab is open AND the selected
        // player is actually playing.
        Binding {
            target: CavaService
            property: "active"
            value: _mediaView.visible && MprisService.playing
        }
        // Poll the YouTube Music companion server only while the media tab is open.
        Binding {
            target: YtmCompanionService
            property: "active"
            value: _mediaView.visible
        }
        anchors {
            top: _tabBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom
            topMargin: ThemeManager.spacing; leftMargin: ThemeManager.spacingLg
            rightMargin: ThemeManager.spacingLg; bottomMargin: ThemeManager.spacingLg
        }
        radius: ThemeManager.chipRadius + 4
        color:  ThemeManager.surfaceContainer
        layer.enabled: true
        layer.effect: Elevation { level: 2 }

        // Empty state
        Text {
            anchors.centerIn: parent
            visible: !MprisService.hasPlayer
            text: "No media playing"
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeMd
            opacity: 0.6
        }

        RowLayout {
            anchors { fill: parent; margins: 18 }
            visible: MprisService.hasPlayer
            spacing: 18

            // Left column: round album art + visualizer, centred in its column
            Item {
                id: _artBox
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.fillHeight: true

                readonly property int _maxBar: 28           // bar length (outward)
                readonly property int _artReserve: 16       // art-size margin (keeps art at original size)
                readonly property real _artD: Math.min(width, 150, height) - _artReserve * 2
                readonly property real _ring: _artD / 2 + 4

                // Visualizer bars radiating around the circle
                Repeater {
                    model: SettingsService.get("media.visualizer", true) ? CavaService.bars : 0
                    delegate: Item {
                        required property int index
                        anchors.centerIn: parent
                        width: 1; height: 1
                        rotation: index * (360 / CavaService.bars)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 3; radius: 1.5
                            height: 3 + (CavaService.active ? (CavaService.levels[index] || 0) : 0) * _artBox._maxBar
                            y: -(_artBox._ring + height)
                            color: ThemeManager.primary
                            opacity: 0.85
                            Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                        }
                    }
                }

                ClippingRectangle {
                    anchors.centerIn: parent
                    width: _artBox._artD; height: _artBox._artD
                    radius: width / 2
                    color: ThemeManager.surfaceContainerHigh
                    Image {
                        id: _bigArt
                        anchors.fill: parent
                        source: MprisService.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width:  512
                        sourceSize.height: 512
                        smooth: true
                        mipmap: true
                        cache: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: _bigArt.status !== Image.Ready
                        text: "󰝚"
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 56
                    }
                }
            }

            // Center column — vertically centred, compact, width-capped so the
            // seek bar / switcher don't stretch across the whole panel.
            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.maximumWidth: 300
                Layout.fillHeight: true
                spacing: 3

                Item { Layout.fillHeight: true }

                MarqueeText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: MprisService.title || "Unknown"
                    color: ThemeManager.onSurface
                    pixelSize: ThemeManager.fontSizeMd + 2
                    bold: true
                }
                MarqueeText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: MprisService.artist
                    color: ThemeManager.onSurfaceVariant
                    pixelSize: ThemeManager.fontSizeSm
                }
                Text {
                    text: MprisService.album
                    visible: MprisService.album !== ""
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 10
                    opacity: 0.7
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                }

                Item { implicitHeight: 8 }

                // Progress + times
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: MprisService.fmt(MprisService.position)
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily; font.pixelSize: 10
                    }
                    Rectangle {
                        id: _scrub
                        Layout.fillWidth: true
                        implicitHeight: 6; radius: 3
                        color: ThemeManager.surfaceContainerHigh
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: Math.max(0, parent.width * MprisService.progress)
                            radius: 3; color: ThemeManager.primary
                        }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -6
                            enabled: MprisService.canSeek
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: (e) => MprisService.seekTo((e.x + 6) / _scrub.width)
                        }
                    }
                    Text {
                        text: MprisService.fmt(MprisService.length)
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily; font.pixelSize: 10
                    }
                }

                // Transport — compact, centred
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 18
                    spacing: 4
                    MediaBtn { icon: "󰒝"; enabled: MprisService.canShuffle; active: MprisService.shuffle; onClicked: MprisService.toggleShuffle() }
                    MediaBtn { icon: "󰒮"; enabled: MprisService.canPrev; onClicked: MprisService.previous() }
                    MediaBtn { icon: MprisService.playing ? "󰏤" : "󰐊"; big: true; onClicked: MprisService.playPause() }
                    MediaBtn { icon: "󰒭"; enabled: MprisService.canNext; onClicked: MprisService.next() }
                    MediaBtn {
                        icon: MprisService.loopState === 2 ? "󰑘" : "󰑖"   // 2 = Track
                        enabled: MprisService.canLoop
                        active: MprisService.loopState !== 0
                        onClicked: MprisService.cycleLoop()
                    }
                }

                // Player switcher (dropdown) + pop-out — centred
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 18
                    spacing: 6
                    PlayerDropdown { visible: MprisService.players.length > 0; Layout.alignment: Qt.AlignVCenter }
                    MediaBtn { icon: "󰍹"; visible: root._playerWs !== ""; small: true; onClicked: root._openPlayerWs() }
                    MediaBtn { icon: "󰏋"; visible: MprisService.canRaise && root._playerWs === ""; small: true; onClicked: { MprisService.raise(); PopoutService.close() } }
                }

                Item { Layout.fillHeight: true }
            }

            // Right column: bongo cat — centred in its column, animates when playing
            AnimatedImage {
                id: _bongo
                visible: SettingsService.get("media.bongo", true)
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.fillHeight: true
                Layout.maximumHeight: 92
                source: Qt.resolvedUrl("../assets/bongocat.gif")
                fillMode: AnimatedImage.PreserveAspectFit
                horizontalAlignment: Image.AlignHCenter
                verticalAlignment: Image.AlignVCenter
                asynchronous: true
                // Beat-matched: tap (flip the 2 gif frames) on each detected beat;
                // rest on frame 0 when nothing is playing.
                playing: false
                paused:  true
                currentFrame: MprisService.playing ? CavaService.frame : 0
            }
        }
    }

    // ── Player selector list (root overlay → reliable clicks) ─────────────────
    MouseArea {
        z: 60
        anchors.fill: parent
        visible: root._playerMenu && root.tab === "media"
        onClicked: root._playerMenu = false
    }
    Rectangle {
        id: _pmList
        z: 61
        visible: root._playerMenu && root.tab === "media"
        width: 200
        // Originate from the dropdown button: centred on it, opening upward.
        x: Math.max(8, Math.round(root._pmX - width / 2))
        y: Math.round(root._pmTop - height - 6)
        height: _pmCol.implicitHeight + 8
        radius: ThemeManager.chipRadius
        color:  ThemeManager.surfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)
        layer.enabled: true
        layer.effect: Elevation { level: 3 }

        Column {
            id: _pmCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
            spacing: 2
            Repeater {
                model: root._playerMenu ? MprisService.players : []
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: MprisService.active === modelData
                    width: parent.width; height: 34
                    radius: ThemeManager.chipRadius
                    color: sel
                        ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.18)
                        : (_pmRowMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        Text { text: MprisService.icon(modelData); color: parent.parent.sel ? ThemeManager.primary : ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: 17 }
                        Text {
                            Layout.fillWidth: true
                            text: MprisService.label(modelData)
                            color: parent.parent.sel ? ThemeManager.primary : ThemeManager.onSurface
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: _pmRowMa
                        anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { MprisService.select(modelData); root._playerMenu = false }
                    }
                }
            }
        }
    }

    // Continuous ticker: when text overflows, two copies scroll left at a
    // constant speed and loop seamlessly. Centred (single copy) when it fits.
    component MarqueeText: Item {
        id: mq
        property string text: ""
        property color  color: ThemeManager.onSurface
        property int    pixelSize: 12
        property bool   bold: false
        readonly property real gap: 48
        readonly property bool over: _m1.implicitWidth > width
        property real _scroll: 0

        clip: true
        implicitHeight: _m1.implicitHeight

        Row {
            spacing: mq.gap
            x: mq.over ? mq._scroll : Math.round((mq.width - _m1.implicitWidth) / 2)
            Text {
                id: _m1
                text: mq.text; color: mq.color
                font.family: ThemeManager.fontFamily; font.pixelSize: mq.pixelSize
                font.weight: mq.bold ? Font.Bold : Font.Normal
            }
            Text {
                visible: mq.over
                text: mq.text; color: mq.color
                font.family: ThemeManager.fontFamily; font.pixelSize: mq.pixelSize
                font.weight: mq.bold ? Font.Bold : Font.Normal
            }
        }

        NumberAnimation {
            target: mq; property: "_scroll"
            running: mq.over && mq.visible
            from: 0; to: -(_m1.implicitWidth + mq.gap)
            duration: Math.max(1, (_m1.implicitWidth + mq.gap) * 22)   // ~constant px/s, linear
            loops: Animation.Infinite
        }
    }

    component MediaBtn: Rectangle {
        id: mbt
        property string icon: ""
        property bool   big:   false
        property bool   small: false
        property bool   active: false
        signal clicked()
        implicitWidth:  big ? 48 : (small ? 38 : 44)
        implicitHeight: big ? 48 : (small ? 38 : 44)
        radius: width / 2
        color: big
            ? (_mbtMa.containsMouse ? ThemeManager.primary : Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.85))
            : (active ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.18)
                      : (_mbtMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.10) : "transparent"))
        opacity: mbt.enabled ? 1 : 0.35
        Text {
            anchors.centerIn: parent
            text: mbt.icon
            color: mbt.big ? ThemeManager.onPrimary : (mbt.active ? ThemeManager.primary : ThemeManager.onSurface)
            font.family: ThemeManager.fontFamily
            font.pixelSize: mbt.big ? 22 : (mbt.small ? 20 : 24)
        }
        MouseArea { id: _mbtMa; anchors.fill: parent; enabled: mbt.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mbt.clicked() }
    }

    // ── Player selector dropdown button (list is a root-level overlay) ────────
    component PlayerDropdown: Rectangle {
        id: _dd
        implicitWidth:  184
        implicitHeight: 34
        radius: ThemeManager.chipRadius
        color: _ddMa.containsMouse
            ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.10)
            : ThemeManager.surfaceContainerHigh
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 8
            Text { text: MprisService.icon(MprisService.active); color: ThemeManager.primary; font.family: ThemeManager.fontFamily; font.pixelSize: 17 }
            Text {
                Layout.fillWidth: true
                text: MprisService.label(MprisService.active)
                color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                elide: Text.ElideRight
            }
            Text { text: root._playerMenu ? "󰅃" : "󰅀"; color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: 13 }
        }
        MouseArea {
            id: _ddMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!root._playerMenu) {
                    const pt = _dd.mapToItem(root, 0, 0)
                    root._pmX   = pt.x + _dd.width / 2
                    root._pmTop = pt.y
                }
                root._playerMenu = !root._playerMenu
            }
        }
    }

    // ════════════════════════ QUICK SETTINGS OVERLAY ════════════════════════
    // Dismiss catcher — closes any open submenu when clicking elsewhere.
    MouseArea {
        anchors.fill: parent
        z: 20
        visible: root.qsKey !== ""
        onClicked: root.qsKey = ""
    }

    // Icon rail (anchored to match the spacer column; above catcher)
    Rectangle {
        id: _qsRail
        z: 30
        visible: root.tab === "home"
        width: 48
        anchors {
            top:    _grid.top
            bottom: _grid.bottom
            right:  parent.right
            rightMargin: ThemeManager.spacingLg + 200 + ThemeManager.spacing  // outer + mpris + gap
        }
        radius: ThemeManager.chipRadius + 4
        color:  ThemeManager.surfaceContainer

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            QsIcon { icon: "󰕾"; key: "volume" }
            QsIcon { icon: "󰃠"; key: "brightness" }
            QsIcon { icon: "󰖩"; key: "wifi" }
            QsIcon { icon: "󰖂"; key: "vpn" }
            QsIcon { icon: "󰂯"; key: "bluetooth" }
            QsIcon {
                icon: NotificationService.doNotDisturb ? "󰂛" : "󰂚"; key: "dnd"
                // DND toggles directly (no flyout)
                toggle: true
                onActivated: NotificationService.doNotDisturb = !NotificationService.doNotDisturb
                highlighted: NotificationService.doNotDisturb
            }
            QsIcon { icon: "󰔎"; key: "theme" }
            QsIcon {
                icon: "󰒓"; key: "settings"
                toggle: true
                onActivated: { SettingsUi.show(); PopoutService.close() }
            }
        }
    }

    // Flyout card — slides out to the LEFT of the rail, elevated, content-sized.
    // Capped to the dashboard height; tall content scrolls instead of truncating.
    Rectangle {
        id: _qsFlyout
        z: 30
        layer.enabled: true
        layer.effect: Elevation { level: 3 }
        visible: root.qsKey !== "" && root.qsKey !== "dnd" && _flyout.item
        anchors {
            right: _qsRail.left; rightMargin: ThemeManager.spacing
            top:   _qsRail.top
        }

        readonly property int _pad: 10
        readonly property real _contentH: _flyout.item ? _flyout.item.implicitHeight : 0
        readonly property real _maxH: root.height - ThemeManager.spacingLg * 2

        width:  _flyout.item ? _flyout.item.implicitWidth + _pad * 2 : 0
        height: Math.min(_contentH + _pad * 2, _maxH)
        radius: ThemeManager.panelRadius
        color:  ThemeManager.surfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)

        opacity: visible ? 1 : 0
        scale:   visible ? 1 : 0.92
        transformOrigin: Item.Right
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: [0.05,0.7,0.1,1,1,1] } }

        Flickable {
            anchors.fill: parent
            anchors.margins: _qsFlyout._pad
            clip: true
            contentWidth:  width
            contentHeight: _flyout.item ? _flyout.item.implicitHeight : 0
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Loader {
                id: _flyout
                width: parent.width
                sourceComponent: {
                    switch (root.qsKey) {
                        case "volume":     return _volCmp
                        case "brightness": return _brightCmp
                        case "theme":      return _themeCmp
                        case "wifi":       return _wifiCmp
                        case "vpn":        return _vpnCmp
                        case "bluetooth":  return _btCmp
                        default:           return null
                    }
                }
            }
        }
    }

    // ════════════════════════ CONFIRM OVERLAY (reboot/shutdown) ═════════════
    MouseArea {
        anchors.fill: parent
        z: 45
        visible: root._confirmAction !== ""
        onClicked: root._confirmAction = ""
    }
    Rectangle {
        z: 46
        visible: root._confirmAction !== ""
        anchors.centerIn: parent
        width: 240
        layer.enabled: true
        layer.effect: Elevation { level: 4 }
        height: _confCol.implicitHeight + 32
        radius: ThemeManager.panelRadius
        color:  ThemeManager.surfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(ThemeManager.error.r, ThemeManager.error.g, ThemeManager.error.b, 0.4)

        ColumnLayout {
            id: _confCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root._confirmAction === "reboot" ? "󰑙" : (root._confirmAction === "shutdown" ? "󰐥" : "󰍃")
                color: ThemeManager.error
                font.family: ThemeManager.fontFamily
                font.pixelSize: 32
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root._confirmAction === "reboot" ? "Reboot now?"
                    : (root._confirmAction === "shutdown" ? "Shut down now?" : "Log out now?")
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeMd; font.weight: Font.Medium
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                ConfirmBtn { label: "Cancel";  onClicked: root._confirmAction = "" }
                ConfirmBtn { label: "Confirm"; danger: true; onClicked: root._runConfirm() }
            }
        }
    }

    component ConfirmBtn: Rectangle {
        id: cb
        property string label:  ""
        property bool   danger: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 34
        radius: ThemeManager.chipRadius
        readonly property color _accent: danger ? ThemeManager.error : ThemeManager.primary
        color: _cbHov.hovered
            ? Qt.rgba(_accent.r, _accent.g, _accent.b, danger ? 0.9 : 0.18)
            : (danger ? Qt.rgba(_accent.r, _accent.g, _accent.b, 0.75) : ThemeManager.surfaceContainer)
        Text {
            anchors.centerIn: parent
            text: cb.label
            color: cb.danger ? ThemeManager.onError : ThemeManager.onSurface
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
        }
        HoverHandler { id: _cbHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: cb.clicked() }
    }

    // ════════════════════════ CALENDAR DAY OVERLAY ══════════════════════════
    MouseArea {
        anchors.fill: parent
        z: 35
        visible: root.calSelectedDate !== ""
        onClicked: root.calSelectedDate = ""
    }

    Rectangle {
        id: _calPanel
        z: 40
        layer.enabled: true
        layer.effect: Elevation { level: 3 }
        visible: root.calSelectedDate !== ""
        width:  320
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top; topMargin: ThemeManager.spacingLg
        }
        readonly property real _maxH: root.height - ThemeManager.spacingLg * 2
        height: Math.min(_calCol.implicitHeight + 24, _maxH)
        radius: ThemeManager.panelRadius
        color:  ThemeManager.surfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)

        opacity: visible ? 1 : 0
        scale:   visible ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: [0.05,0.7,0.1,1,1,1] } }

        readonly property var _events: {
            const _ = CalendarService.eventsByDate
            return root.calSelectedDate !== "" ? CalendarService.eventsOn(root.calSelectedDate) : []
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 12
            clip: true
            contentWidth: width
            contentHeight: _calCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            ColumnLayout {
                id: _calCol
                width: parent.width
                spacing: 8

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: root.calSelectedDate !== ""
                            ? new Date(root.calSelectedDate).toLocaleDateString(root._fr, "dddd, d MMMM")
                            : ""
                        color: ThemeManager.onSurface
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeMd; font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    CalIconBtn { visible: CalendarService.canCreate; icon: root.calCreating ? "󰅖" : "󰐕"; onClicked: root.calCreating = !root.calCreating }
                    CalIconBtn { icon: "󰅖"; onClicked: root.calSelectedDate = "" }
                }

                // ── Create form ───────────────────────────────────────────────
                ColumnLayout {
                    visible: root.calCreating
                    Layout.fillWidth: true
                    spacing: 6

                    CalField { id: _evTitle; placeholder: "Title" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        CalField { id: _evStart; placeholder: "09:00"; Layout.preferredWidth: 70 }
                        CalField { id: _evEnd;   placeholder: "10:00"; Layout.preferredWidth: 70 }
                        Item { Layout.fillWidth: true }
                    }
                    CalField { id: _evLoc; placeholder: "Location (optional)" }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: ThemeManager.chipRadius
                        color: _saveMa.containsMouse ? ThemeManager.primary
                             : Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.85)
                        opacity: CalendarService.busy ? 0.5 : 1
                        Text {
                            anchors.centerIn: parent
                            text: CalendarService.busy ? "Saving…" : "Add event"
                            color: ThemeManager.onPrimary
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
                        }
                        MouseArea {
                            id: _saveMa
                            anchors.fill: parent
                            enabled: !CalendarService.busy && _evTitle.text !== ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                CalendarService.createEvent(root.calSelectedDate,
                                    _evStart.text, _evEnd.text, _evTitle.text, _evLoc.text)
                                _evTitle.text = ""; _evStart.text = ""; _evEnd.text = ""; _evLoc.text = ""
                                root.calCreating = false
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.outlineVariant; opacity: 0.3 }
                }

                // ── Event list ────────────────────────────────────────────────
                Text {
                    visible: !root.calCreating && _calPanel._events.length === 0
                    text: "No events"
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeSm
                    opacity: 0.6
                }

                Repeater {
                    model: root.calCreating ? [] : _calPanel._events
                    delegate: Rectangle {
                        id: _evRow
                        required property var modelData
                        property bool expanded: false
                        Layout.fillWidth: true
                        implicitHeight: _evInner.implicitHeight + 16
                        radius: ThemeManager.chipRadius
                        color: _evHov.hovered || expanded
                            ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.06)
                            : ThemeManager.surfaceContainer
                        Behavior on color { ColorAnimation { duration: 100 } }

                        HoverHandler { id: _evHov }

                        ColumnLayout {
                            id: _evInner
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 2

                            // Header — click toggles expand
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: _hdr.implicitHeight
                                RowLayout {
                                    id: _hdr
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 8
                                    Rectangle { width: 3; radius: 1.5; color: ThemeManager.primary; Layout.preferredHeight: 16 }
                                    Text {
                                        text: _evRow.modelData.stime !== "" ? _evRow.modelData.stime : "All day"
                                        color: ThemeManager.primary
                                        font.family: ThemeManager.fontFamily
                                        font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: _evRow.modelData.title
                                        color: ThemeManager.onSurface
                                        font.family: ThemeManager.fontFamily
                                        font.pixelSize: ThemeManager.fontSizeSm
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: _evRow.expanded = !_evRow.expanded
                                }
                            }

                            // Details (expanded)
                            Text {
                                visible: _evRow.expanded && _evRow.modelData.stime !== ""
                                text: "󱎫  " + _evRow.modelData.stime + " – " + _evRow.modelData.etime
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 11
                                Layout.leftMargin: 11
                            }
                            Text {
                                visible: _evRow.expanded && _evRow.modelData.location !== ""
                                text: "󰍎  " + _evRow.modelData.location
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                Layout.leftMargin: 11
                            }
                            // Description with clickable links
                            Text {
                                id: _descText
                                visible: _evRow.expanded && _evRow.modelData.description !== ""
                                text: root._linkify(_evRow.modelData.description)
                                textFormat: Text.StyledText
                                linkColor: ThemeManager.primary
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                Layout.leftMargin: 11
                                Layout.topMargin: 2

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    property string _hl: ""
                                    cursorShape: _hl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onPositionChanged: (e) => _hl = _descText.linkAt(e.x, e.y)
                                    onExited: _hl = ""
                                    onClicked: (e) => {
                                        const l = _descText.linkAt(e.x, e.y)
                                        if (l !== "") root._openUrl(l)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component CalIconBtn: Rectangle {
        property string icon: ""
        signal clicked()
        implicitWidth: 26; implicitHeight: 26; radius: 6
        color: _cibMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent"
        Behavior on color { ColorAnimation { duration: 80 } }
        Text {
            anchors.centerIn: parent
            text: parent.icon
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily; font.pixelSize: 15
        }
        MouseArea { id: _cibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    component CalField: Rectangle {
        property string placeholder: ""
        property alias  text: _fieldInput.text
        Layout.fillWidth: true
        implicitHeight: 30
        radius: ThemeManager.chipRadius
        color: ThemeManager.surfaceContainer
        border.width: _fieldInput.activeFocus ? 1 : 0
        border.color: ThemeManager.primary
        TextInput {
            id: _fieldInput
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            color: ThemeManager.onSurface
            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
            clip: true
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: _fieldInput.text === ""
                text: parent.parent.placeholder
                color: ThemeManager.onSurfaceVariant; opacity: 0.5
                font: _fieldInput.font
            }
        }
    }

    // ── Flyout content components ───────────────────────────────────────────
    Component { id: _volCmp;   AudioPanel {} }

    Component {
        id: _brightCmp
        ColumnLayout {
            implicitWidth: 90
            spacing: ThemeManager.spacing
            VertSlider {
                Layout.alignment: Qt.AlignHCenter
                icon:  "󰃠"
                value: BrightnessService.value / 100
                label: BrightnessService.value + "%"
                onMoved: (f) => BrightnessService.set(f * 100)
            }
            Text {
                visible: !BrightnessService.available
                Layout.alignment: Qt.AlignHCenter
                text: "brightnessctl not found"
                color: ThemeManager.error
                font.family: ThemeManager.fontFamily
                font.pixelSize: 10
            }
        }
    }

    Component {
        id: _themeCmp
        ColumnLayout {
            spacing: 4
            Text {
                text: "Theme"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
            }
            Repeater {
                model: ThemeManager.availableThemes
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: ThemeManager.activeId === modelData.id
                    Layout.fillWidth: true
                    // Drives the column width to the widest pill
                    implicitWidth: _tlabel.implicitWidth + 24
                    implicitHeight: 30
                    radius: ThemeManager.chipRadius
                    color: active
                        ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, _tma.containsMouse ? 0.28 : 0.18)
                        : (_tma.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        id: _tlabel
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: modelData.name
                        color: parent.active ? ThemeManager.primary : ThemeManager.onSurface
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                    }
                    MouseArea {
                        id: _tma; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: ThemeManager.setTheme(modelData.id)
                    }
                }
            }
        }
    }

    // ── Bluetooth flyout ─────────────────────────────────────────────────────
    Component {
        id: _btCmp
        Item {
            implicitWidth:  240
            implicitHeight: _btCol.implicitHeight
            ColumnLayout {
                id: _btCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 4

            MenuHeader {
                title: "Bluetooth"
                on: Bluetooth.defaultAdapter?.enabled ?? false
                onToggled: { const a = Bluetooth.defaultAdapter; if (a) a.enabled = !a.enabled }
            }

            Text {
                visible: !(Bluetooth.defaultAdapter?.enabled ?? false)
                text: "Adapter off"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
                Layout.topMargin: 4
            }

            Repeater {
                model: (Bluetooth.defaultAdapter?.enabled ?? false) ? (Bluetooth.devices?.values ?? []) : []
                delegate: MenuRow {
                    required property var modelData
                    text:     (modelData.deviceName && modelData.deviceName !== "")
                              ? modelData.deviceName : modelData.address
                    icon:     modelData.connected ? "󰂱" : "󰂯"
                    active:   modelData.connected
                    trailing: modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                }
            }

            MenuFooter { text: "Open blueman-manager"; onClicked: root._launch(root._blueman) }
            }
        }
    }

    // ── Wi-Fi flyout ───────────────────────────────────────────────────────--
    Component {
        id: _wifiCmp
        Item {
            implicitWidth:  250
            implicitHeight: _wifiCol.implicitHeight
            ColumnLayout {
                id: _wifiCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 4

            MenuHeader {
                title: "Wi-Fi"
                on: root.wifiEnabled
                onToggled: {
                    root._nm(["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"], "wifi")
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

            Repeater {
                model: root.wifiEnabled ? root.wifiNetworks : []
                delegate: MenuRow {
                    required property var modelData
                    text:     modelData.ssid
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
                        root._nm(["nmcli", "device", "wifi", "connect", modelData.ssid], "wifi")
                }
            }

            MenuFooter { text: "Open network settings"; onClicked: root._launch(root._nmEditor) }
            }
        }
    }

    // ── VPN flyout ─────────────────────────────────────────────────────────--
    Component {
        id: _vpnCmp
        Item {
            implicitWidth:  240
            implicitHeight: _vpnCol.implicitHeight
            ColumnLayout {
                id: _vpnCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 4

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
                    onClicked: root._nm(
                        ["nmcli", "connection", modelData.active ? "down" : "up", "id", modelData.name],
                        "vpn")
                }
            }

            MenuFooter { text: "Open network settings"; onClicked: root._launch(root._nmEditor) }
            }
        }
    }

    // ── Shared submenu pieces ─────────────────────────────────────────────────
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
        // Pill toggle
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

    // ════════════════════════ COMPONENTS ════════════════════════════════════

    component Card: Rectangle {
        property int pad: 12
        default property alias _kids: _inner.data
        radius: ThemeManager.chipRadius + 4
        color:  ThemeManager.surfaceContainer
        implicitHeight: _inner.implicitHeight + pad * 2
        layer.enabled: true
        layer.effect: Elevation { level: 2 }
        ColumnLayout {
            id: _inner
            anchors.fill: parent
            anchors.margins: parent.pad
            spacing: ThemeManager.spacing
        }
    }

    // ── QuickSettings rail icon ──────────────────────────────────────────────
    component QsIcon: Item {
        id: qi
        property string icon: ""
        property string key:  ""
        property bool   toggle: false       // true = act directly, no flyout
        property bool   highlighted: false
        signal activated()

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 40; implicitHeight: 40

        readonly property bool active: qi.toggle ? qi.highlighted : (root.qsKey === qi.key)

        Rectangle {
            anchors.fill: parent; anchors.margins: 2
            radius: ThemeManager.chipRadius
            color: qi.active
                ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, _ma.containsMouse ? 0.28 : 0.18)
                : (_ma.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Text {
            anchors.centerIn: parent
            text: qi.icon
            color: qi.active ? ThemeManager.primary : ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: 17
        }
        MouseArea {
            id: _ma; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (qi.toggle) { qi.activated(); return }
                root.qsKey = (root.qsKey === qi.key) ? "" : qi.key
            }
        }
    }

    // ── Profile ──────────────────────────────────────────────────────────────
    component ProfileCard: Rectangle {
        id: pc
        radius: ThemeManager.chipRadius + 4
        color:  ThemeManager.surfaceContainer
        implicitHeight: 92
        layer.enabled: true
        layer.effect: Elevation { level: 2 }

        property bool _hover: _pcHover.hovered

        RowLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 12

            ClippingRectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 52; height: 52; radius: 26
                color: ThemeManager.surfaceContainerHigh
                Image {
                    id: _face
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    source: root.homeDir !== "" ? "file://" + root.homeDir + "/.face" : ""
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: _face.status !== Image.Ready
                    text: "󰀄"
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 26
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: root.userName !== "" ? root.userName : "user"
                    color: ThemeManager.onSurface
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeLg; font.weight: Font.Bold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Fixed-height slot: uptime ↔ session buttons (no height jump on hover)
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 26

                    Text {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: !pc._hover
                        text: root.uptime !== "" ? "up " + root.uptime : ""
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: pc._hover
                        spacing: 4
                        MiniSession { Layout.fillWidth: true; icon: "󰌾"; onClicked: LockService.lock() }
                        MiniSession { Layout.fillWidth: true; icon: "󰒲"; onClicked: root._suspendProc.running = true }
                        MiniSession { Layout.fillWidth: true; icon: "󰍃"; danger: true; onClicked: root._confirmAction = "logout" }
                        MiniSession { Layout.fillWidth: true; icon: "󰑙"; danger: true; onClicked: root._confirmAction = "reboot" }
                        MiniSession { Layout.fillWidth: true; icon: "󰐥"; danger: true; onClicked: root._confirmAction = "shutdown" }
                    }
                }
            }
        }

        HoverHandler { id: _pcHover }
    }

    component MiniSession: Rectangle {
        id: ms
        property string icon: ""
        property bool danger: false
        signal clicked()
        implicitWidth: 26; implicitHeight: 26; radius: 6
        readonly property color _accent: danger ? ThemeManager.error : ThemeManager.primary
        color: _msHov.hovered
            ? Qt.rgba(_accent.r, _accent.g, _accent.b, 0.16)
            : ThemeManager.surfaceContainerHigh
        Text {
            anchors.centerIn: parent
            text: ms.icon
            color: _msHov.hovered ? ms._accent : ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: 13
        }
        HoverHandler { id: _msHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ms.clicked() }
    }

    // ── MPRIS controls ─────────────────────────────────────────────────────--
    component MprisCard: Rectangle {
        radius: ThemeManager.chipRadius + 4
        color:  ThemeManager.surfaceContainer
        layer.enabled: true
        layer.effect: Elevation { level: 2 }

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 8

            // Empty state
            Text {
                visible: !MprisService.hasPlayer
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                verticalAlignment: Text.AlignVCenter
                text: "No media"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
            }

            // Top spacer — balances the bottom one to center content vertically
            Item { visible: MprisService.hasPlayer; Layout.fillHeight: true }

            // Album art + circular progress
            Item {
                visible: MprisService.hasPlayer
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 110; implicitHeight: 110

                Canvas {
                    id: _ring
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        const cx = width/2, cy = height/2, r = 50, lw = 4
                        ctx.clearRect(0,0,width,height)
                        ctx.lineWidth = lw; ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.strokeStyle = Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.12)
                        ctx.arc(cx, cy, r, 0, 2*Math.PI); ctx.stroke()
                        ctx.beginPath()
                        ctx.strokeStyle = ThemeManager.primary
                        const s = -Math.PI/2
                        ctx.arc(cx, cy, r, s, s + 2*Math.PI*MprisService.progress); ctx.stroke()
                    }
                    Connections {
                        target: MprisService
                        function onProgressChanged() { _ring.requestPaint() }
                    }
                }

                ClippingRectangle {
                    anchors.centerIn: parent
                    width: 88; height: 88; radius: 44
                    color: ThemeManager.surfaceContainerHigh
                    Image {
                        id: _art
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: MprisService.artUrl
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: _art.status !== Image.Ready
                        text: "󰝚"
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 30
                    }
                }
            }

            Text {
                visible: MprisService.hasPlayer
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: MprisService.title
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                visible: MprisService.hasPlayer
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: MprisService.artist
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            RowLayout {
                visible: MprisService.hasPlayer
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                MprisBtn { icon: "󰒮"; enabled: MprisService.canPrev; onClicked: MprisService.previous() }
                MprisBtn { icon: MprisService.playing ? "󰏤" : "󰐊"; big: true; onClicked: MprisService.playPause() }
                MprisBtn { icon: "󰒭"; enabled: MprisService.canNext; onClicked: MprisService.next() }
            }

            Item { Layout.fillHeight: true }
        }
    }

    component MprisBtn: Rectangle {
        id: mb
        property string icon: ""
        property bool big: false
        signal clicked()
        width: big ? 40 : 32; height: big ? 40 : 32
        radius: width/2
        color: big
            ? (_mbMa.containsMouse ? ThemeManager.primary : Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.85))
            : (_mbMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.10) : "transparent")
        opacity: mb.enabled ? 1 : 0.35
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            anchors.centerIn: parent
            text: mb.icon
            color: mb.big ? ThemeManager.onPrimary : ThemeManager.onSurface
            font.family: ThemeManager.fontFamily
            font.pixelSize: mb.big ? 18 : 15
        }
        MouseArea {
            id: _mbMa; anchors.fill: parent
            enabled: mb.enabled
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: mb.clicked()
        }
    }

    // ── Weather ───────────────────────────────────────────────────────────────
    component WeatherCard: Rectangle {
        radius: ThemeManager.chipRadius + 4
        color:  ThemeManager.surfaceContainer
        implicitHeight: _wc.implicitHeight + 24
        layer.enabled: true
        layer.effect: Elevation { level: 2 }

        ColumnLayout {
            id: _wc
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            Text {
                visible: !WeatherService.ok
                text: "Weather unavailable"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
            }

            RowLayout {
                visible: WeatherService.ok
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: WeatherService.icon
                    color: ThemeManager.primary
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 32
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Text {
                        text: WeatherService.temp + WeatherService.unit
                        color: ThemeManager.onSurface
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 22; font.weight: Font.Bold
                    }
                    Text {
                        text: WeatherService.desc
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            Text {
                visible: WeatherService.ok
                text: WeatherService.location + "  ·  feels " + WeatherService.feels + "°  ·  " + WeatherService.humidity + "%"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                visible: WeatherService.ok && WeatherService.forecast.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 4
                Repeater {
                    model: WeatherService.forecast
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.day
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: 10
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.icon
                            color: ThemeManager.primary
                            font.family: ThemeManager.fontFamily; font.pixelSize: 14
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: WeatherService.conv(modelData.max) + "°/" + WeatherService.conv(modelData.min) + "°"
                            color: ThemeManager.onSurface
                            font.family: ThemeManager.fontFamily; font.pixelSize: 9
                        }
                    }
                }
            }
        }
    }

    // ── System metrics (vertical rings) ──────────────────────────────────────
    component MetricsCard: Rectangle {
        radius: ThemeManager.chipRadius + 4
        color:  ThemeManager.surfaceContainer
        layer.enabled: true
        layer.effect: Elevation { level: 2 }

        ColumnLayout {
            anchors { fill: parent; margins: 10 }
            spacing: ThemeManager.spacing

            Ring { Layout.fillWidth: true; label: "CPU";  frac: SystemMetricsService.cpu / 100; value: Math.round(SystemMetricsService.cpu) + "%" }
            Ring { Layout.fillWidth: true; label: "RAM";  frac: SystemMetricsService.ram / 100; value: Math.round(SystemMetricsService.ram) + "%" }
            Ring {
                Layout.fillWidth: true; label: "TEMP"
                frac:  SystemMetricsService.temp >= 0 ? Math.min(1, SystemMetricsService.temp / 100) : 0
                value: SystemMetricsService.temp >= 0 ? SystemMetricsService.temp + "°" : "—"
            }
            Item { Layout.fillHeight: true }
        }
    }

    component Ring: Item {
        id: ring
        property string label: ""
        property string value: ""
        property real   frac:  0
        implicitHeight: 64

        readonly property color _accent: frac > 0.85 ? ThemeManager.error : ThemeManager.primary

        Canvas {
            id: _cv
            width: 44; height: 44
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            onPaint: {
                const ctx = getContext("2d")
                const cx = width/2, cy = height/2, r = 18, lw = 4
                ctx.clearRect(0,0,width,height)
                ctx.lineWidth = lw; ctx.lineCap = "round"
                ctx.beginPath()
                ctx.strokeStyle = Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.12)
                ctx.arc(cx, cy, r, 0, 2*Math.PI); ctx.stroke()
                ctx.beginPath()
                ctx.strokeStyle = ring._accent
                const s = -Math.PI/2
                ctx.arc(cx, cy, r, s, s + 2*Math.PI*Math.max(0, Math.min(1, ring.frac))); ctx.stroke()
            }
            Connections { target: ring; function onFracChanged() { _cv.requestPaint() } }
            Component.onCompleted: requestPaint()
        }
        Text {
            anchors.centerIn: _cv
            text: ring.value
            color: ThemeManager.onSurface
            font.family: ThemeManager.fontFamily
            font.pixelSize: 10; font.weight: Font.Medium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: _cv.bottom; anchors.topMargin: 2
            text: ring.label
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily; font.pixelSize: 9
        }
    }

    // ── Calendar ─────────────────────────────────────────────────────────────
    component MonthCalendar: ColumnLayout {
        id: cal
        property var view: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
        spacing: 4

        readonly property var _today: root.now

        onViewChanged: CalendarService.loadMonth(view)
        Component.onCompleted: CalendarService.loadMonth(view)

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: cal.view.toLocaleDateString(root._fr, "MMMM yyyy")
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeMd; font.weight: Font.Medium
                Layout.fillWidth: true
            }
            CalNav { icon: "󰅁"; onClicked: cal.view = new Date(cal.view.getFullYear(), cal.view.getMonth() - 1, 1) }
            CalNav { icon: "󰅂"; onClicked: cal.view = new Date(cal.view.getFullYear(), cal.view.getMonth() + 1, 1) }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 2; columnSpacing: 2

            Repeater {
                model: ["Lu","Ma","Me","Je","Ve","Sa","Di"]
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 10; font.weight: Font.Medium
                    opacity: 0.7
                }
            }

            Repeater {
                model: 42
                delegate: Item {
                    id: _cell
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 26

                    readonly property var _cellDate: {
                        const first  = new Date(cal.view.getFullYear(), cal.view.getMonth(), 1)
                        const offset = (first.getDay() + 6) % 7
                        return new Date(first.getFullYear(), first.getMonth(), 1 - offset + index)
                    }
                    readonly property string _ds: Qt.formatDate(_cellDate, "yyyy-MM-dd")
                    readonly property bool _inMonth: _cellDate.getMonth() === cal.view.getMonth()
                    readonly property bool _isToday:
                        _cellDate.getFullYear() === cal._today.getFullYear() &&
                        _cellDate.getMonth()    === cal._today.getMonth()    &&
                        _cellDate.getDate()     === cal._today.getDate()
                    // Touch eventsByDate so dots re-evaluate when events load
                    readonly property bool _hasEv: {
                        const _ = CalendarService.eventsByDate
                        return CalendarService.hasEvents(_ds)
                    }
                    readonly property bool _selected: root.calSelectedDate === _ds

                    Rectangle {
                        anchors.centerIn: parent
                        width: 24; height: 24; radius: 12
                        color: _cell._isToday ? ThemeManager.primary
                             : (_cell._selected ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.18)
                             : (_cellMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent"))
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: _cell._cellDate.getDate()
                        color: _cell._isToday
                            ? ThemeManager.onPrimary
                            : (_cell._inMonth ? ThemeManager.onSurface : ThemeManager.onSurfaceVariant)
                        opacity: _cell._inMonth ? 1.0 : 0.35
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                    }
                    // Event dot
                    Rectangle {
                        visible: _cell._hasEv
                        width: 4; height: 4; radius: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        color: _cell._isToday ? ThemeManager.onPrimary : ThemeManager.primary
                    }
                    MouseArea {
                        id: _cellMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.calSelectedDate = _cell._ds
                    }
                }
            }
        }
    }

    component CalNav: Item {
        property string icon: ""
        signal clicked()
        implicitWidth: 22; implicitHeight: 22
        Rectangle {
            anchors.fill: parent; radius: 6
            color: _ma.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent"
            Behavior on color { ColorAnimation { duration: 80 } }
        }
        Text {
            anchors.centerIn: parent
            text: parent.icon
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily; font.pixelSize: 14
        }
        MouseArea {
            id: _ma; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    // ── Vertical M3 slider (brightness flyout) ───────────────────────────────
    component VertSlider: ColumnLayout {
        id: vs
        property string icon:  ""
        property string label: ""
        property real   value: 0          // 0..1
        signal moved(real frac)

        readonly property int _trackW: 6
        readonly property int _thumbR: 10
        readonly property int _trackH: 150

        spacing: ThemeManager.spacing

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: vs.label
            color: ThemeManager.onSurface
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
        }

        Item {
            id: _body
            Layout.alignment: Qt.AlignHCenter
            implicitWidth:  vs._thumbR * 4
            implicitHeight: vs._trackH + vs._thumbR * 2

            readonly property real frac:    Math.max(0, Math.min(1, vs.value))
            readonly property real thumbCY: vs._thumbR + (1.0 - frac) * (vs._trackH - vs._thumbR * 2)

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: vs._thumbR; width: vs._trackW; height: vs._trackH
                radius: vs._trackW / 2
                color: ThemeManager.surfaceContainerHigh
                clip: true
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: _body.frac * vs._trackH
                    color: ThemeManager.primary
                    Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: _body.thumbCY - vs._thumbR
                width: vs._thumbR * 2; height: vs._thumbR * 2
                radius: vs._thumbR
                color: ThemeManager.primary
                Behavior on y { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function applyY(y) {
                    const cy   = Math.max(vs._thumbR, Math.min(vs._thumbR + vs._trackH, y))
                    const frac = 1.0 - (cy - vs._thumbR) / vs._trackH
                    vs.moved(Math.max(0, Math.min(1, frac)))
                }
                onPressed:         (ev) => applyY(ev.y)
                onPositionChanged: (ev) => { if (pressed) applyY(ev.y) }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: vs.icon
            color: ThemeManager.primary
            font.family: ThemeManager.fontFamily
            font.pixelSize: 16
        }
    }

    // ── Shared slider (horizontal) ───────────────────────────────────────────
    component DashSlider: Item {
        id: sl
        property string icon:  ""
        property real   value: 0
        signal moved(real frac)
        implicitHeight: 28

        Text {
            id: _ic
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: sl.icon
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily; font.pixelSize: 16
        }
        Rectangle {
            id: _track
            anchors { left: _ic.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 6; radius: 3
            color: ThemeManager.surfaceContainerHigh
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: Math.max(6, parent.width * Math.max(0, Math.min(1, sl.value)))
                radius: 3
                color: ThemeManager.primary
                Behavior on width { NumberAnimation { duration: 60 } }
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                function apply(x) { sl.moved(Math.max(0, Math.min(1, (x + 8) / _track.width))) }
                onPressed:         (e) => apply(e.x)
                onPositionChanged: (e) => { if (pressed) apply(e.x) }
            }
        }
    }
}
