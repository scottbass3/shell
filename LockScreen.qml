import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "./theme"
import "./services"
import "./widgets/lock"

// Custom session lock. State 1: wallpaper + clock/date (left) + weather (bottom-right).
// State 2 (click / key): background blurs and a password prompt appears, with
// keyboard layout, battery and power buttons along the bottom.
WlSessionLock {
    id: lock
    locked: LockService.locked

    WlSessionLockSurface {
        id: surf
        color: "black"

        property bool showPrompt: false
        property bool showPassword: false
        property string power: ""      // power action awaiting confirmation
        property var  now: new Date()
        readonly property var _fr: Qt.locale("fr_FR")

        readonly property var _powerActions: [
            { id: "suspend",  icon: "󰒲", label: "Mettre en veille", confirm: "Mettre l'ordinateur en veille ?" },
            { id: "reboot",   icon: "󰜉", label: "Redémarrer",       confirm: "Redémarrer l'ordinateur ?" },
            { id: "poweroff", icon: "󰐥", label: "Éteindre",         confirm: "Éteindre l'ordinateur ?" }
        ]
        readonly property var _pending: _powerActions.find(a => a.id === power) ?? null

        Timer { interval: 1000; running: true; repeat: true; onTriggered: surf.now = new Date() }

        function reveal() {
            if (!showPrompt) showPrompt = true
            _pwInput.forceActiveFocus()
        }
        function hidePrompt() {
            showPrompt = false
            showPassword = false
            power = ""
            _pwInput.text = ""
            _idleKeys.forceActiveFocus()
        }
        function runPower() {
            const id = power
            power = ""
            Quickshell.execDetached(["systemctl", id])
        }

        // Reset to idle whenever the lock toggles
        Connections {
            target: LockService
            function onLockedChanged() { if (!LockService.locked) { surf.showPrompt = false; surf.power = ""; _pwInput.text = "" } }
            function onBusyChanged()   { if (!LockService.busy && LockService.locked) { _pwInput.text = ""; _pwInput.forceActiveFocus() } }
        }

        // ── Wallpaper (sharp) ─────────────────────────────────────────────────
        Image {
            id: _wall
            anchors.fill: parent
            source:   LockService.wallpaper
            fillMode: Image.PreserveAspectCrop
            cache:    true
        }

        // ── Blurred overlay (fades in with prompt) ────────────────────────────
        MultiEffect {
            anchors.fill: parent
            source:        _wall
            blurEnabled:   true
            blur:          1.0
            blurMax:       64
            autoPaddingEnabled: false
            opacity:       surf.showPrompt ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            anchors.fill: parent
            color:   "black"
            opacity: surf.showPrompt ? 0.45 : 0.0
            Behavior on opacity { NumberAnimation { duration: 280 } }
        }

        // ── Idle: clock + date (left, vertically centered) ────────────────────
        Column {
            anchors {
                left: parent.left; leftMargin: 80
                verticalCenter: parent.verticalCenter
            }
            spacing: 0
            opacity: surf.showPrompt ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 260 } }

            Text {
                text: surf.now.toLocaleTimeString(surf._fr, "HH:mm")
                color: "white"
                font.family: ThemeManager.fontFamily
                font.pixelSize: 120
                font.weight: Font.Bold
            }
            Text {
                text: surf.now.toLocaleDateString(surf._fr, "dddd, d MMMM yyyy")
                color: "white"
                opacity: 0.85
                font.family: ThemeManager.fontFamily
                font.pixelSize: 26
            }
        }

        // ── Idle: weather (bottom-right) ──────────────────────────────────────
        Row {
            anchors {
                right: parent.right; rightMargin: 80
                bottom: parent.bottom; bottomMargin: 70
            }
            spacing: 16
            visible: WeatherService.ok
            opacity: surf.showPrompt ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 260 } }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: WeatherService.icon
                color: "white"
                font.family: ThemeManager.fontFamily
                font.pixelSize: 56
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    text: WeatherService.temp + WeatherService.unit
                    color: "white"
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 40; font.weight: Font.Bold
                }
                Text {
                    text: WeatherService.desc + "  ·  " + WeatherService.location
                    color: "white"; opacity: 0.85
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 18
                }
            }
        }

        // ── Prompt (centered, appears on reveal) ──────────────────────────────
        Column {
            anchors.centerIn: parent
            spacing: 18
            opacity: surf.showPrompt ? 1.0 : 0.0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            // Avatar: ~/.face if present, else a glyph
            ClippingRectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96; radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.12)
                Image {
                    id: _face
                    anchors.fill: parent
                    source: {
                        const h = Quickshell.env("HOME")
                        return h ? "file://" + h + "/.face" : ""
                    }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: _face.status !== Image.Ready
                    text: "󰀄"
                    color: "white"
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 64
                }
            }

            // Username under the avatar
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: LockService.userName
                visible: LockService.userName !== ""
                color: "white"
                font.family: ThemeManager.fontFamily
                font.pixelSize: 20; font.weight: Font.Medium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: surf.now.toLocaleTimeString(surf._fr, "HH:mm")
                color: "white"
                font.family: ThemeManager.fontFamily
                font.pixelSize: 34; font.weight: Font.Medium
            }

            // Password box
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300; height: 44
                radius: 22
                color: Qt.rgba(1, 1, 1, 0.12)
                border.width: LockService.busy ? 0 : 1
                border.color: LockService.error !== "" ? ThemeManager.error : Qt.rgba(1, 1, 1, 0.25)

                TextInput {
                    id: _pwInput
                    anchors { fill: parent; leftMargin: 18; rightMargin: 46 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: "white"
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 18
                    echoMode: surf.showPassword ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    enabled: !LockService.busy
                    clip: true
                    onAccepted: { if (surf.power !== "") surf.runPower(); else LockService.submit(text) }
                    Keys.onEscapePressed: { if (surf.power !== "") surf.power = ""; else surf.hidePrompt() }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: _pwInput.text === "" && !LockService.busy
                        text: "Mot de passe"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font: _pwInput.font
                    }
                }

                // Busy spinner dots
                Text {
                    anchors.centerIn: parent
                    visible: LockService.busy
                    text: "Vérification…"
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 16
                }

                // Show / hide the password
                Text {
                    visible: !LockService.busy
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: surf.showPassword ? "󰈉" : "󰈈"
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 18
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { surf.showPassword = !surf.showPassword; _pwInput.forceActiveFocus() }
                    }
                }
            }

            // Messages get a fixed space, so the prompt doesn't move when they show.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 340; height: 48
                Column {
                    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: KeyboardService.capsLock
                        text: "󰪛  Verr. Maj activé"
                        color: ThemeManager.primary
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 14
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: LockService.error
                        visible: LockService.error !== ""
                        color: ThemeManager.error
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 14
                    }
                }
            }
        }

        // ── Prompt: bottom bar (keyboard layout, battery, power) ──────────────
        Item {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 32 }
            height: 44
            opacity: surf.showPrompt ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 280 } }

            Text {
                anchors.centerIn: parent
                text: "Échap pour revenir"
                color: "white"
                opacity: 0.6
                font.family: ThemeManager.fontFamily
                font.pixelSize: 12
            }

            Row {
                anchors.right: parent.right
                spacing: 8
                LockPill {
                    visible: KeyboardService.available && KeyboardService.layout !== ""
                    icon: "󰌌"
                    label: KeyboardService.layout
                    tip: KeyboardService.multiple ? "Disposition suivante" : "Disposition du clavier"
                    onClicked: { if (KeyboardService.multiple) KeyboardService.next(); _pwInput.forceActiveFocus() }
                }
                LockPill {
                    visible: BatteryService.present && BatteryService.pct >= 0
                    icon: BatteryService.charging ? "󰂄"
                        : ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"][Math.min(9, Math.floor(Math.max(0, BatteryService.pct) / 10))]
                    label: BatteryService.pct + "%"
                    tip: BatteryService.charging ? "En charge" : "Batterie"
                }
                Repeater {
                    model: surf._powerActions
                    delegate: LockPill {
                        required property var modelData
                        icon: modelData.icon
                        tip: modelData.label
                        onClicked: { surf.power = modelData.id; _pwInput.forceActiveFocus() }
                    }
                }
            }
        }

        // ── Power confirmation ────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            visible: surf.power !== ""
            color: Qt.rgba(0, 0, 0, 0.45)
            z: 10
            MouseArea { anchors.fill: parent; onClicked: { surf.power = ""; _pwInput.forceActiveFocus() } }

            Rectangle {
                anchors.centerIn: parent
                width: 380
                height: _confirmCol.implicitHeight + 44
                radius: ThemeManager.panelRadius + 4
                color: ThemeManager.surfaceContainerHigh
                border.width: 1
                border.color: ThemeManager.outlineVariant
                MouseArea { anchors.fill: parent }

                Column {
                    id: _confirmCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                    spacing: 18
                    Row {
                        spacing: 12
                        Text {
                            text: surf._pending?.icon ?? ""
                            color: ThemeManager.primary
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: 24
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: surf._pending?.confirm ?? ""
                            color: ThemeManager.onSurface
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeLg
                            font.weight: Font.DemiBold
                        }
                    }
                    Text {
                        text: "Entrée confirme, Échap annule."
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeXs
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        LockDialogButton { label: "Annuler"; onClicked: { surf.power = ""; _pwInput.forceActiveFocus() } }
                        LockDialogButton { label: surf._pending?.label ?? ""; strong: true; onClicked: surf.runPower() }
                    }
                }
            }
        }

        // ── Reveal triggers ───────────────────────────────────────────────────
        MouseArea {
            anchors.fill: parent
            enabled: !surf.showPrompt
            onClicked: surf.reveal()
        }

        // Keyboard focus catcher (idle). Any key reveals the prompt; a printable
        // character also seeds the password field so typing starts immediately
        // (non-printable keys — modifiers, Enter, Escape… — only reveal).
        Item {
            id: _idleKeys
            anchors.fill: parent
            focus: !surf.showPrompt
            Keys.onPressed: (e) => {
                surf.reveal()
                if (e.text.length === 1 && e.text.charCodeAt(0) >= 0x20)
                    _pwInput.text += e.text
                e.accepted = true
            }
        }
    }
}
