import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

// Floating right-click context menu for a network or bluetooth device. Rendered
// top-level by MainWindow at the cursor; reads its target from ContextMenuService.
Rectangle {
    id: root

    readonly property var    target: ContextMenuService.target
    readonly property string kind:   ContextMenuService.kind

    implicitWidth:  210
    implicitHeight: _col.implicitHeight + 10
    radius: ThemeManager.panelRadius
    color:  ThemeManager.surfaceContainerHigh
    border.width: 1
    border.color: Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.1)

    // Reset the password field whenever a new menu opens.
    Connections {
        target: ContextMenuService
        function onOpenChanged() { if (ContextMenuService.open) _psk.text = "" }
    }

    ColumnLayout {
        id: _col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5 }
        spacing: 2

        // ── Title ─────────────────────────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            Layout.margins: 5
            Layout.bottomMargin: 2
            text: {
                if (!root.target) return ""
                if (root.kind === "wifi") return "" + root.target.name
                return root.target.name || root.target.deviceName || ("" + root.target.address)
            }
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: 10; font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: ThemeManager.outlineVariant; opacity: 0.3 }

        // ══════════════════ Wi-Fi ══════════════════
        // Connect / Disconnect
        MenuItem {
            visible: root.kind === "wifi" && root.target
            icon: root.target?.connected ? "󰖪" : "󰖩"
            label: root.target?.connected ? "Disconnect" : "Connect"
            // Unknown secured networks need a password (entered below) — for those
            // the Connect row is hidden and the user uses the field.
            enabled: root.target?.connected || root.target?.known
            onTriggered: {
                if (root.target.connected) root.target.disconnect()
                else root.target.connect()
                ContextMenuService.close()
            }
        }
        // Password entry for an unknown secured network
        ColumnLayout {
            visible: root.kind === "wifi" && root.target && !root.target.connected && !root.target.known
            Layout.fillWidth: true
            spacing: 2
            Rectangle {
                Layout.fillWidth: true; Layout.margins: 3
                implicitHeight: 30
                radius: ThemeManager.chipRadius
                color: ThemeManager.surfaceContainer
                border.width: _psk.activeFocus ? 1 : 0
                border.color: ThemeManager.primary
                TextInput {
                    id: _psk
                    anchors { fill: parent; leftMargin: 10; rightMargin: 30 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: ThemeManager.onSurface
                    font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                    echoMode: _reveal.checked ? TextInput.Normal : TextInput.Password
                    clip: true
                    onActiveFocusChanged: PopoutService.keyboardActive = activeFocus
                    onAccepted: if (root.target) { root.target.connectWithPsk(text); ContextMenuService.close() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: _psk.text === ""
                        text: "Password"; color: ThemeManager.onSurfaceVariant; opacity: 0.5
                        font: _psk.font
                    }
                }
                Text {
                    id: _reveal
                    property bool checked: false
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 8 }
                    text: checked ? "󰈉" : "󰈈"
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: _reveal.checked = !_reveal.checked }
                }
            }
            MenuItem {
                icon: "󰖩"; label: "Connect"
                onTriggered: if (root.target) { root.target.connectWithPsk(_psk.text); ContextMenuService.close() }
            }
        }
        MenuItem {
            visible: root.kind === "wifi" && root.target?.known
            icon: "󰆴"; label: "Forget"; danger: true
            onTriggered: { root.target.forget(); ContextMenuService.close() }
        }

        // ══════════════════ Bluetooth ══════════════════
        MenuItem {
            visible: root.kind === "bt" && root.target
            icon: root.target?.connected ? "󰂲" : "󰂱"
            label: root.target?.connected ? "Disconnect" : "Connect"
            onTriggered: {
                root.target.connected ? root.target.disconnect() : root.target.connect()
                ContextMenuService.close()
            }
        }
        MenuItem {
            visible: root.kind === "bt" && root.target
            icon: root.target?.trusted ? "󰄬" : "󰒙"
            label: root.target?.trusted ? "Trusted" : "Trust"
            onTriggered: { root.target.trusted = !root.target.trusted }
        }
        // Rename
        Rectangle {
            visible: root.kind === "bt" && root.target
            Layout.fillWidth: true; Layout.margins: 3
            implicitHeight: 30
            radius: ThemeManager.chipRadius
            color: ThemeManager.surfaceContainer
            border.width: _rename.activeFocus ? 1 : 0
            border.color: ThemeManager.primary
            TextInput {
                id: _rename
                anchors { fill: parent; leftMargin: 10; rightMargin: 30 }
                verticalAlignment: TextInput.AlignVCenter
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                clip: true
                text: (root.kind === "bt" && root.target) ? (root.target.name || root.target.deviceName || "") : ""
                onActiveFocusChanged: PopoutService.keyboardActive = activeFocus
                onAccepted: if (root.target) { root.target.name = text; focus = false }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 8 }
                text: "󰸞"; color: ThemeManager.primary
                font.family: ThemeManager.fontFamily; font.pixelSize: 15
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.target) { root.target.name = _rename.text; _rename.focus = false } }
            }
        }
        // Audio profiles
        Text {
            visible: root.kind === "bt" && root.target?.connected && ContextMenuService._profiles.length > 0
            Layout.fillWidth: true; Layout.leftMargin: 5; Layout.topMargin: 2
            text: "Audio profile"
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily; font.pixelSize: 9; font.weight: Font.Medium
        }
        Repeater {
            model: (root.kind === "bt" && root.target?.connected) ? ContextMenuService._profiles : []
            delegate: MenuItem {
                required property var modelData
                icon: modelData.active ? "󰄬" : "  "
                label: modelData.desc
                small: true
                highlight: modelData.active
                onTriggered: ContextMenuService.setProfile(modelData.index)
            }
        }
        MenuItem {
            visible: root.kind === "bt" && (root.target?.paired || root.target?.bonded)
            icon: "󰆴"; label: "Forget"; danger: true
            onTriggered: { root.target.forget(); ContextMenuService.close() }
        }
    }

    // ── Menu item ─────────────────────────────────────────────────────────────
    component MenuItem: Rectangle {
        id: mi
        property string icon:  ""
        property string label: ""
        property bool   danger: false
        property bool   highlight: false
        property bool   small: false
        property bool   enabled: true
        signal triggered()
        Layout.fillWidth: true
        implicitHeight: mi.small ? 26 : 30
        radius: ThemeManager.chipRadius
        readonly property color _accent: danger ? ThemeManager.error : ThemeManager.primary
        color: highlight
            ? Qt.rgba(_accent.r, _accent.g, _accent.b, 0.18)
            : (_miMa.containsMouse && mi.enabled ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
        opacity: mi.enabled ? 1 : 0.4
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 8
            Text {
                text: mi.icon
                color: mi.danger ? ThemeManager.error : (mi.highlight ? ThemeManager.primary : ThemeManager.onSurfaceVariant)
                font.family: ThemeManager.fontFamily; font.pixelSize: mi.small ? 12 : 14
            }
            Text {
                Layout.fillWidth: true
                text: mi.label
                color: mi.danger ? ThemeManager.error : (mi.highlight ? ThemeManager.primary : ThemeManager.onSurface)
                font.family: ThemeManager.fontFamily; font.pixelSize: mi.small ? 11 : ThemeManager.fontSizeSm
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: _miMa; anchors.fill: parent
            enabled: mi.enabled
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: mi.triggered()
        }
    }
}
