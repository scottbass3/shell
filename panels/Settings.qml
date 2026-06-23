import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Services.SystemTray
import "../theme"
import "../services"

// Settings window — centered modal (standalone per-screen window, shown on the
// focused monitor). Sidebar categories + scrollable pane. Live-applies +
// persists via SettingsService; opt-in features dependency-checked.
PanelWindow {
    id: root
    required property var modelData

    readonly property bool active:
        SettingsUi.open && SettingsUi.screenName === modelData?.name

    screen:        modelData
    visible:       active || _exiting
    color:         "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors        { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property bool _exiting: false
    onActiveChanged: { if (active) _exiting = false; else if (visible) { _exiting = true; _exitTimer.restart() } }
    Timer { id: _exitTimer; interval: 180; onTriggered: root._exiting = false }

    // ── Tray config helpers (defaults mirror Tray.qml) ────────────────────────
    readonly property var _trayHiddenDef: ["nm-applet", "blueman", "slimbookintelcontrollerindicator.py",
        "Wayland to X11 Video bridge", "Gestionnaire de paramètres de Manjaro"]
    readonly property var _traySpecialDef: [
        { match: "spotify", ws: "spotify" }, { match: "youtube", ws: "ytmusic" },
        { match: "rocket", ws: "rocketchat" }, { match: "vesktop", ws: "vesktop" },
        { match: "discord", ws: "vesktop" }, { match: "vencord", ws: "vesktop" }]

    function _trayHay(item) { return ((item.id ?? "") + " " + (item.title ?? "") + " " + (item.tooltipTitle ?? "")).toLowerCase() }
    function _trayHidden() { return SettingsService.get("tray.hidden", _trayHiddenDef) }
    function _trayIsHidden(item) { const h = _trayHay(item); return _trayHidden().some(x => h.includes(String(x).toLowerCase())) }
    function _trayToggleHide(item) {
        const h = _trayHay(item)
        let a = _trayHidden().slice()
        if (_trayIsHidden(item)) a = a.filter(x => !h.includes(String(x).toLowerCase()))
        else a.push((item.title && item.title !== "") ? item.title : (item.id ?? ""))
        SettingsService.set("tray.hidden", a)
    }
    function _traySpecial() { return SettingsService.get("tray.specialWs", _traySpecialDef) }
    function _trayWs(item) { const h = _trayHay(item); const e = _traySpecial().find(x => h.includes(String(x.match).toLowerCase())); return e ? e.ws : "" }
    // Most specific identifier: electron apps share id "chrome_status_icon_1",
    // so prefer the (unique) tooltip title, then title, then id.
    function _trayKey(item) {
        const tt = item.tooltipTitle ?? "", t = item.title ?? "", id = item.id ?? ""
        return (tt !== "" ? tt : (t !== "" ? t : id)).toLowerCase()
    }
    function _traySetWs(item, ws) {
        const key = _trayKey(item)
        let m = _traySpecial().filter(x => String(x.match).toLowerCase() !== key)
        if (ws && ws.trim() !== "") m.push({ match: key, ws: ws.trim() })
        SettingsService.set("tray.specialWs", m)
    }

    // Custom (non-SNI) tray entries: [{name, icon, action:"run"|"ws", value}]
    readonly property var _trayCustomList: SettingsService.get("tray.custom", [])
    property int _trayEditIdx: -1   // which entry is expanded for editing (-1 = none)
    function _trayCustom() { return SettingsService.get("tray.custom", []) }
    function _trayCustomAdd() {
        let a = _trayCustom().slice()
        a.push({ name: "App", icon: "application-x-executable", action: "run", value: "" })
        SettingsService.set("tray.custom", a)
        _trayEditIdx = a.length - 1   // open the new entry for editing
    }
    function _trayCustomSet(i, field, val) {
        let a = _trayCustom().slice()
        if (i < 0 || i >= a.length) return
        let e = Object.assign({}, a[i]); e[field] = val; a[i] = e
        SettingsService.set("tray.custom", a)
    }
    function _trayCustomRemove(i) {
        let a = _trayCustom().slice()
        if (i < 0 || i >= a.length) return
        a.splice(i, 1)
        SettingsService.set("tray.custom", a)
        _trayEditIdx = -1
    }

    // Theme name-entry flow: "" | "new" | "duplicate" | "rename"
    property string _themeAction: ""
    function _confirmTheme(name) {
        if (!name || name.trim() === "") { _themeAction = ""; return }
        if (_themeAction === "new")            ThemeManager.createTheme(name)
        else if (_themeAction === "duplicate") ThemeManager.duplicateTheme(ThemeManager.activeId, name)
        else if (_themeAction === "rename")    ThemeManager.renameTheme(ThemeManager.activeId, name)
        _themeAction = ""
    }

    readonly property var _cats: [
        { id: "appearance",   label: "Appearance",   icon: "󰉼" },
        { id: "bar",          label: "Bar",          icon: "󰍜" },
        { id: "keybindings",  label: "Keybindings",  icon: "󰌌" },
        { id: "media",        label: "Media",        icon: "󰝚" },
        { id: "notifications",label: "Notifications",icon: "󰂚" },
        { id: "weather",      label: "Weather",      icon: "󰖐" },
        { id: "tray",         label: "Tray",         icon: "󰍡" },
        { id: "tools",        label: "Tools",        icon: "󱁤" },
        { id: "dependencies", label: "Dependencies", icon: "󰏖" },
        { id: "advanced",     label: "Advanced",     icon: "󰒓" }
    ]

    // ── Scrim ───────────────────────────────────────────────────────────────--
    Rectangle {
        anchors.fill: parent
        color: ThemeManager.scrim
        opacity: root.active ? 0.4 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        MouseArea { anchors.fill: parent; onClicked: SettingsUi.hide() }
    }

    // ── Card ────────────────────────────────────────────────────────────────--
    Rectangle {
        id: card
        width:  Math.min(760, root.width - 80)
        height: Math.min(560, root.height - 120)
        anchors.centerIn: parent
        radius: ThemeManager.panelRadius + 4
        color:  ThemeManager.surfaceContainer
        border.width: 1
        border.color: ThemeManager.outlineVariant
        opacity: root.active ? 1 : 0
        scale:   root.active ? 1 : 0.96
        layer.enabled: true
        layer.effect: Elevation { level: 4 }
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        focus: root.active
        Keys.onEscapePressed: SettingsUi.hide()

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ── Sidebar ───────────────────────────────────────────────────────
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 188
                color: ThemeManager.surfaceContainerLow
                topLeftRadius: ThemeManager.panelRadius + 4
                bottomLeftRadius: ThemeManager.panelRadius + 4

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4

                    Text {
                        text: "Settings"
                        color: ThemeManager.onSurface
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeLg
                        font.bold: true
                        Layout.bottomMargin: 8
                        Layout.leftMargin: 6
                    }

                    Repeater {
                        model: root._cats
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 36
                            radius: ThemeManager.chipRadius
                            readonly property bool sel: SettingsUi.category === modelData.id
                            color: sel ? ThemeManager.secondaryContainer
                                       : (_h.hovered ? ThemeManager.surfaceContainerHigh : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 12
                                spacing: 10
                                Text { text: modelData.icon; color: sel ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                                       font.family: ThemeManager.fontFamily; font.pixelSize: 16 }
                                Text { Layout.fillWidth: true; text: modelData.label
                                       color: sel ? ThemeManager.onSurface : ThemeManager.onSurfaceVariant
                                       font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeMd }
                            }
                            HoverHandler { id: _h }
                            TapHandler { onTapped: SettingsUi.category = modelData.id }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ── Content pane ──────────────────────────────────────────────────
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: _pane.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: _pane
                    width: parent.width
                    Component.onCompleted: {}

                    // Appearance ----------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "appearance"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6
                        SettingSection { text: "Appearance" }
                        SettingSeg {
                            label: "Overall style"
                            sub: "Frame border · top bar only · floating bar"
                            options: ["Frame", "Top bar", "Islands"]
                            keys: ["frame", "topbar", "islands"]
                            path: "appearance.mode"; def: "frame"
                        }
                        SettingSlider { label: "Bar height"; path: "bar.height"; def: 40; from: 28; to: 56; unit: "px" }
                        SettingSlider { label: "Panel radius"; path: "appearance.panelRadius"; def: 16; from: 0; to: 28; unit: "px" }
                        SettingSlider { label: "Base font size"; path: "appearance.fontSize"; def: 13; from: 10; to: 18; unit: "pt" }
                        SettingToggle { label: "Panel blur"; sub: "Background blur behind panels"; path: "appearance.blur"; def: true }

                        SettingSection { text: "Theme" }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: ThemeManager.pickerThemes
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: ThemeManager.activeId === modelData.id
                                    implicitWidth: _tn.implicitWidth + 28
                                    implicitHeight: 34
                                    radius: ThemeManager.chipRadius
                                    color: sel ? ThemeManager.secondaryContainer
                                               : (_th.hovered ? ThemeManager.surfaceContainerHigh : ThemeManager.surfaceContainerLow)
                                    border.width: sel ? 2 : 1
                                    border.color: sel ? ThemeManager.primary : ThemeManager.outlineVariant
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 7
                                        Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter
                                                    color: modelData.dark ? "#222" : "#eee"; border.width: 1; border.color: ThemeManager.outlineVariant }
                                        Text { id: _tn; text: modelData.name
                                               color: sel ? ThemeManager.onSurface : ThemeManager.onSurfaceVariant
                                               font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                                    }
                                    HoverHandler { id: _th }
                                    TapHandler { onTapped: ThemeManager.setTheme(modelData.id) }
                                }
                            }
                        }
                        // Theme actions
                        Row {
                            Layout.topMargin: 4
                            spacing: 8
                            SettingBtn { label: "New";       onClicked: { root._themeAction = "new";       _nameInput.text = ""; _nameInput.forceActiveFocus() } }
                            SettingBtn { label: "Duplicate"; onClicked: { root._themeAction = "duplicate"; _nameInput.text = ThemeManager.name + " copy"; _nameInput.forceActiveFocus() } }
                            SettingBtn { enabled: ThemeManager._isUser(ThemeManager.activeId); label: "Rename"; onClicked: { root._themeAction = "rename"; _nameInput.text = ThemeManager.name; _nameInput.forceActiveFocus() } }
                            SettingBtn { enabled: ThemeManager._isUser(ThemeManager.activeId); label: "Delete"; danger: true; onClicked: ThemeManager.deleteTheme(ThemeManager.activeId) }
                        }
                        // Name entry — only while a New/Duplicate/Rename is pending
                        RowLayout {
                            visible: root._themeAction !== ""
                            Layout.fillWidth: true; Layout.topMargin: 4
                            spacing: 8
                            TextField {
                                id: _nameInput
                                Layout.fillWidth: true; implicitHeight: 30
                                placeholderText: "Theme name"
                                color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                leftPadding: 10; rightPadding: 10
                                background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                        border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                onAccepted: root._confirmTheme(text)
                                Keys.onEscapePressed: root._themeAction = ""
                            }
                            SettingBtn {
                                label: root._themeAction === "rename" ? "Rename"
                                     : root._themeAction === "duplicate" ? "Duplicate" : "Create"
                                onClicked: root._confirmTheme(_nameInput.text)
                            }
                            SettingBtn { label: "Cancel"; onClicked: root._themeAction = "" }
                        }

                        // ── Theme designer (colors) ────────────────────────────
                        SettingSection { text: "Designer" }
                        Text {
                            visible: !ThemeManager._isUser(ThemeManager.activeId)
                            Layout.fillWidth: true
                            text: "Built-in themes are read-only — Duplicate one to edit its colors."
                            wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: 10
                        }
                        ColumnLayout {
                            visible: ThemeManager._isUser(ThemeManager.activeId)
                            Layout.fillWidth: true; Layout.topMargin: 4
                            spacing: 4
                            Repeater {
                                model: ThemeManager.editableRoles
                                delegate: SettingColor { required property var modelData; role: modelData }
                            }
                        }
                        SettingText {
                            Layout.topMargin: 6
                            label: "Import (.json)"; sub: "Path → new theme"
                            path: "_importPath"; def: ""; placeholder: "/path/theme.json"
                        }
                        Row {
                            Layout.topMargin: 6
                            spacing: 10
                            SettingBtn { label: "Import"; onClicked: ThemeManager.importTheme(SettingsService.get("_importPath", ""), "imported") }
                            SettingBtn { label: "Export current theme"; onClicked: _exportTheme.running = true }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Exports the active theme's colors to ~/.local/state/quickshell/exports/"
                            wrapMode: Text.WordWrap
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: 10
                        }
                        Process {
                            id: _exportTheme
                            command: ["sh", "-c",
                                "d=\"" + (Paths.stateDir + "/exports") + "\"; " +
                                "mkdir -p \"$d\" && printf '%s' '" +
                                JSON.stringify(ThemeManager.themeData).replace(/'/g, "'\\''") +
                                "' > \"$d/" + ThemeManager.activeId + ".json\""]
                        }
                    }

                    // Bar -----------------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "bar"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6
                        SettingSection { text: "Clock" }
                        SettingToggle { label: "24-hour clock"; path: "bar.clock.use24h"; def: true }
                        SettingToggle { label: "Show seconds"; path: "bar.clock.seconds"; def: false }
                        SettingSection { text: "Widgets (opt-in)" }
                        SettingToggle { label: "Launcher button"; path: "bar.widgets.launcher"; def: true }
                        SettingToggle { label: "Active window title"; path: "bar.widgets.windowTitle"; def: true }
                        SettingToggle { label: "Media mini indicator"; path: "bar.widgets.media"; def: false }
                        SettingToggle { label: "Status row (battery/wifi/bt/vol)"; path: "bar.widgets.status"; def: true }
                        SettingSection { text: "Workspaces" }
                        SettingToggle { label: "Show numbers"; sub: "Off = dots"; path: "bar.workspaces.numbers"; def: false }
                        SettingToggle { label: "Hide special workspaces"; path: "bar.workspaces.hideSpecial"; def: true }
                        SettingToggle { label: "Unified workspaces"; sub: "Shared across screens (off = per-monitor)"; path: "workspaces.unified"; def: false }
                    }

                    // Media ---------------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "media"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6
                        SettingSection { text: "Media player" }
                        SettingToggle { label: "Audio visualizer"; dep: "cava"; path: "media.visualizer"; def: true }
                        SettingToggle { label: "Bongo cat"; path: "media.bongo"; def: true }
                        SettingToggle { label: "YouTube Music companion"; sub: "Realtime integration (needs node)"; dep: "node"; path: "media.ytm"; def: true }
                    }

                    // Notifications -------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "notifications"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6
                        SettingSection { text: "Notifications" }
                        SettingToggle { label: "Click notification opens app"; path: "notifications.clickOpensApp"; def: true }
                        SettingToggle { label: "Start in Do Not Disturb"; path: "notifications.dndDefault"; def: false }
                        SettingSlider { label: "Toast timeout"; path: "notifications.toastMs"; def: 5000; from: 2000; to: 15000; unit: "ms" }
                        SettingSlider { label: "Max toast stack"; path: "notifications.toastMax"; def: 5; from: 1; to: 10; unit: "" }
                    }

                    // Weather -------------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "weather"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6
                        SettingSection { text: "Weather" }
                        SettingText { label: "Location"; sub: "City or lat,lon — empty = auto by IP"; path: "weather.location"; def: "Dijon"; placeholder: "auto" }
                        SettingToggle { label: "Fahrenheit"; sub: "Off = Celsius"; path: "weather.fahrenheit"; def: false }
                        SettingSlider { label: "Refresh interval"; path: "weather.refreshMin"; def: 30; from: 5; to: 120; unit: "min" }
                    }

                    // Keybindings ---------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "keybindings"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6
                        SettingSection { text: "Keybindings" }
                        Text {
                            Layout.fillWidth: true; Layout.bottomMargin: 4
                            text: "Shortcuts for the shell's actions. Unbound by default. Type a Hyprland combo, e.g. \"SUPER + R\" or \"SUPER + SHIFT + L\". Saving reloads Hyprland to apply. Requires hypr/quickshell.lua (Lua config)."
                            wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }
                        Repeater {
                            model: BindingService.actions
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                    elide: Text.ElideRight
                                }
                                TextField {
                                    id: _bindField
                                    Layout.preferredWidth: 180; implicitHeight: 28
                                    text: SettingsService.get("binds." + modelData.key, "")
                                    placeholderText: "Unbound"
                                    color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                    leftPadding: 8; rightPadding: 8
                                    background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                            border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                    onEditingFinished: if (text !== SettingsService.get("binds." + modelData.key, "")) BindingService.setCombo(modelData.key, text)
                                }
                                SettingBtn {
                                    label: "Clear"; danger: true
                                    enabled: SettingsService.get("binds." + modelData.key, "") !== ""
                                    onClicked: { _bindField.text = ""; BindingService.setCombo(modelData.key, "") }
                                }
                            }
                        }
                    }

                    // Tray ----------------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "tray"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6

                        // Custom entries (non-SNI apps) -----------------------------
                        SettingSection { text: "Custom entries" }
                        Text {
                            Layout.fillWidth: true; Layout.bottomMargin: 2
                            text: "Pin any app to the tray, even ones without tray support. Each entry is one clickable icon."
                            wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }

                        Repeater {
                            model: root._trayCustomList
                            delegate: Rectangle {
                                id: _ce
                                required property var modelData
                                required property int index
                                readonly property bool _ws: (modelData.action ?? "run") === "ws"
                                readonly property bool editing: root._trayEditIdx === index

                                function _iconSrc() {
                                    const ic = String(_ce.modelData.icon ?? "")
                                    if (ic === "") return ""
                                    return (ic.startsWith("/") || ic.indexOf("://") >= 0) ? ic : Quickshell.iconPath(ic, true)
                                }

                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                radius: ThemeManager.panelRadius
                                color: ThemeManager.surfaceContainerHigh
                                border.width: 1; border.color: editing ? ThemeManager.primary : ThemeManager.outlineVariant
                                implicitHeight: (editing ? _ceCol.implicitHeight : _ceRow.implicitHeight) + 24

                                // ── Collapsed summary ──────────────────────────────
                                RowLayout {
                                    id: _ceRow
                                    visible: !_ce.editing
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                                    spacing: 10
                                    Rectangle {
                                        implicitWidth: 30; implicitHeight: 30; radius: 6
                                        color: ThemeManager.surfaceContainer
                                        border.width: 1; border.color: ThemeManager.outlineVariant
                                        IconImage { anchors.centerIn: parent; implicitSize: 20; source: _ce._iconSrc() }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            text: (_ce.modelData.name && _ce.modelData.name !== "") ? _ce.modelData.name : "Unnamed"
                                            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm; font.bold: true
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            text: (_ce._ws ? "Toggle workspace · " : "Run · ") + ((_ce.modelData.value && _ce.modelData.value !== "") ? _ce.modelData.value : "not set")
                                            color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11
                                        }
                                    }
                                    SettingBtn { label: "Edit"; onClicked: root._trayEditIdx = _ce.index }
                                    SettingBtn { label: "Remove"; danger: true; onClicked: root._trayCustomRemove(_ce.index) }
                                }

                                // ── Expanded editor ────────────────────────────────
                                ColumnLayout {
                                    id: _ceCol
                                    visible: _ce.editing
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                    spacing: 10

                                    // Header: live icon preview + name field
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Rectangle {
                                            implicitWidth: 30; implicitHeight: 30; radius: 6
                                            color: ThemeManager.surfaceContainer
                                            border.width: 1; border.color: ThemeManager.outlineVariant
                                            IconImage { anchors.centerIn: parent; implicitSize: 20; source: _ce._iconSrc() }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 2
                                            Text { text: "Label (tooltip on hover)"; color: ThemeManager.onSurfaceVariant
                                                   font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11 }
                                            TextField {
                                                Layout.fillWidth: true; implicitHeight: 28
                                                text: _ce.modelData.name ?? ""; placeholderText: "e.g. Firefox"
                                                color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                                leftPadding: 8; rightPadding: 8
                                                background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainer
                                                                        border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                                onEditingFinished: if (text !== (_ce.modelData.name ?? "")) root._trayCustomSet(_ce.index, "name", text)
                                            }
                                        }
                                    }

                                    // Icon field
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Text { text: "Icon — freedesktop name (e.g. firefox, spotify) or /path/to/icon.png"
                                               color: ThemeManager.onSurfaceVariant
                                               font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11 }
                                        TextField {
                                            Layout.fillWidth: true; implicitHeight: 28
                                            text: _ce.modelData.icon ?? ""; placeholderText: "firefox"
                                            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                            leftPadding: 8; rightPadding: 8
                                            background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainer
                                                                    border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                            onEditingFinished: if (text !== (_ce.modelData.icon ?? "")) root._trayCustomSet(_ce.index, "icon", text)
                                        }
                                    }

                                    // Action chooser (segmented) + value field
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        Text { text: "On left-click"; color: ThemeManager.onSurfaceVariant
                                               font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11 }
                                        Row {
                                            spacing: 0
                                            Repeater {
                                                model: [{ k: "run", t: "Run a command" }, { k: "ws", t: "Toggle workspace" }]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    readonly property bool sel: (_ce.modelData.action ?? "run") === modelData.k
                                                    implicitWidth: _segT.implicitWidth + 24; implicitHeight: 28
                                                    topLeftRadius:    index === 0 ? ThemeManager.chipRadius : 0
                                                    bottomLeftRadius: index === 0 ? ThemeManager.chipRadius : 0
                                                    topRightRadius:    index === 1 ? ThemeManager.chipRadius : 0
                                                    bottomRightRadius: index === 1 ? ThemeManager.chipRadius : 0
                                                    color: sel ? ThemeManager.primary : ThemeManager.surfaceContainer
                                                    border.width: 1; border.color: sel ? ThemeManager.primary : ThemeManager.outlineVariant
                                                    Text { id: _segT; anchors.centerIn: parent; text: modelData.t
                                                           color: parent.sel ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                                                           font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                                                    TapHandler { onTapped: root._trayCustomSet(_ce.index, "action", modelData.k) }
                                                }
                                            }
                                        }
                                        TextField {
                                            Layout.fillWidth: true; Layout.topMargin: 2; implicitHeight: 28
                                            text: _ce.modelData.value ?? ""
                                            placeholderText: _ce._ws ? "special workspace name (e.g. spotify)" : "command to run (e.g. firefox)"
                                            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                            leftPadding: 8; rightPadding: 8
                                            background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainer
                                                                    border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                            onEditingFinished: if (text !== (_ce.modelData.value ?? "")) root._trayCustomSet(_ce.index, "value", text)
                                        }
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: _ce._ws
                                                ? "Click peeks/hides that Hyprland special workspace (park the app there via a window rule)."
                                                : "Click runs this shell command (launches or focuses the app)."
                                            color: ThemeManager.onSurfaceVariant
                                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11
                                        }
                                    }

                                    // Footer: Remove + Validate (collapse)
                                    RowLayout {
                                        Layout.fillWidth: true; Layout.topMargin: 2
                                        SettingBtn { label: "Remove"; danger: true; onClicked: root._trayCustomRemove(_ce.index) }
                                        Item { Layout.fillWidth: true }
                                        SettingBtn { label: "Validate"; onClicked: root._trayEditIdx = -1 }
                                    }
                                }
                            }
                        }

                        SettingBtn { Layout.topMargin: 8; label: "+  Add entry"; onClicked: root._trayCustomAdd() }

                        SettingSection { text: "System tray"; Layout.topMargin: 12 }
                        Text {
                            Layout.fillWidth: true; Layout.bottomMargin: 4
                            text: "Per app: hide it, or set a special workspace (left-click then toggles that workspace instead of activating)."
                            wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }
                        Repeater {
                            model: SystemTray.items
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10
                                IconImage { implicitSize: 18; source: modelData.icon ?? "" }
                                Text {
                                    Layout.fillWidth: true
                                    text: (modelData.tooltipTitle && modelData.tooltipTitle !== "") ? modelData.tooltipTitle
                                        : ((modelData.title && modelData.title !== "") ? modelData.title : (modelData.id ?? "item"))
                                    color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                    elide: Text.ElideRight
                                }
                                TextField {
                                    Layout.preferredWidth: 104; implicitHeight: 26
                                    text: root._trayWs(modelData); placeholderText: "workspace"
                                    color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                    leftPadding: 8; rightPadding: 8
                                    background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                            border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                    onEditingFinished: if (text !== root._trayWs(modelData)) root._traySetWs(modelData, text)
                                }
                                SettingBtn {
                                    readonly property bool _hidden: root._trayIsHidden(modelData)
                                    label: _hidden ? "Hidden" : "Visible"; danger: _hidden
                                    onClicked: root._trayToggleHide(modelData)
                                }
                            }
                        }
                        Text {
                            visible: (SystemTray.items?.values ?? []).length === 0
                            text: "No tray items."
                            color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }
                    }

                    // Tools ---------------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "tools"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6
                        SettingSection { text: "Tools toolbar" }
                        SettingToggle { label: "Enable toolbar"; path: "tools.enabled"; def: true }
                        SettingSection { text: "Tools" }
                        SettingToggle { label: "File explorer"; dep: "superfile"; path: "tools.files"; def: true }
                        SettingToggle { label: "Screen recorder"; dep: "wf-recorder"; path: "tools.recorder"; def: true }
                        SettingToggle { label: "Docker explorer"; dep: "beacon"; path: "tools.docker"; def: true }
                        SettingToggle { label: "Wallpaper picker"; dep: "matugen"; path: "tools.wallpaper"; def: true }

                        SettingSection { text: "Screen recorder" }
                        SettingText   { label: "Output folder"; path: "tools.recorder.dir"; def: ""; placeholder: "~/Videos" }
                        SettingToggle { label: "Capture audio"; path: "tools.recorder.audio"; def: false }
                    }

                    // Dependencies --------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "dependencies"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6
                        SettingSection { text: "Optional dependencies" }
                        Text {
                            Layout.fillWidth: true; Layout.bottomMargin: 6
                            text: "Optional features need these. Nothing is installed automatically."
                            wrapMode: Text.WordWrap
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }
                        Repeater {
                            model: Object.keys(DependencyService.deps)
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10
                                readonly property bool ok: DependencyService.available(modelData)
                                Text { text: ok ? "󰄬" : "󰅖"; color: ok ? "#7bd88f" : ThemeManager.error
                                       font.family: ThemeManager.fontFamily; font.pixelSize: 14 }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    Text { text: modelData + "  ·  " + DependencyService.desc(modelData)
                                           color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                                    Text { visible: !parent.parent.ok; text: "install: " + DependencyService.pkg(modelData)
                                           color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: 10 }
                                }
                            }
                        }
                        Rectangle {
                            Layout.topMargin: 8
                            implicitWidth: _recheck.implicitWidth + 24; implicitHeight: 30
                            radius: ThemeManager.chipRadius; color: _rcH.hovered ? ThemeManager.surfaceContainerHigh : ThemeManager.surfaceContainerLow
                            border.width: 1; border.color: ThemeManager.outlineVariant
                            Text { id: _recheck; anchors.centerIn: parent; text: "Re-check"; color: ThemeManager.onSurface
                                   font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                            HoverHandler { id: _rcH }
                            TapHandler { onTapped: DependencyService.recheck() }
                        }
                    }

                    // Advanced ------------------------------------------------------
                    ColumnLayout {
                        visible: SettingsUi.category === "advanced"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 10
                        SettingSection { text: "Advanced" }
                        Row {
                            spacing: 10
                            SettingBtn { label: "Open settings.json"; onClicked: _open.running = true }
                            SettingBtn { label: "Reset to defaults"; danger: true; onClicked: SettingsService.reset() }
                        }
                        Process { id: _open; command: ["xdg-open", SettingsService._path]; running: false }
                    }
                }
            }
        }
    }

    // ── Reusable controls ─────────────────────────────────────────────────────
    component SettingSection: Text {
        Layout.topMargin: 10
        Layout.bottomMargin: 2
        color: ThemeManager.primary
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeSm
        font.bold: true
    }
    component SettingRowBase: RowLayout {
        id: rowBase
        property string label: ""
        property string sub: ""
        property string dep: ""
        Layout.fillWidth: true
        spacing: 10
        readonly property bool depOk: dep === "" || DependencyService.available(dep)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                spacing: 6
                Text { text: rowBase.label; color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeMd }
                Rectangle {
                    visible: rowBase.dep !== "" && !rowBase.depOk
                    implicitWidth: _dt.implicitWidth + 10; implicitHeight: 16; radius: 8
                    color: Qt.rgba(ThemeManager.error.r, ThemeManager.error.g, ThemeManager.error.b, 0.18)
                    Text { id: _dt; anchors.centerIn: parent; text: "needs " + (rowBase.dep ? DependencyService.pkg(rowBase.dep) : "")
                           color: ThemeManager.error; font.family: ThemeManager.fontFamily; font.pixelSize: 9 }
                }
            }
            Text { visible: rowBase.sub !== ""; text: rowBase.sub; color: ThemeManager.onSurfaceVariant
                   font.family: ThemeManager.fontFamily; font.pixelSize: 10 }
        }
    }
    component SettingToggle: SettingRowBase {
        id: tg
        property string path: ""
        property bool def: false
        readonly property bool on: SettingsService.get(path, def)
        Rectangle {
            implicitWidth: 40; implicitHeight: 22; radius: 11
            opacity: tg.depOk ? 1 : 0.4
            color: tg.on ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 16; height: 16; radius: 8
                y: 3; x: tg.on ? parent.width - width - 3 : 3
                color: tg.on ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
            TapHandler { enabled: tg.depOk; onTapped: SettingsService.set(tg.path, !tg.on) }
        }
    }
    component SettingSlider: SettingRowBase {
        id: sl
        property string path: ""
        property real def: 0
        property real from: 0
        property real to: 100
        property string unit: ""
        readonly property real val: SettingsService.get(path, def)
        Text { text: Math.round(sl.val) + sl.unit; color: ThemeManager.onSurfaceVariant
               font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm; Layout.rightMargin: 8 }
        Rectangle {
            id: track
            Layout.preferredWidth: 160; implicitHeight: 6; radius: 3
            color: ThemeManager.surfaceContainerHigh
            readonly property real _frac: Math.max(0, Math.min(1, (sl.val - sl.from) / (sl.to - sl.from)))
            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: track.width * track._frac; radius: 3; color: ThemeManager.primary }
            Rectangle { width: 14; height: 14; radius: 7; color: ThemeManager.primary
                        y: -4; x: Math.max(0, Math.min(track.width - width, track.width * track._frac - width / 2)) }
            MouseArea {
                anchors.fill: parent; anchors.margins: -6
                onPressed: (e) => _set(e.x); onPositionChanged: (e) => { if (pressed) _set(e.x) }
                function _set(x) {
                    const f = Math.max(0, Math.min(1, (x - 6) / track.width))
                    SettingsService.set(sl.path, Math.round(sl.from + f * (sl.to - sl.from)))
                }
            }
        }
    }
    component SettingSeg: SettingRowBase {
        id: seg
        property string path: ""
        property string def: ""
        property var options: []
        property var keys: []
        readonly property string cur: SettingsService.get(path, def)
        Row {
            spacing: 0
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    implicitWidth: _st.implicitWidth + 22; implicitHeight: 28
                    readonly property bool sel: seg.cur === seg.keys[index]
                    color: sel ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
                    border.width: 1; border.color: ThemeManager.outlineVariant
                    Text { id: _st; anchors.centerIn: parent; text: modelData
                           color: sel ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                           font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                    TapHandler { onTapped: SettingsService.set(seg.path, seg.keys[index]) }
                }
            }
        }
    }
    component SettingColor: RowLayout {
        id: clr
        property string role: ""
        Layout.fillWidth: true
        spacing: 10
        Rectangle {
            width: 22; height: 22; radius: 5
            color: ThemeManager[clr.role] !== undefined ? ThemeManager[clr.role] : "transparent"
            border.width: 1; border.color: ThemeManager.outlineVariant
        }
        Text {
            Layout.fillWidth: true; text: clr.role
            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
        }
        TextField {
            Layout.preferredWidth: 100; implicitHeight: 26
            text: ThemeManager.roleHex(clr.role)
            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
            leftPadding: 8; rightPadding: 8
            background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                    border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
            onEditingFinished: if (text !== ThemeManager.roleHex(clr.role)) ThemeManager.setRole(clr.role, text)
        }
    }
    component SettingText: SettingRowBase {
        id: tx
        property string path: ""
        property string def: ""
        property string placeholder: ""
        TextField {
            Layout.preferredWidth: 170
            implicitHeight: 30
            text: SettingsService.get(tx.path, tx.def)
            placeholderText: tx.placeholder
            placeholderTextColor: ThemeManager.onSurfaceVariant
            color: ThemeManager.onSurface
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            leftPadding: 10; rightPadding: 10
            background: Rectangle {
                radius: ThemeManager.chipRadius
                color: ThemeManager.surfaceContainerHigh
                border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant
            }
            onEditingFinished: SettingsService.set(tx.path, text)
        }
    }
    component SettingBtn: Rectangle {
        id: btn
        property string label: ""
        property bool danger: false
        property bool enabled: true
        signal clicked()
        implicitWidth: _bt.implicitWidth + 26; implicitHeight: 32
        radius: ThemeManager.chipRadius
        opacity: enabled ? 1 : 0.4
        color: (enabled && _bH.hovered) ? ThemeManager.surfaceContainerHigh : ThemeManager.surfaceContainerLow
        border.width: 1; border.color: danger ? ThemeManager.error : ThemeManager.outlineVariant
        Text { id: _bt; anchors.centerIn: parent; text: btn.label
               color: btn.danger ? ThemeManager.error : ThemeManager.onSurface
               font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
        HoverHandler { id: _bH; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: btn.enabled; onTapped: btn.clicked() }
    }
}
