import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
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
    // This transient overlay must request keyboard itself (unlike the always-on
    // shell layer, a focus grab alone won't pull keyboard to it). The grab is
    // kept only so window focus is restored automatically on close.
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    HyprlandFocusGrab { windows: [root]; active: root.active }

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

    // Custom tools: [{name, icon (glyph), command}] — rendered in the rail.
    readonly property var _toolCustomList: SettingsService.get("tools.custom", [])
    property int _toolEditIdx: -1
    function _toolCustom() { return SettingsService.get("tools.custom", []) }
    function _toolCustomAdd() {
        let a = _toolCustom().slice()
        a.push({ name: "Tool", icon: "󰘔", command: "" })
        SettingsService.set("tools.custom", a)
        _toolEditIdx = a.length - 1
    }
    function _toolCustomSet(i, field, val) {
        let a = _toolCustom().slice()
        if (i < 0 || i >= a.length) return
        let e = Object.assign({}, a[i]); e[field] = val; a[i] = e
        SettingsService.set("tools.custom", a)
    }
    function _toolCustomRemove(i) {
        let a = _toolCustom().slice()
        if (i < 0 || i >= a.length) return
        a.splice(i, 1)
        SettingsService.set("tools.custom", a)
        _toolEditIdx = -1
    }
    // Curated glyph palette (Material Design Icons / nerd font) for the picker.
    readonly property var _toolIcons: [
        "󰆍","󰉋","󰈔","󰏫","󰆼","󰊢","󰃤","󰖟","󰝚","󰕧","󰄀","󰻃","󰋩","󰡨","󰒓","󰪚",
        "󰃭","󰇮","󰭹","󰇚","󰍉","󰩹","󰋊","󰂯","󰍹","󰌌","󰸌","󰊗","󰠮","󰥔","󰅟","󰒃",
        "󰋜","󰖷","󰓎","󰣐","󰀻","󰘔"
    ]

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
        { id: "wallpaper",    label: "Wallpaper",    icon: "󰸉" },
        { id: "hyprland",     label: "Hyprland",     icon: "󰍹" },
        { id: "dependencies", label: "Dependencies", icon: "󰏖" },
        { id: "advanced",     label: "Advanced",     icon: "󰒓" }
    ]

    // Wallpaper pane: active sub-tab ("local" | "favorites" | "browse")
    property string _wpTab: "local"

    // Hyprland pane: active sub-tab ("display" | "appearance" | "input")
    property string _hlTab: "display"

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
        width:  Math.min(920, root.width - 80)
        height: Math.min(660, root.height - 120)
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

        // Swallow clicks on the card background (sidebar gaps, header) so they
        // don't reach the dismiss scrim underneath.
        MouseArea { anchors.fill: parent }

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
                        SettingSection { text: "Widgets" }
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
                        SettingToggle { label: "YouTube Music companion"; sub: "Realtime integration (ytmdesktop companion server)"; path: "media.ytm"; def: true }
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
                        onVisibleChanged: if (visible) HyprlandConfigService.refreshClients()
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

                        // Launch rules (Hyprland window rules) --------------------
                        SettingSection { text: "Launch in special workspace"; Layout.topMargin: 12 }
                        Text {
                            Layout.fillWidth: true; Layout.bottomMargin: 4
                            text: "Windows whose class matches open directly in that special workspace. Switch off to let the app open normally. Use the same workspace name as the tray mapping above. Applies to windows opened from now on."
                            wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }
                        Repeater {
                            model: HyprlandConfigService.specialRules
                            delegate: RowLayout {
                                id: _sr
                                required property var modelData
                                required property int index
                                readonly property bool on: modelData.enabled !== false
                                readonly property var hit: HyprlandConfigService.matchedClass(modelData.class ?? "")
                                Layout.fillWidth: true
                                spacing: 10
                                SwitchPill {
                                    on: _sr.on
                                    onToggled: HyprlandConfigService.setSpecialRule(_sr.index, "enabled", !_sr.on)
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 1
                                    opacity: _sr.on ? 1 : 0.5
                                    TextField {
                                        Layout.fillWidth: true; implicitHeight: 26
                                        text: _sr.modelData.class ?? ""; placeholderText: "window class regex (e.g. rocket-chat)"
                                        color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                        leftPadding: 8; rightPadding: 8
                                        background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                                border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                        onEditingFinished: if (text !== (_sr.modelData.class ?? "")) HyprlandConfigService.setSpecialRule(_sr.index, "class", text.trim())
                                    }
                                    Text {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        text: _sr.hit === null ? "Invalid regex"
                                            : (_sr.hit !== "" ? "Matches open window: " + _sr.hit : "No open window matches")
                                        color: _sr.hit === null ? ThemeManager.error : ThemeManager.onSurfaceVariant
                                        font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11
                                    }
                                }
                                Text { text: "special:"; color: ThemeManager.onSurfaceVariant; opacity: _sr.on ? 1 : 0.5
                                       font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm; Layout.alignment: Qt.AlignTop; Layout.topMargin: 5 }
                                TextField {
                                    Layout.preferredWidth: 104; implicitHeight: 26; Layout.alignment: Qt.AlignTop
                                    opacity: _sr.on ? 1 : 0.5
                                    text: _sr.modelData.ws ?? ""; placeholderText: "workspace"
                                    color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                    leftPadding: 8; rightPadding: 8
                                    background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                            border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                    onEditingFinished: if (text !== (_sr.modelData.ws ?? "")) HyprlandConfigService.setSpecialRule(_sr.index, "ws", text.trim())
                                }
                                SettingBtn { Layout.alignment: Qt.AlignTop; label: "Remove"; danger: true; onClicked: HyprlandConfigService.removeSpecialRule(_sr.index) }
                            }
                        }
                        RowLayout {
                            Layout.topMargin: 8; spacing: 8
                            SettingBtn { label: "+  Add rule"; onClicked: HyprlandConfigService.addSpecialRule("", "") }
                            SettingBtn { label: "Refresh windows"; onClicked: HyprlandConfigService.refreshClients() }
                        }
                        Text {
                            Layout.topMargin: 6
                            visible: _openClasses.count > 0
                            text: "Add from an open window:"
                            color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: 6
                            Repeater {
                                id: _openClasses
                                // Unique classes of open windows not already covered by a rule.
                                model: {
                                    const rules = HyprlandConfigService.specialRules
                                    const seen = new Set()
                                    return HyprlandConfigService.clients.map(c => c.class).filter(cls => {
                                        if (seen.has(cls)) return false
                                        seen.add(cls)
                                        return !rules.some(r => {
                                            try { return new RegExp("^(?:" + (r.class ?? "") + ")$").test(cls) } catch (e) { return false }
                                        })
                                    })
                                }
                                delegate: SettingBtn {
                                    required property string modelData
                                    label: "+ " + modelData
                                    onClicked: HyprlandConfigService.addSpecialRule(
                                        modelData.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
                                        modelData.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""))
                                }
                            }
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
                        SettingToggle { label: "Wallpaper picker"; sub: "Built-in background/theme tool"; dep: "matugen"; path: "tools.wallpaper"; def: true }

                        SettingSection { text: "Custom tools"; Layout.topMargin: 12 }
                        Text {
                            Layout.fillWidth: true; Layout.bottomMargin: 2
                            text: "Add your own rail buttons — each runs a command. Examples: file manager (kitty -e yazi), screen record (wf-recorder -g \"$(slurp)\" -f ~/rec.mp4)."
                            wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }
                        Repeater {
                            model: root._toolCustomList
                            delegate: Rectangle {
                                id: _tc
                                required property var modelData
                                required property int index
                                readonly property bool editing: root._toolEditIdx === index

                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                radius: ThemeManager.panelRadius
                                color: ThemeManager.surfaceContainerHigh
                                border.width: 1; border.color: editing ? ThemeManager.primary : ThemeManager.outlineVariant
                                implicitHeight: (editing ? _tcCol.implicitHeight : _tcRow.implicitHeight) + 24

                                // Collapsed summary
                                RowLayout {
                                    id: _tcRow
                                    visible: !_tc.editing
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                                    spacing: 10
                                    Text {
                                        text: _tc.modelData.icon || "󰘔"; color: ThemeManager.onSurface
                                        font.family: ThemeManager.fontFamily; font.pixelSize: 22
                                        Layout.preferredWidth: 28; horizontalAlignment: Text.AlignHCenter
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            text: (_tc.modelData.name && _tc.modelData.name !== "") ? _tc.modelData.name : "Unnamed"
                                            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm; font.bold: true
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            text: (_tc.modelData.command && _tc.modelData.command !== "") ? _tc.modelData.command : "no command"
                                            color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11
                                        }
                                    }
                                    SettingBtn { label: "Edit"; onClicked: root._toolEditIdx = _tc.index }
                                    SettingBtn { label: "Remove"; danger: true; onClicked: root._toolCustomRemove(_tc.index) }
                                }

                                // Expanded editor
                                ColumnLayout {
                                    id: _tcCol
                                    visible: _tc.editing
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Text { text: "Name (tooltip)"; color: ThemeManager.onSurfaceVariant
                                               font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11 }
                                        TextField {
                                            Layout.fillWidth: true; implicitHeight: 28
                                            text: _tc.modelData.name ?? ""; placeholderText: "e.g. Files"
                                            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                            leftPadding: 8; rightPadding: 8
                                            background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainer
                                                                    border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                            onEditingFinished: if (text !== (_tc.modelData.name ?? "")) root._toolCustomSet(_tc.index, "name", text)
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Text { text: "Command"; color: ThemeManager.onSurfaceVariant
                                               font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11 }
                                        TextField {
                                            Layout.fillWidth: true; implicitHeight: 28
                                            text: _tc.modelData.command ?? ""; placeholderText: "kitty -e yazi"
                                            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                            leftPadding: 8; rightPadding: 8
                                            background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainer
                                                                    border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                            onEditingFinished: if (text !== (_tc.modelData.command ?? "")) root._toolCustomSet(_tc.index, "command", text)
                                        }
                                    }
                                    // Icon picker — grid of glyphs
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        Text { text: "Icon"; color: ThemeManager.onSurfaceVariant
                                               font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeXs ?? 11 }
                                        Flow {
                                            Layout.fillWidth: true; spacing: 4
                                            Repeater {
                                                model: root._toolIcons
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool sel: (_tc.modelData.icon || "") === modelData
                                                    width: 34; height: 34; radius: 8
                                                    color: sel ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.22)
                                                               : ThemeManager.surfaceContainer
                                                    border.width: 1; border.color: sel ? ThemeManager.primary : ThemeManager.outlineVariant
                                                    Text { anchors.centerIn: parent; text: modelData
                                                           color: parent.sel ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                                                           font.family: ThemeManager.fontFamily; font.pixelSize: 20 }
                                                    TapHandler { onTapped: root._toolCustomSet(_tc.index, "icon", modelData) }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; Layout.topMargin: 2
                                        SettingBtn { label: "Remove"; danger: true; onClicked: root._toolCustomRemove(_tc.index) }
                                        Item { Layout.fillWidth: true }
                                        SettingBtn { label: "Validate"; onClicked: root._toolEditIdx = -1 }
                                    }
                                }
                            }
                        }
                        SettingBtn { Layout.topMargin: 8; label: "+  Add tool"; onClicked: root._toolCustomAdd() }
                    }

                    // Wallpaper -----------------------------------------------------
                    ColumnLayout {
                        id: _wpPane
                        visible: SettingsUi.category === "wallpaper"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6

                        readonly property var _localList: WallpaperService.wallpapers
                        readonly property var _favList:   WallpaperService.favorites
                        readonly property var _shownList: root._wpTab === "favorites" ? _favList : _localList
                        property int _rotAnchor: -1   // last-clicked index, for shift-range rotation select

                        Text {
                            visible: !WallpaperService.available
                            Layout.fillWidth: true
                            text: "hyprpaper not installed — the wallpaper switcher is disabled."
                            wrapMode: Text.WordWrap; color: ThemeManager.error
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }

                        // ── Tabs ──────────────────────────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [ { id: "local", label: "Local" }, { id: "favorites", label: "Favorites" }, { id: "browse", label: "Browse" } ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root._wpTab === modelData.id
                                    implicitWidth: _wtl.implicitWidth + 24; implicitHeight: 30
                                    radius: ThemeManager.chipRadius
                                    color: sel ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.18)
                                               : (_wtMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                                    Text {
                                        id: _wtl; anchors.centerIn: parent; text: modelData.label
                                        color: parent.sel ? ThemeManager.primary : ThemeManager.onSurface
                                        font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                    }
                                    MouseArea { id: _wtMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root._wpTab = modelData.id }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            SettingBtn { label: "Refresh"; onClicked: WallpaperService.refresh() }
                        }

                        Text {
                            visible: root._wpTab !== "browse" && _wpPane._shownList.length === 0
                            Layout.topMargin: 8
                            text: root._wpTab === "favorites" ? "No favorites yet — tap the heart on a wallpaper."
                                                              : "No wallpapers in ~/wallpaper."
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                            opacity: 0.7
                        }

                        // ── Local / Favorites thumbnail grid ──────────────────────
                        Flow {
                            visible: root._wpTab !== "browse"
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 8
                            Repeater {
                                model: root._wpTab === "browse" ? [] : _wpPane._shownList
                                delegate: ClippingRectangle {
                                    id: _tile
                                    required property var modelData
                                    required property int index
                                    readonly property string _path: "" + modelData
                                    readonly property bool _isCurrent: WallpaperService.current === _path
                                    readonly property bool _inRot: WallpaperService.isInRotation(_path)
                                    width: 168; height: 96
                                    radius: ThemeManager.chipRadius
                                    color: ThemeManager.surfaceContainerHigh

                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + _tile._path
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: false
                                        sourceSize.width: 336
                                    }
                                    // Border: current wallpaper (primary) or in-rotation (tertiary)
                                    Rectangle {
                                        anchors.fill: parent; radius: _tile.radius; color: "transparent"
                                        border.width: (_tile._isCurrent || _tile._inRot) ? 2 : 0
                                        border.color: _tile._isCurrent ? ThemeManager.primary : ThemeManager.tertiary
                                    }
                                    // Hover darken
                                    Rectangle {
                                        anchors.fill: parent; radius: _tile.radius
                                        color: Qt.rgba(0, 0, 0, _tileMa.containsMouse ? 0.18 : 0)
                                    }
                                    // Rotation badge (bottom-left) — membership set via ctrl/shift-click
                                    Rectangle {
                                        visible: _tile._inRot
                                        anchors { left: parent.left; bottom: parent.bottom; margins: 5 }
                                        width: 20; height: 20; radius: 10
                                        color: Qt.rgba(ThemeManager.tertiary.r, ThemeManager.tertiary.g, ThemeManager.tertiary.b, 0.9)
                                        Text { anchors.centerIn: parent; text: "󰑖"; color: ThemeManager.onTertiary
                                               font.family: ThemeManager.fontFamily; font.pixelSize: 12 }
                                    }
                                    // Click: plain = set; ctrl = toggle rotation; shift = range-add to rotation
                                    MouseArea {
                                        id: _tileMa
                                        anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: (m) => {
                                            if (m.modifiers & Qt.ControlModifier) {
                                                WallpaperService.toggleRotation(_tile._path)
                                                _wpPane._rotAnchor = _tile.index
                                            } else if (m.modifiers & Qt.ShiftModifier) {
                                                const list = _wpPane._shownList
                                                const a = _wpPane._rotAnchor >= 0 ? _wpPane._rotAnchor : _tile.index
                                                const lo = Math.min(a, _tile.index), hi = Math.max(a, _tile.index)
                                                const r = (WallpaperService.rotationPaths || []).slice()
                                                for (let i = lo; i <= hi; i++) {
                                                    const pp = "" + list[i]
                                                    if (r.indexOf(pp) < 0) r.push(pp)
                                                }
                                                WallpaperService.setRotation(r)
                                            } else {
                                                WallpaperService.commit(_tile._path)
                                                _wpPane._rotAnchor = _tile.index
                                            }
                                        }
                                    }
                                    // Favorite button (on top of the tile MouseArea so it stays clickable)
                                    WpTileBtn {
                                        anchors { top: parent.top; right: parent.right; margins: 5 }
                                        icon: WallpaperService.isFavorite(_tile._path) ? "󰋑" : "󰋕"
                                        active: WallpaperService.isFavorite(_tile._path)
                                        onClicked: WallpaperService.toggleFavorite(_tile._path)
                                    }
                                }
                            }
                        }

                        // ── Browse (Wallhaven) ────────────────────────────────────
                        ColumnLayout {
                            visible: root._wpTab === "browse"
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                TextField {
                                    id: _whSearch
                                    Layout.fillWidth: true; implicitHeight: 30
                                    placeholderText: "Search wallhaven.cc…"
                                    color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                    leftPadding: 10; rightPadding: 10
                                    background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                            border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                    onAccepted: WallhavenService.search(text, _whSort.cur)
                                }
                                SettingBtn { label: "Search"; onClicked: WallhavenService.search(_whSearch.text, _whSort.cur) }
                            }
                            // Sorting
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: [ { k: "toplist", l: "Top" }, { k: "date_added", l: "Latest" }, { k: "views", l: "Views" }, { k: "random", l: "Random" } ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool sel: _whSort.cur === modelData.k
                                        implicitWidth: _whsl.implicitWidth + 18; implicitHeight: 26
                                        radius: ThemeManager.chipRadius
                                        color: sel ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.18)
                                                   : (_whsMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                                        Text { id: _whsl; anchors.centerIn: parent; text: modelData.l
                                               color: parent.sel ? ThemeManager.primary : ThemeManager.onSurface
                                               font.family: ThemeManager.fontFamily; font.pixelSize: 11 }
                                        MouseArea { id: _whsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { _whSort.cur = modelData.k; WallhavenService.search(_whSearch.text, modelData.k) } }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Item {
                                    property string cur: "toplist"
                                    id: _whSort
                                }
                            }

                            Text {
                                visible: !WallpaperService.canDownload
                                Layout.fillWidth: true
                                text: "Browsing works, but downloading a wallpaper needs curl (install it to set/favorite from here)."
                                wrapMode: Text.WordWrap; color: ThemeManager.error
                                font.family: ThemeManager.fontFamily; font.pixelSize: 10
                            }
                            Text {
                                visible: WallhavenService.error !== ""
                                Layout.fillWidth: true
                                text: WallhavenService.error
                                color: ThemeManager.error; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                            }
                            Text {
                                visible: WallhavenService.loading && WallhavenService.results.length === 0
                                text: "Searching…"; color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm; opacity: 0.7
                            }
                            Text {
                                visible: !WallhavenService.loading && WallhavenService.error === "" && WallhavenService.results.length === 0
                                text: "Search wallhaven.cc for wallpapers."; color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm; opacity: 0.7
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: root._wpTab === "browse" ? WallhavenService.results : []
                                    delegate: ClippingRectangle {
                                        id: _rtile
                                        required property var modelData
                                        readonly property bool _busy: WallpaperService.downloadingId === ("" + modelData.id)
                                        width: 168; height: 96
                                        radius: ThemeManager.chipRadius
                                        color: ThemeManager.surfaceContainerHigh

                                        Image {
                                            anchors.fill: parent
                                            source: _rtile.modelData.thumb
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true; cache: true
                                        }
                                        Rectangle {
                                            anchors.fill: parent; radius: _rtile.radius
                                            color: Qt.rgba(0, 0, 0, (_rtMa.containsMouse || _rtile._busy) ? 0.3 : 0)
                                        }
                                        // Resolution chip
                                        Text {
                                            anchors { bottom: parent.bottom; left: parent.left; margins: 4 }
                                            text: _rtile.modelData.resolution || ""
                                            color: "white"; style: Text.Outline; styleColor: "black"
                                            font.family: ThemeManager.fontFamily; font.pixelSize: 9
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: _rtile._busy
                                            text: "󰇚"; color: "white"
                                            font.family: ThemeManager.fontFamily; font.pixelSize: 22
                                        }
                                        MouseArea {
                                            id: _rtMa; anchors.fill: parent
                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            enabled: WallpaperService.canDownload && !_rtile._busy
                                            // Click = download + set
                                            onClicked: WallpaperService.download(_rtile.modelData.full, _rtile.modelData.id, _rtile.modelData.fileType, false)
                                        }
                                        // Favorite (download + favorite) — above the tile MouseArea so it stays clickable
                                        WpTileBtn {
                                            anchors { top: parent.top; right: parent.right; margins: 5 }
                                            icon: "󰋕"
                                            onClicked: WallpaperService.download(_rtile.modelData.full, _rtile.modelData.id, _rtile.modelData.fileType, true)
                                        }
                                    }
                                }
                            }
                            SettingBtn {
                                Layout.topMargin: 6
                                visible: WallhavenService.hasMore && !WallhavenService.loading
                                label: "Load more"
                                onClicked: WallhavenService.loadMore()
                            }
                            SettingText {
                                Layout.topMargin: 10
                                label: "Wallhaven API key"
                                sub: "Optional — only needed to browse NSFW results"
                                path: "wallpaper.wallhavenKey"
                                placeholder: "from wallhaven.cc/settings/account"
                            }
                        }

                        // ── Rotation ──────────────────────────────────────────────
                        SettingSection { text: "Rotation"; Layout.topMargin: 14 }
                        SettingRowBase {
                            label: "Rotate wallpapers"
                            sub: WallpaperService.rotationPaths.length + " selected — Ctrl-click a wallpaper to add, Shift-click for a range"
                            Rectangle {
                                implicitWidth: 40; implicitHeight: 22; radius: 11
                                opacity: WallpaperService.rotationPaths.length > 1 ? 1 : 0.4
                                color: WallpaperService.rotationEnabled ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Rectangle {
                                    width: 16; height: 16; radius: 8; y: 3
                                    x: WallpaperService.rotationEnabled ? parent.width - width - 3 : 3
                                    color: WallpaperService.rotationEnabled ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                                TapHandler {
                                    enabled: WallpaperService.rotationPaths.length > 1
                                    onTapped: WallpaperService.setRotationEnabled(!WallpaperService.rotationEnabled)
                                }
                            }
                        }
                        SettingRowBase {
                            label: "Interval"
                            Text {
                                text: WallpaperService.rotationIntervalMin + " min"
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm; Layout.rightMargin: 8
                            }
                            Rectangle {
                                id: _wpIvTrack
                                Layout.preferredWidth: 160; implicitHeight: 6; radius: 3
                                color: ThemeManager.surfaceContainerHigh
                                readonly property int _min: 1
                                readonly property int _max: 120
                                readonly property real _frac: Math.max(0, Math.min(1, (WallpaperService.rotationIntervalMin - _min) / (_max - _min)))
                                Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                            width: _wpIvTrack.width * _wpIvTrack._frac; radius: 3; color: ThemeManager.primary }
                                Rectangle { width: 14; height: 14; radius: 7; color: ThemeManager.primary
                                            y: -4; x: Math.max(0, Math.min(_wpIvTrack.width - width, _wpIvTrack.width * _wpIvTrack._frac - width / 2)) }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -6
                                    onPressed: (e) => _set(e.x); onPositionChanged: (e) => { if (pressed) _set(e.x) }
                                    function _set(x) {
                                        const f = Math.max(0, Math.min(1, (x - 6) / _wpIvTrack.width))
                                        WallpaperService.setRotationInterval(_wpIvTrack._min + f * (_wpIvTrack._max - _wpIvTrack._min))
                                    }
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true; Layout.topMargin: 2
                            text: "Each change re-generates the Material You theme from the new wallpaper."
                            wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: 10; opacity: 0.7
                        }
                    }

                    // Hyprland ------------------------------------------------------
                    ColumnLayout {
                        id: _hlPane
                        visible: SettingsUi.category === "hyprland"
                        Layout.fillWidth: true
                        Layout.margins: 20
                        spacing: 6

                        SettingSection { text: "Hyprland" }
                        Text {
                            Layout.fillWidth: true; Layout.bottomMargin: 4
                            text: "Override monitors, appearance and input on top of your own Hyprland config. Only what you change here is written (to hypr.generated.lua); your config is untouched. Requires hypr/quickshell.lua (Lua config)."
                            wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                        }

                        // ── Sub-tabs ──────────────────────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [ { id: "display", label: "Display" }, { id: "appearance", label: "Appearance" }, { id: "input", label: "Input" } ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root._hlTab === modelData.id
                                    implicitWidth: _htl.implicitWidth + 24; implicitHeight: 30
                                    radius: ThemeManager.chipRadius
                                    color: sel ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.18)
                                               : (_htMa.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
                                    Text {
                                        id: _htl; anchors.centerIn: parent; text: modelData.label
                                        color: parent.sel ? ThemeManager.primary : ThemeManager.onSurface
                                        font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                    }
                                    MouseArea { id: _htMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root._hlTab = modelData.id }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            SettingBtn { label: "Refresh"; onClicked: HyprlandConfigService.refresh() }
                        }

                        // ── Display tab ───────────────────────────────────────────
                        ColumnLayout {
                            id: _dispTab
                            visible: root._hlTab === "display"
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 8

                            property string sel: ""
                            property bool _detModeOpen: false
                            // Selection with a fallback to the first monitor so the detail
                            // panel always has a target (probe may finish after onCompleted).
                            readonly property string effSel: {
                                const ms = HyprlandConfigService.monitors
                                if (sel !== "") for (const m of ms) if (m.name === sel) return sel
                                return ms.length ? ms[0].name : ""
                            }

                            function mget(name, k, d) { return SettingsService.get("hypr.monitors." + name + "." + k, d) }
                            function selMon() { for (const m of HyprlandConfigService.monitors) if (m.name === _dispTab.effSel) return m; return null }

                            // Effective logical geometry for a monitor (staged override or live).
                            // Logical size = mode pixels / scale, swapped for 90°/270° rotation.
                            function mgeo(m) {
                                void SettingsService.rev
                                const modeStr = mget(m.name, "mode", m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2))
                                const mm = ("" + modeStr).split("@")[0].split("x")
                                let W = parseInt(mm[0]) || m.width, H = parseInt(mm[1]) || m.height
                                const sc = parseFloat(mget(m.name, "scale", m.scale)) || 1
                                const tr = parseInt(mget(m.name, "transform", m.transform)) || 0
                                if (tr === 1 || tr === 3) { const t = W; W = H; H = t }
                                return {
                                    name: m.name,
                                    on:   mget(m.name, "enabled", !m.disabled),
                                    lx:   parseInt(mget(m.name, "x", m.x)) || 0,
                                    ly:   parseInt(mget(m.name, "y", m.y)) || 0,
                                    lw:   Math.max(1, Math.round(W / sc)),
                                    lh:   Math.max(1, Math.round(H / sc))
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Drag a screen to reposition it; it snaps to its neighbours' edges. Click to select and edit its settings below."
                                wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily; font.pixelSize: 10; opacity: 0.7
                            }

                            // ── Visual layout canvas ──────────────────────────────────
                            Rectangle {
                                id: _canvas
                                Layout.fillWidth: true
                                Layout.preferredHeight: 260
                                radius: ThemeManager.chipRadius
                                color: ThemeManager.surfaceContainerLow
                                border.width: 1; border.color: ThemeManager.outlineVariant
                                clip: true

                                readonly property var _boxes: { void SettingsService.rev; return HyprlandConfigService.monitors.map(m => _dispTab.mgeo(m)) }
                                readonly property real _pad: 18
                                readonly property real _minX: _boxes.length ? Math.min(..._boxes.map(b => b.lx)) : 0
                                readonly property real _minY: _boxes.length ? Math.min(..._boxes.map(b => b.ly)) : 0
                                readonly property real _spanX: _boxes.length ? Math.max(1, Math.max(..._boxes.map(b => b.lx + b.lw)) - _minX) : 1
                                readonly property real _spanY: _boxes.length ? Math.max(1, Math.max(..._boxes.map(b => b.ly + b.lh)) - _minY) : 1
                                readonly property real k: Math.min((width - 2 * _pad) / _spanX, (height - 2 * _pad) / _spanY)
                                readonly property real _offX: (width  - _spanX * k) / 2
                                readonly property real _offY: (height - _spanY * k) / 2
                                function px(lx) { return _offX + (lx - _minX) * k }
                                function py(ly) { return _offY + (ly - _minY) * k }

                                // Deselect when clicking empty canvas
                                MouseArea { anchors.fill: parent; onClicked: {} }

                                Repeater {
                                    model: HyprlandConfigService.monitors
                                    delegate: Rectangle {
                                        id: _mtile
                                        required property var modelData
                                        readonly property string _mn: modelData.name
                                        readonly property var b: _dispTab.mgeo(modelData)
                                        readonly property bool _isSel: _dispTab.effSel === _mn
                                        property real _grabX: 0
                                        property real _grabY: 0
                                        property int  _origX: 0
                                        property int  _origY: 0
                                        property bool _moved: false

                                        x: _canvas.px(b.lx);  y: _canvas.py(b.ly)
                                        width:  Math.max(24, b.lw * _canvas.k)
                                        height: Math.max(18, b.lh * _canvas.k)
                                        radius: 6
                                        opacity: b.on ? 1 : 0.45
                                        color: _isSel ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.28)
                                                      : ThemeManager.surfaceContainerHigh
                                        border.width: _isSel ? 2 : 1
                                        border.color: _isSel ? ThemeManager.primary : ThemeManager.outlineVariant

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: _mtile._mn
                                                color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily
                                                font.pixelSize: ThemeManager.fontSizeSm; font.bold: true
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                visible: _mtile.height > 34
                                                text: _mtile.b.on ? (_mtile.b.lw + "×" + _mtile.b.lh) : "off"
                                                color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: 9
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.OpenHandCursor
                                            onPressed: (m) => {
                                                _dispTab.sel = _mtile._mn
                                                _mtile._moved = false
                                                const p = mapToItem(_canvas, m.x, m.y)
                                                _mtile._grabX = p.x; _mtile._grabY = p.y
                                                _mtile._origX = _mtile.b.lx; _mtile._origY = _mtile.b.ly
                                            }
                                            onPositionChanged: (m) => {
                                                if (!pressed) return
                                                const p = mapToItem(_canvas, m.x, m.y)
                                                if (!_mtile._moved && Math.abs(p.x - _mtile._grabX) + Math.abs(p.y - _mtile._grabY) < 3) return
                                                _mtile._moved = true
                                                const nx = Math.round(_mtile._origX + (p.x - _mtile._grabX) / _canvas.k)
                                                const ny = Math.round(_mtile._origY + (p.y - _mtile._grabY) / _canvas.k)
                                                HyprlandConfigService.stageMonitor(_mtile._mn, "x", nx)
                                                HyprlandConfigService.stageMonitor(_mtile._mn, "y", ny)
                                            }
                                            onReleased: { if (_mtile._moved) _dispTab.snap(_mtile._mn) }
                                        }
                                    }
                                }
                            }

                            // Snap the given monitor's edges to its neighbours (kill gaps/overlap).
                            function snap(name) {
                                const me = mgeo(selMonBy(name))
                                if (!me) return
                                const others = HyprlandConfigService.monitors.filter(m => m.name !== name).map(m => mgeo(m))
                                const th = Math.max(40, _canvas._spanX * 0.05)
                                let nx = me.lx, ny = me.ly
                                for (const o of others) {
                                    // horizontal edge snapping
                                    if (Math.abs((me.lx + me.lw) - o.lx) < th) nx = o.lx - me.lw
                                    else if (Math.abs(me.lx - (o.lx + o.lw)) < th) nx = o.lx + o.lw
                                    else if (Math.abs(me.lx - o.lx) < th) nx = o.lx
                                    // vertical edge / top-align snapping
                                    if (Math.abs((me.ly + me.lh) - o.ly) < th) ny = o.ly - me.lh
                                    else if (Math.abs(me.ly - (o.ly + o.lh)) < th) ny = o.ly + o.lh
                                    else if (Math.abs(me.ly - o.ly) < th) ny = o.ly
                                }
                                if (nx !== me.lx) HyprlandConfigService.stageMonitor(name, "x", nx)
                                if (ny !== me.ly) HyprlandConfigService.stageMonitor(name, "y", ny)
                            }
                            function selMonBy(name) { for (const m of HyprlandConfigService.monitors) if (m.name === name) return m; return null }

                            // ── Selected-monitor detail ───────────────────────────────
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                visible: _dispTab.selMon() !== null
                                implicitHeight: _detCol.implicitHeight + 24
                                radius: ThemeManager.chipRadius
                                color: ThemeManager.surfaceContainerLow
                                border.width: 1; border.color: ThemeManager.outlineVariant

                                readonly property var m: _dispTab.selMon()
                                readonly property string _mn: m ? m.name : ""
                                function _get(k, d) { return m ? SettingsService.get("hypr.monitors." + _mn + "." + k, d) : d }
                                readonly property bool _on: m ? _get("enabled", !m.disabled) : true
                                id: _det

                                ColumnLayout {
                                    id: _detCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        Text {
                                            text: _det._mn
                                            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily
                                            font.pixelSize: ThemeManager.fontSizeMd; font.bold: true
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: _det.m ? (_det.m.width + "×" + _det.m.height + " @" + Number(_det.m.refreshRate).toFixed(0) + "Hz") : ""
                                            color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                        Text { text: "On"; color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily; font.pixelSize: 10 }
                                        Rectangle {
                                            implicitWidth: 40; implicitHeight: 22; radius: 11
                                            color: _det._on ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
                                            Rectangle { width: 16; height: 16; radius: 8; y: 3; x: _det._on ? parent.width - width - 3 : 3
                                                        color: _det._on ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                                                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } }
                                            TapHandler { onTapped: HyprlandConfigService.stageMonitor(_det._mn, "enabled", !_det._on) }
                                        }
                                    }

                                    // Resolution (inline expanding)
                                    ColumnLayout {
                                        visible: _det._on
                                        Layout.fillWidth: true
                                        spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { text: "Resolution"; color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                                            Item { Layout.fillWidth: true }
                                            Rectangle {
                                                implicitWidth: _detRes.implicitWidth + 26; implicitHeight: 28
                                                radius: ThemeManager.chipRadius
                                                color: ThemeManager.surfaceContainerHigh
                                                border.width: 1; border.color: _dispTab._detModeOpen ? ThemeManager.primary : ThemeManager.outlineVariant
                                                Text {
                                                    id: _detRes; anchors.centerIn: parent
                                                    text: (_det.m ? _det._get("mode", _det.m.width + "x" + _det.m.height + "@" + Number(_det.m.refreshRate).toFixed(2)) : "") + "  ▾"
                                                    color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: _dispTab._detModeOpen = !_dispTab._detModeOpen }
                                            }
                                        }
                                        Flow {
                                            visible: _dispTab._detModeOpen
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Repeater {
                                                model: (_dispTab._detModeOpen && _det.m) ? _det.m.modes : []
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool sel: _det._get("mode", "") === modelData
                                                    implicitWidth: _dmo.implicitWidth + 16; implicitHeight: 24
                                                    radius: ThemeManager.chipRadius
                                                    color: sel ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.18) : ThemeManager.surfaceContainerHigh
                                                    border.width: 1; border.color: ThemeManager.outlineVariant
                                                    Text { id: _dmo; anchors.centerIn: parent; text: modelData
                                                           color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: 10 }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                onClicked: { HyprlandConfigService.stageMonitor(_det._mn, "mode", modelData); _dispTab._detModeOpen = false } }
                                                }
                                            }
                                        }
                                    }

                                    // Scale + position + rotation
                                    GridLayout {
                                        visible: _det._on
                                        Layout.fillWidth: true
                                        columns: 2; columnSpacing: 12; rowSpacing: 6

                                        Text { text: "Scale"; color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                                        TextField {
                                            Layout.preferredWidth: 90; implicitHeight: 28
                                            text: _det.m ? "" + _det._get("scale", _det.m.scale) : ""
                                            color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                            leftPadding: 8; rightPadding: 8
                                            background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                                    border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                            onEditingFinished: { const v = parseFloat(text); if (!isNaN(v)) HyprlandConfigService.stageMonitor(_det._mn, "scale", v) }
                                        }

                                        Text { text: "Position (x, y)"; color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                                        RowLayout {
                                            spacing: 6
                                            TextField {
                                                Layout.preferredWidth: 70; implicitHeight: 28
                                                text: _det.m ? "" + _det._get("x", _det.m.x) : ""
                                                color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                                leftPadding: 8; rightPadding: 8
                                                background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                                        border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                                onEditingFinished: { const v = parseInt(text); if (!isNaN(v)) HyprlandConfigService.stageMonitor(_det._mn, "x", v) }
                                            }
                                            TextField {
                                                Layout.preferredWidth: 70; implicitHeight: 28
                                                text: _det.m ? "" + _det._get("y", _det.m.y) : ""
                                                color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm
                                                leftPadding: 8; rightPadding: 8
                                                background: Rectangle { radius: ThemeManager.chipRadius; color: ThemeManager.surfaceContainerHigh
                                                                        border.width: 1; border.color: parent.activeFocus ? ThemeManager.primary : ThemeManager.outlineVariant }
                                                onEditingFinished: { const v = parseInt(text); if (!isNaN(v)) HyprlandConfigService.stageMonitor(_det._mn, "y", v) }
                                            }
                                        }

                                        Text { text: "Rotation"; color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                                        Row {
                                            spacing: 0
                                            Repeater {
                                                model: [ "0°", "90°", "180°", "270°" ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    readonly property bool sel: _det.m ? (_det._get("transform", _det.m.transform) === index) : false
                                                    implicitWidth: _dtr.implicitWidth + 18; implicitHeight: 26
                                                    color: sel ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
                                                    border.width: 1; border.color: ThemeManager.outlineVariant
                                                    Text { id: _dtr; anchors.centerIn: parent; text: modelData
                                                           color: sel ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
                                                           font.family: ThemeManager.fontFamily; font.pixelSize: ThemeManager.fontSizeSm }
                                                    TapHandler { onTapped: HyprlandConfigService.stageMonitor(_det._mn, "transform", index) }
                                                }
                                            }
                                        }
                                    }

                                    SettingBtn {
                                        label: "Reset this monitor"; danger: true
                                        onClicked: HyprlandConfigService.resetMonitor(_det._mn)
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 10
                                SettingBtn {
                                    label: "Apply display changes"
                                    enabled: HyprlandConfigService.monitorsDirty
                                    onClicked: HyprlandConfigService.applyMonitors()
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Display changes ask for confirmation and auto-revert after 15 s if not kept."
                                    wrapMode: Text.WordWrap; color: ThemeManager.onSurfaceVariant
                                    font.family: ThemeManager.fontFamily; font.pixelSize: 10; opacity: 0.7
                                }
                            }
                        }

                        // ── Appearance tab ────────────────────────────────────────
                        ColumnLayout {
                            visible: root._hlTab === "appearance"
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 6

                            SettingSection { text: "Gaps & borders" }
                            SettingSlider { label: "Gaps in";  path: "hypr.general.gaps_in";  def: HyprlandConfigService.live("general:gaps_in", 5);   from: 0; to: 40; unit: "px"; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingSlider { label: "Gaps out"; path: "hypr.general.gaps_out"; def: HyprlandConfigService.live("general:gaps_out", 20); from: 0; to: 60; unit: "px"; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingSlider { label: "Border size"; path: "hypr.general.border_size"; def: HyprlandConfigService.live("general:border_size", 2); from: 0; to: 8; unit: "px"; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingText   { label: "Active border";   path: "hypr.general.col.active_border";   def: ""; placeholder: "rgba(4fcf8cee)"; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingText   { label: "Inactive border"; path: "hypr.general.col.inactive_border"; def: ""; placeholder: "rgba(595959aa)"; applyFn: () => HyprlandConfigService.applyLive() }

                            SettingSection { text: "Decoration" }
                            SettingSlider { label: "Rounding"; path: "hypr.decoration.rounding"; def: HyprlandConfigService.live("decoration:rounding", 10); from: 0; to: 24; unit: "px"; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingToggle { label: "Blur"; path: "hypr.decoration.blur.enabled"; def: HyprlandConfigService.live("decoration:blur:enabled", true); applyFn: () => HyprlandConfigService.applyLive() }
                            SettingSlider { label: "Blur size";   path: "hypr.decoration.blur.size";   def: HyprlandConfigService.live("decoration:blur:size", 8);   from: 1; to: 20; unit: ""; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingSlider { label: "Blur passes"; path: "hypr.decoration.blur.passes"; def: HyprlandConfigService.live("decoration:blur:passes", 3); from: 1; to: 6;  unit: ""; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingToggle { label: "Shadow"; path: "hypr.decoration.shadow.enabled"; def: HyprlandConfigService.live("decoration:shadow:enabled", true); applyFn: () => HyprlandConfigService.applyLive() }

                            RowLayout {
                                Layout.fillWidth: true; Layout.topMargin: 6
                                Item { Layout.fillWidth: true }
                                SettingBtn { label: "Reset to my config"; danger: true
                                             onClicked: HyprlandConfigService.resetKeys(["general", "decoration"]) }
                            }
                        }

                        // ── Input tab ─────────────────────────────────────────────
                        ColumnLayout {
                            visible: root._hlTab === "input"
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 6

                            SettingSection { text: "Keyboard" }
                            SettingText { label: "Layout";  path: "hypr.input.kb_layout";  def: ""; placeholder: HyprlandConfigService.live("input:kb_layout", "us"); applyFn: () => HyprlandConfigService.applyLive() }
                            SettingText { label: "Variant"; path: "hypr.input.kb_variant"; def: ""; placeholder: HyprlandConfigService.live("input:kb_variant", "—"); applyFn: () => HyprlandConfigService.applyLive() }

                            SettingSection { text: "Mouse & touchpad" }
                            SettingText   { label: "Sensitivity"; sub: "−1.0 to 1.0"; path: "hypr.input.sensitivity"; def: ""; placeholder: "" + HyprlandConfigService.live("input:sensitivity", 0); applyFn: () => HyprlandConfigService.applyLive() }
                            SettingSeg    { label: "Follow mouse"; path: "hypr.input.follow_mouse"; def: "" + HyprlandConfigService.live("input:follow_mouse", 1)
                                            options: [ "0", "1", "2", "3" ]; keys: [ "0", "1", "2", "3" ]; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingToggle { label: "Touchpad natural scroll"; path: "hypr.input.touchpad.natural_scroll"; def: HyprlandConfigService.live("input:touchpad:natural_scroll", false); applyFn: () => HyprlandConfigService.applyLive() }

                            SettingSection { text: "Behavior" }
                            SettingSeg    { label: "Layout"; path: "hypr.general.layout"; def: HyprlandConfigService.live("general:layout", "dwindle")
                                            options: [ "Dwindle", "Master" ]; keys: [ "dwindle", "master" ]; applyFn: () => HyprlandConfigService.applyLive() }
                            SettingToggle { label: "Allow tearing"; sub: "For fullscreen games"; path: "hypr.general.allow_tearing"; def: HyprlandConfigService.live("general:allow_tearing", false); applyFn: () => HyprlandConfigService.applyLive() }
                            SettingToggle { label: "Animations"; path: "hypr.animations.enabled"; def: HyprlandConfigService.live("animations:enabled", true); applyFn: () => HyprlandConfigService.applyLive() }

                            RowLayout {
                                Layout.fillWidth: true; Layout.topMargin: 6
                                Item { Layout.fillWidth: true }
                                SettingBtn { label: "Reset to my config"; danger: true
                                             onClicked: HyprlandConfigService.resetKeys(["input", "general.layout", "general.allow_tearing", "animations"]) }
                            }
                        }
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

    // ── Monitor confirm-or-revert dialog ──────────────────────────────────────
    // Applied display changes auto-revert after a countdown unless kept (a bad
    // mode can black out a screen). Rendered above the card.
    Rectangle {
        anchors.fill: parent
        visible: HyprlandConfigService.monitorConfirmPending
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent }   // swallow clicks to the card

        Rectangle {
            anchors.centerIn: parent
            width: 360
            implicitHeight: _cdCol.implicitHeight + 40
            radius: ThemeManager.panelRadius + 4
            color: ThemeManager.surfaceContainer
            border.width: 1; border.color: ThemeManager.outlineVariant
            layer.enabled: true
            layer.effect: Elevation { level: 4 }

            ColumnLayout {
                id: _cdCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: "Keep these display settings?"
                    color: ThemeManager.onSurface; font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeLg; font.bold: true; wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: "Reverting to the previous settings in " + HyprlandConfigService.monitorCountdown + " s…"
                    color: ThemeManager.onSurfaceVariant; font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeSm; wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Item { Layout.fillWidth: true }
                    SettingBtn { label: "Revert"; danger: true; onClicked: HyprlandConfigService.revertMonitors() }
                    SettingBtn { label: "Keep changes"; onClicked: HyprlandConfigService.confirmMonitors() }
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
    component SwitchPill: Rectangle {
        id: sw
        property bool on: false
        signal toggled()
        implicitWidth: 40; implicitHeight: 22; radius: 11
        color: sw.on ? ThemeManager.primary : ThemeManager.surfaceContainerHigh
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 16; height: 16; radius: 8
            y: 3; x: sw.on ? parent.width - width - 3 : 3
            color: sw.on ? ThemeManager.onPrimary : ThemeManager.onSurfaceVariant
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        TapHandler { onTapped: sw.toggled() }
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
        property var applyFn: null
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
            TapHandler { enabled: tg.depOk; onTapped: { SettingsService.set(tg.path, !tg.on); if (tg.applyFn) tg.applyFn() } }
        }
    }
    component SettingSlider: SettingRowBase {
        id: sl
        property string path: ""
        property real def: 0
        property real from: 0
        property real to: 100
        property string unit: ""
        property var applyFn: null
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
                onReleased: if (sl.applyFn) sl.applyFn()
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
        property var applyFn: null
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
                    TapHandler { onTapped: { SettingsService.set(seg.path, seg.keys[index]); if (seg.applyFn) seg.applyFn() } }
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
        property var applyFn: null
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
            onEditingFinished: { SettingsService.set(tx.path, text); if (tx.applyFn) tx.applyFn() }
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

    // Small round overlay button on a wallpaper tile (favorite / rotation).
    component WpTileBtn: Rectangle {
        id: wtb
        property string icon: ""
        property bool   active: false
        signal clicked()
        implicitWidth: 24; implicitHeight: 24; radius: 12
        color: active ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.9)
                      : Qt.rgba(0, 0, 0, 0.45)
        Text {
            anchors.centerIn: parent
            text: wtb.icon
            color: wtb.active ? ThemeManager.onPrimary : "white"
            font.family: ThemeManager.fontFamily; font.pixelSize: 13
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wtb.clicked() }
    }
}
