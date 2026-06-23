import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "./theme"
import "./services"

// Custom session lock. State 1: wallpaper + clock/date (left) + weather (bottom-right).
// State 2 (click / key): background blurs and a password prompt appears.
WlSessionLock {
    id: lock
    locked: LockService.locked

    WlSessionLockSurface {
        id: surf
        color: "black"

        property bool showPrompt: false
        property var  now: new Date()
        readonly property var _fr: Qt.locale("fr_FR")

        Timer { interval: 1000; running: true; repeat: true; onTriggered: surf.now = new Date() }

        function reveal() {
            if (!showPrompt) showPrompt = true
            _pwInput.forceActiveFocus()
        }

        // Reset to idle whenever the lock toggles
        Connections {
            target: LockService
            function onLockedChanged() { if (!LockService.locked) { surf.showPrompt = false; _pwInput.text = "" } }
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

            // Avatar circle (optional flair)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰀄"
                color: "white"
                font.family: ThemeManager.fontFamily
                font.pixelSize: 64
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
                    anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: "white"
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 18
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    enabled: !LockService.busy
                    clip: true
                    onAccepted: LockService.submit(text)

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

        // ── Reveal triggers ───────────────────────────────────────────────────
        MouseArea {
            anchors.fill: parent
            enabled: !surf.showPrompt
            onClicked: surf.reveal()
        }

        // Keyboard focus catcher (idle). Any key reveals the prompt.
        Item {
            anchors.fill: parent
            focus: !surf.showPrompt
            Keys.onPressed: (e) => { surf.reveal(); e.accepted = true }
        }
    }
}
