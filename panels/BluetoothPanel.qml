import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Bluetooth
import "../theme"
import "../services"

// In-shell Bluetooth manager (replaces blueman-manager). Adapter toggle + scan,
// and per-device: connect/disconnect, pair, trust, forget, rename, battery, plus
// audio-profile switching (A2DP ↔ headset) via wpctl when present. Device rows
// expand to reveal their controls; one open at a time.
Item {
    id: root

    implicitWidth:  300
    implicitHeight: Math.min(_col.implicitHeight + 16, 460)

    readonly property var  adapter:   Bluetooth.defaultAdapter
    readonly property bool btEnabled: adapter?.enabled ?? false
    readonly property bool _wpctl:    DependencyService.available("wpctl")

    readonly property bool active: PopoutService.currentName === "bluetooth"
    property string expandedAddr: ""
    onActiveChanged: if (!active) { expandedAddr = ""; if (adapter) adapter.discovering = false }

    function _toggleExpand(addr, connected) {
        expandedAddr = (expandedAddr === addr) ? "" : addr
        if (expandedAddr === addr && connected && _wpctl) _queryProfiles(addr)
        else _profiles = []
    }

    // ── Audio profiles (pw-dump to read, wpctl to set) ────────────────────────
    property var    _profiles:    []   // [{ index, desc, active }]
    property int    _profilePwId: -1
    property string _profileAddr: ""

    function _cardName(addr) { return "bluez_card." + ("" + addr).replace(/:/g, "_") }

    function _queryProfiles(addr) {
        _profileAddr = addr
        _profiles    = []
        _profilePwId = -1
        _profileProc.running = false
        _profileProc.running = true
    }
    property Process _profileProc: Process {
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr
                try { arr = JSON.parse(text) } catch (e) { return }
                const want = root._cardName(root._profileAddr)
                for (const o of arr) {
                    if (o.type !== "PipeWire:Interface:Device") continue
                    const props = (o.info && o.info.props) || {}
                    if (props["device.name"] !== want) continue
                    const params = (o.info && o.info.params) || {}
                    const active = (params.Profile && params.Profile[0] && params.Profile[0].index)
                    const list = []
                    for (const p of (params.EnumProfile || [])) {
                        if (p.available && p.available !== "yes") continue
                        list.push({ index: p.index, desc: p.description || p.name, active: p.index === active })
                    }
                    root._profilePwId = o.id
                    root._profiles    = list
                    break
                }
            }
        }
    }
    property Process _setProfileProc: Process { running: false }
    function _setProfile(index) {
        if (_profilePwId < 0) return
        _setProfileProc.command = ["wpctl", "set-profile", "" + _profilePwId, "" + index]
        _setProfileProc.running = false
        _setProfileProc.running = true
        _profileReQuery.restart()
    }
    property Timer _profileReQuery: Timer {
        interval: 700; onTriggered: root._queryProfiles(root._profileAddr)
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

            // ── Header: title + scan + power ──────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Bluetooth"
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
                    Layout.fillWidth: true
                }
                // Scan toggle
                Rectangle {
                    id: _scanBtn
                    visible: root.btEnabled
                    implicitWidth: 24; implicitHeight: 20; radius: ThemeManager.chipRadius
                    readonly property bool _on: root.adapter?.discovering ?? false
                    color: _on ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.2)
                               : (_scanMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                    Text {
                        anchors.centerIn: parent
                        text: "󰜉"   // refresh/scan glyph
                        color: _scanBtn._on ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily; font.pixelSize: 13
                        RotationAnimation on rotation {
                            running: _scanBtn._on; from: 0; to: 360; duration: 1400; loops: Animation.Infinite
                        }
                    }
                    MouseArea {
                        id: _scanMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.adapter) root.adapter.discovering = !root.adapter.discovering
                    }
                }
                // Power pill
                Rectangle {
                    width: 36; height: 20; radius: 10
                    color: root.btEnabled ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Rectangle {
                        width: 16; height: 16; radius: 8; y: 2; x: root.btEnabled ? 18 : 2
                        color: root.btEnabled ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { const a = root.adapter; if (a) a.enabled = !a.enabled }
                    }
                }
            }

            Text {
                visible: !root.btEnabled
                text: "Adapter off"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                opacity: 0.6
                Layout.topMargin: 4
            }

            // ── Devices ───────────────────────────────────────────────────────
            Repeater {
                model: root.btEnabled ? (Bluetooth.devices?.values ?? []) : []
                delegate: ColumnLayout {
                    id: _dev
                    required property var modelData
                    readonly property string _addr: "" + modelData.address
                    readonly property bool _exp: root.expandedAddr === _addr
                    Layout.fillWidth: true
                    spacing: 2

                    // Header row
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: ThemeManager.chipRadius
                        color: _dev.modelData.connected
                            ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, _dev._exp ? 0.2 : 0.13)
                            : (_devMa.containsMouse || _dev._exp ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                        Behavior on color { ColorAnimation { duration: 100 } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 8
                            Text {
                                text: _dev.modelData.connected ? "󰂱" : "󰂯"
                                color: _dev.modelData.connected ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 14
                            }
                            Text {
                                Layout.fillWidth: true
                                text: (_dev.modelData.name && _dev.modelData.name !== "")
                                      ? _dev.modelData.name
                                      : (_dev.modelData.deviceName || _dev._addr)
                                color: _dev.modelData.connected ? ThemeManager.primary : ThemeManager.onSurface
                                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                elide: Text.ElideRight
                            }
                            // Battery (if reported)
                            Text {
                                visible: _dev.modelData.connected && (_dev.modelData.batteryAvailable ?? false)
                                text: Math.round((_dev.modelData.battery ?? 0) * 100) + "%"
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 10
                            }
                            Text {
                                visible: !_dev.modelData.connected && _dev.modelData.paired
                                text: "Paired"
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 10
                            }
                        }
                        MouseArea {
                            id: _devMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root._toggleExpand(_dev._addr, _dev.modelData.connected)
                        }
                    }

                    // Expanded controls
                    ColumnLayout {
                        visible: _dev._exp
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 4
                        Layout.bottomMargin: 6
                        spacing: 5

                        // Rename
                        Rectangle {
                            Layout.fillWidth: true; Layout.topMargin: 4
                            implicitHeight: 30
                            radius: ThemeManager.chipRadius
                            color: ThemeManager.surfaceContainer
                            border.width: _nameField.activeFocus ? 1 : 0
                            border.color: ThemeManager.primary
                            TextInput {
                                id: _nameField
                                anchors { fill: parent; leftMargin: 10; rightMargin: 34 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: ThemeManager.onSurface
                                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                clip: true
                                text: _dev.modelData.name || _dev.modelData.deviceName || ""
                                onActiveFocusChanged: PopoutService.keyboardActive = activeFocus
                                onAccepted: { _dev.modelData.name = text; focus = false }
                            }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 8 }
                                text: "󰸞"   // apply
                                color: ThemeManager.primary
                                font.family: ThemeManager.fontFamily; font.pixelSize: 15
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                    onClicked: { _dev.modelData.name = _nameField.text; _nameField.focus = false }
                                }
                            }
                        }

                        // Address
                        Text {
                            text: _dev._addr + (_dev.modelData.icon ? "  ·  " + _dev.modelData.icon : "")
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: 10
                            opacity: 0.7
                        }

                        // Audio profiles (connected + wpctl)
                        ColumnLayout {
                            visible: _dev._exp && _dev.modelData.connected && root._wpctl
                                     && root._profiles.length > 0
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Audio profile"
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 10; font.weight: Font.Medium
                                Layout.topMargin: 2
                            }
                            Repeater {
                                model: root._profiles
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: ThemeManager.chipRadius
                                    color: modelData.active
                                        ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.18)
                                        : (_profMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.desc
                                            color: modelData.active ? ThemeManager.primary : ThemeManager.onSurface
                                            font.family: ThemeManager.fontFamily; font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: modelData.active
                                            text: "󰄬"
                                            color: ThemeManager.primary
                                            font.family: ThemeManager.fontFamily; font.pixelSize: 12
                                        }
                                    }
                                    MouseArea {
                                        id: _profMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root._setProfile(modelData.index)
                                    }
                                }
                            }
                        }

                        // Action buttons
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 4
                            BtBtn {
                                text: _dev.modelData.connected ? "Disconnect" : "Connect"
                                onClicked: _dev.modelData.connected ? _dev.modelData.disconnect() : _dev.modelData.connect()
                            }
                            BtBtn {
                                text: "Trust"
                                accent: _dev.modelData.trusted
                                onClicked: _dev.modelData.trusted = !_dev.modelData.trusted
                            }
                            BtBtn {
                                visible: _dev.modelData.paired || _dev.modelData.bonded
                                text: "Forget"
                                danger: true
                                onClicked: { _dev.modelData.forget(); root.expandedAddr = "" }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }

    // Small action button.
    component BtBtn: Rectangle {
        id: bb
        property string text: ""
        property bool   danger: false
        property bool   accent: false
        signal clicked()
        implicitWidth:  _bbLabel.implicitWidth + 18
        implicitHeight: 28
        radius: ThemeManager.chipRadius
        readonly property color _col: danger ? ThemeManager.error : ThemeManager.primary
        color: (accent)
            ? Qt.rgba(bb._col.r, bb._col.g, bb._col.b, _bbMa.containsMouse ? 0.30 : 0.20)
            : (_bbMa.containsMouse ? Qt.rgba(bb._col.r, bb._col.g, bb._col.b, 0.22)
                                   : Qt.rgba(bb._col.r, bb._col.g, bb._col.b, 0.12))
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            id: _bbLabel
            anchors.centerIn: parent
            text: bb.text
            color: bb._col
            font.family: ThemeManager.fontFamily; font.pixelSize: 11
        }
        MouseArea {
            id: _bbMa; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: bb.clicked()
        }
    }
}
