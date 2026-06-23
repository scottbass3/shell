import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Caelestia.Blobs
import "./bar"
import "./panels"
import "./theme"
import "./services"

PanelWindow {
    id: root

    required property var modelData

    // Force BatteryService singleton to instantiate so it watches plug/unplug/low.
    Component.onCompleted: BatteryService.present

    screen:        modelData
    anchors        { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color:         "transparent"

    // ── Notification panel state ──────────────────────────────────────────────
    readonly property bool _notifOpen: NotificationService.centerOpen &&
        (NotificationService.centerScreen === null ||
         NotificationService.centerScreen?.name === root.modelData?.name)
    readonly property int  _panelWidth: 320
    readonly property int  _maxHeight:  420
    readonly property int  _targetNotifHeight:
        _notifOpen ? Math.min(notifCenter.implicitHeight, _maxHeight) : 0

    property real _notifHeight: _targetNotifHeight
    Behavior on _notifHeight {
        NumberAnimation {
            duration:           root._notifOpen ? 400 : 250
            easing.type:        Easing.Bezier
            easing.bezierCurve: root._notifOpen
                ? [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                : [0.30, 0.0, 0.8, 0.15, 1.0, 1.0]
        }
    }

    // ── Generic popout state ──────────────────────────────────────────────────
    readonly property bool _popoutOpen: PopoutService.hasCurrent &&
        PopoutService.anchorScreen?.name === root.modelData?.name

    readonly property int _popoutMaxHeight: 420

    // Caelestia pattern: single container whose width+height animate to the
    // active panel's natural size. Content cross-fades + scales, centred.
    readonly property real _targetPopoutWidth: {
        switch (PopoutService.currentName) {
            case "audio":    return _audioLoader.item?.implicitWidth    ?? 180
            case "power":    return _powerLoader.item?.implicitWidth    ?? 180
            case "powerprofile": return _powerProfileLoader.item?.implicitWidth ?? 190
            case "dashboard": return _dashboardLoader.item?.implicitWidth ?? 360
            case "notif":    return _notifLoader.item?.implicitWidth    ?? 320
            case "network":  return _networkLoader.item?.implicitWidth  ?? 260
            case "bluetooth": return _bluetoothLoader.item?.implicitWidth ?? 250
            case "traymenu": return _trayMenuLoader.item?.implicitWidth ?? 200
            case "workspaces": return _workspacesLoader.item?.implicitWidth ?? 320
            default:         return 180
        }
    }
    readonly property real _targetPopoutHeight: {
        if (!_popoutOpen) return 0
        switch (PopoutService.currentName) {
            case "audio":    return Math.min(_audioLoader.item?.implicitHeight    ?? 0, _popoutMaxHeight)
            case "power":    return Math.min(_powerLoader.item?.implicitHeight    ?? 0, _popoutMaxHeight)
            case "powerprofile": return Math.min(_powerProfileLoader.item?.implicitHeight ?? 0, _popoutMaxHeight)
            case "dashboard": return Math.min(_dashboardLoader.item?.implicitHeight ?? 0, 700)
            case "notif":    return Math.min(_notifLoader.item?.implicitHeight    ?? 0, _popoutMaxHeight)
            case "network":  return Math.min(_networkLoader.item?.implicitHeight  ?? 0, _popoutMaxHeight)
            case "bluetooth": return Math.min(_bluetoothLoader.item?.implicitHeight ?? 0, _popoutMaxHeight)
            case "traymenu": return Math.min(_trayMenuLoader.item?.implicitHeight ?? 0, _popoutMaxHeight)
            case "workspaces": return Math.min(_workspacesLoader.item?.implicitHeight ?? 0, 520)
            default:         return 0
        }
    }

    property real _popoutWidth: _targetPopoutWidth
    Behavior on _popoutWidth {
        NumberAnimation {
            duration:           350
            easing.type:        Easing.Bezier
            easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
        }
    }

    property real _popoutHeight: _targetPopoutHeight
    Behavior on _popoutHeight {
        NumberAnimation {
            duration:           350
            easing.type:        Easing.Bezier
            easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
        }
    }

    // X position: centre under widget, clamped to screen edges, animated
    readonly property real _popoutXCalc: {
        // Use the TARGET width (not the animating one) so x and width animate
        // toward their finals in parallel — avoids resize-then-move.
        const w    = _targetPopoutWidth
        const half = w / 2
        return Math.min(
            Math.max(ThemeManager.borderWidth, PopoutService.anchorX - half),
            root.width - w - ThemeManager.borderWidth)
    }
    property real _popoutX: _popoutXCalc
    Behavior on _popoutX {
        NumberAnimation {
            duration:           350
            easing.type:        Easing.Bezier
            easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
        }
    }

    // ── Tray menu dismiss flag ────────────────────────────────────────────────
    readonly property bool _trayMenuPinned:
        PopoutService.pinned && PopoutService.currentName === "traymenu" &&
        PopoutService.anchorScreen?.name === root.modelData?.name

    // ── Right-edge tools toolbar ───────────────────────────────────────────────
    // Notch + rail rendered in the blob layer so they blend into the right border
    // exactly like the bar popouts blend into the top bar.
    property bool _toolsHovered:  false   // mouse hover (set by collapse logic)
    readonly property int  _toolsNotchW: 1       // visible notch width (collapsed)
    readonly property int  _toolsNotchH: 186     // notch height = rail height (full)
    readonly property int  _toolsRailW:  48      // expanded rail width
    readonly property int  _toolsHoverW: 14      // collapsed hover/input zone
    readonly property int  _toolsH:      186     // rail height (4 buttons)
    readonly property int  _toolsWpW:    210     // wallpaper picker width
    readonly property real _toolsRight:  root.width - ThemeManager.borderWidth
    readonly property real _toolsY:      Math.round((root.height - _toolsH) / 2)

    // Tools toolbar is opt-in (off by default for distribution; default true here).
    readonly property bool _toolsEnabled: SettingsService.get("tools.enabled", true)

    // Deployed if hovered OR opened by keyboard (Super+R) — only when enabled
    readonly property bool _toolsShow:    _toolsEnabled && (_toolsHovered || ToolsService.open || ToolsService.wpOpen)
    readonly property bool _toolsWpOpen:  ToolsService.wpOpen
    readonly property bool _toolsKbdActive: ToolsService.open || ToolsService.wpOpen   // keyboard mode

    // ── App launcher (Win11 start menu) — blob merges into the bottom border ──
    readonly property bool _launcherActive:
        LauncherService.open && LauncherService.screenName === root.modelData?.name
    readonly property real _launcherW: Math.min(660, root.width - 80)
    readonly property real _launcherTargetH: Math.min(640, root.height - ThemeManager.barTotalHeight - 60)
    property real _launcherH: _launcherActive ? _launcherTargetH : 0
    Behavior on _launcherH {
        NumberAnimation { duration: 300; easing.type: Easing.Bezier
            easing.bezierCurve: _launcherActive ? [0.05,0.7,0.1,1,1,1] : [0.3,0,0.8,0.15,1,1] }
    }
    readonly property real _launcherX: Math.round((root.width - _launcherW) / 2)
    readonly property real _launcherY: root.height - _launcherH   // flush with bottom edge

    // Exclusive keyboard while the toolbar's keyboard mode OR the launcher is active.
    WlrLayershell.keyboardFocus: (ToolsService.open || ToolsService.wpOpen || root._launcherActive)
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Hyprland doesn't auto-restore window keyboard focus after a layer releases
    // its exclusive grab — re-assert focus on the previously focused window.
    on_ToolsKbdActiveChanged: if (!_toolsKbdActive) _refocusTimer.restart()
    Timer { id: _refocusTimer; interval: 60; onTriggered: FocusService.refocus(ToolsService._prevWin) }

    // Animated current width + height (notch nub ↔ rail), kept vertically centred
    property real _toolsW: _toolsShow ? _toolsRailW : _toolsNotchW
    Behavior on _toolsW {
        NumberAnimation { duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: [0.05,0.7,0.1,1,1,1] }
    }
    property real _toolsCurH: _toolsShow ? _toolsH : _toolsNotchH
    Behavior on _toolsCurH {
        NumberAnimation { duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: [0.05,0.7,0.1,1,1,1] }
    }
    readonly property real _toolsCurY: Math.round((root.height - _toolsCurH) / 2)

    Timer {
        id: _toolsCollapse
        interval: 350
        onTriggered: {
            if (_toolsHover.hovered || _toolsPickHover.hovered) return
            root._toolsHovered = false
            // Mouse-mode wallpaper picker (keyboard mode keeps ToolsService.open
            // true): leaving the rail+picker closes it, which reverts the live
            // hover preview to the committed wallpaper (onWpOpenChanged).
            if (ToolsService.wpOpen && !ToolsService.open) ToolsService.wpOpen = false
        }
    }
    function _toolsEval() {
        if (_toolsHover.hovered || _toolsPickHover.hovered) { root._toolsHovered = true; _toolsCollapse.stop() }
        else _toolsCollapse.restart()
    }

    // ── Input mask ────────────────────────────────────────────────────────────
    mask: Region {
        Region { x: 0; y: 0; width: root.width; height: ThemeManager.barHeight }
        Region {
            x:      root.width - root._panelWidth - (root._islands ? ThemeManager.spacingLg : 0)
            y:      root._panelTop
            width:  root._notifOpen ? root._panelWidth : 0
            height: root._notifOpen ? Math.ceil(root._notifHeight) : 0
        }
        Region {
            x:      root._popoutX
            y:      root._panelTop
            width:  root._popoutOpen ? root._popoutWidth : 0
            height: root._popoutOpen ? Math.ceil(root._popoutHeight) : 0
        }
        // Full-screen dismiss region when tray menu is pinned open
        Region {
            x: 0; y: 0
            width:  root._trayMenuPinned ? root.width  : 0
            height: root._trayMenuPinned ? root.height : 0
        }
        // Tools notch / rail — reach the actual screen edge so pushing the mouse
        // into the border deploys it. (Width includes the border strip.)
        Region {
            readonly property int _w: !root._toolsEnabled ? 0
                : (root._toolsShow ? root._toolsRailW + ThemeManager.borderWidth : root._toolsHoverW)
            readonly property int _h: root._toolsShow ? root._toolsH : root._toolsNotchH
            x:      root.width - _w
            y:      Math.round((root.height - _h) / 2)
            width:  _w
            height: _h
        }
        // Wallpaper picker
        Region {
            x:      root._toolsWpOpen ? root._toolsRight - root._toolsRailW - 8 - root._toolsWpW : root.width
            y:      ThemeManager.barHeight + 8
            width:  root._toolsWpOpen ? root._toolsWpW : 0
            height: root._toolsWpOpen ? root.height - ThemeManager.barHeight - 24 : 0
        }
        // Full-screen dismiss region while toolbar is keyboard-open
        Region {
            x: 0; y: 0
            width:  root._toolsKbdActive ? root.width  : 0
            height: root._toolsKbdActive ? root.height : 0
        }
        // Full-screen region while the launcher is open (interaction + dismiss)
        Region {
            x: 0; y: 0
            width:  root._launcherActive ? root.width  : 0
            height: root._launcherActive ? root.height : 0
        }
    }

    // ── Tray menu dismiss overlay ─────────────────────────────────────────────
    // Full-screen, z-below popout. Catches clicks outside the menu to close it.
    MouseArea {
        anchors.fill: parent
        visible:      root._trayMenuPinned
        z:            0
        onClicked:    PopoutService.close()
    }

    // ── Appearance mode ────────────────────────────────────────────────────────
    //   frame   = SDF border all around + bar merged into the top strip (default)
    //   topbar  = top bar strip only, no side/bottom border
    //   islands = no frame; bar floats as an inset rounded pill
    readonly property string _appMode: SettingsService.get("appearance.mode", "frame")
    readonly property bool   _frame:   _appMode === "frame"
    readonly property bool   _islands: _appMode === "islands"

    // Panels drop from the bar bottom (frame/topbar) OR float as detached cards
    // below the bar pills with a gap + fully-rounded top (islands).
    readonly property real _panelTop: _islands
        ? (ThemeManager.barFloatTop + ThemeManager.barHeight + ThemeManager.spacing)
        : ThemeManager.barHeight
    readonly property real _panelTopRadius: _islands ? ThemeManager.panelRadius : 0

    // ── Blob visual layer ─────────────────────────────────────────────────────
    Item {
        id: blobLayer
        anchors.fill: parent

        // Material elevation — the whole shell frame + popouts cast a shadow.
        layer.enabled: true
        layer.effect: Elevation { level: 4 }

        BlobGroup {
            id: blobs
            color:     ThemeManager.surface
            smoothing: 60
        }

        // Frame border (frame mode) / top strip only (topbar mode) / none (islands).
        // group stays `blobs`; islands zeroes all borders (toggling group at
        // runtime doesn't reliably remove the shape — border values are live).
        BlobInvertedRect {
            group:  blobs
            anchors { fill: parent; margins: -ThemeManager.panelRadius }
            radius:       ThemeManager.panelRadius
            borderTop:    root._islands ? 0 : (ThemeManager.barHeight + ThemeManager.panelRadius)
            borderLeft:   root._frame ? ThemeManager.borderWidth + ThemeManager.panelRadius : 0
            borderRight:  root._frame ? ThemeManager.borderWidth + ThemeManager.panelRadius : 0
            borderBottom: root._frame ? ThemeManager.borderWidth + ThemeManager.panelRadius : 0
        }

        // Islands mode: each bar section is its own floating pill (drawn in Bar.qml).

        BlobRect {
            group:             root._notifHeight > 1 ? blobs : null
            x:                 parent.width - root._panelWidth - (root._islands ? ThemeManager.spacingLg : 0)
            y:                 root._panelTop
            implicitWidth:     root._panelWidth
            implicitHeight:    root._notifHeight
            topLeftRadius:     root._panelTopRadius; topRightRadius: root._panelTopRadius
            bottomLeftRadius:  ThemeManager.panelRadius
            bottomRightRadius: ThemeManager.panelRadius
            deformScale:       0.00003
        }

        BlobRect {
            group:             root._popoutHeight > 1 ? blobs : null
            x:                 root._popoutX
            y:                 root._panelTop
            implicitWidth:     root._popoutWidth
            implicitHeight:    root._popoutHeight
            topLeftRadius:     root._panelTopRadius; topRightRadius: root._panelTopRadius
            bottomLeftRadius:  ThemeManager.panelRadius
            bottomRightRadius: ThemeManager.panelRadius
            deformScale:       0.00003
        }

        // Tools notch/rail — right edge flush with the border, left side rounded,
        // so it reads as a bump growing out of the right border.
        BlobRect {
            group:             root._toolsEnabled ? blobs : null
            x:                 root._toolsRight - root._toolsW
            y:                 root._toolsCurY
            implicitWidth:     root._toolsW
            implicitHeight:    root._toolsCurH
            // Corner radius can't exceed the width or the blob bulges out
            topLeftRadius:     Math.min(ThemeManager.panelRadius, root._toolsW)
            bottomLeftRadius:  Math.min(ThemeManager.panelRadius, root._toolsW)
            topRightRadius:    0; bottomRightRadius: 0
            deformScale:       0.00003
        }

        // App launcher — grows up out of the bottom border (bottom flush, top
        // rounded) so it reads as a continuation of the screen border.
        BlobRect {
            group:             root._launcherH > 1 ? blobs : null
            x:                 root._launcherX
            y:                 root._launcherY
            implicitWidth:     root._launcherW
            implicitHeight:    root._launcherH
            topLeftRadius:     ThemeManager.panelRadius
            topRightRadius:    ThemeManager.panelRadius
            bottomLeftRadius:  0; bottomRightRadius: 0
            deformScale:       0.00003
        }
    }

    // ── Bar ───────────────────────────────────────────────────────────────────
    Bar {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        anchors.topMargin: root._islands ? ThemeManager.barFloatTop : 0
        height:    ThemeManager.barHeight
        barScreen: root.modelData
    }

    // ── Notification panel ────────────────────────────────────────────────────
    Item {
        x:      root.width - root._panelWidth - (root._islands ? ThemeManager.spacingLg : 0)
        y:      root._panelTop
        width:  root._panelWidth
        height: root._notifHeight
        clip:   true
        opacity: root._notifOpen && root._notifHeight > 20 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }

        HoverHandler { onHoveredChanged: NotificationService.panelHovered = hovered }

        NotificationCenter {
            id:           notifCenter
            anchors.fill: parent
            toastMode:    NotificationService.toastMode
        }
    }

    // ── Generic popout ────────────────────────────────────────────────────────
    // Caelestia pattern: single container, animated width+height. All panels
    // pre-loaded, centred, stacked. Active one cross-fades + scales in; the
    // others fade + scale out. Container size animates to active panel's size.
    Item {
        id: _popoutContainer
        x:       root._popoutX
        y:       root._panelTop
        width:   root._popoutWidth
        height:  root._popoutHeight
        clip:    true
        opacity: root._popoutOpen && root._popoutHeight > 20 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }

        HoverHandler { onHoveredChanged: PopoutService.panelHovered = hovered }

        Loader {
            id: _audioLoader
            anchors.centerIn: parent
            source: "panels/AudioPanel.qml"
            readonly property bool _active: PopoutService.currentName === "audio"
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }

        Loader {
            id: _powerLoader
            anchors.centerIn: parent
            source: "panels/PowerPanel.qml"
            readonly property bool _active: PopoutService.currentName === "power"
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }

        Loader {
            id: _powerProfileLoader
            anchors.centerIn: parent
            source: "panels/PowerProfilePanel.qml"
            readonly property bool _active: PopoutService.currentName === "powerprofile"
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }

        Loader {
            id: _dashboardLoader
            anchors.centerIn: parent
            source: "panels/Dashboard.qml"
            readonly property bool _active: PopoutService.currentName === "dashboard"
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }

        Loader {
            id: _notifLoader
            anchors.centerIn: parent
            sourceComponent: NotificationCenter { toastMode: false }
            readonly property bool _active: PopoutService.currentName === "notif"
            // Constrain height to the cap so the inner Flickable is bounded and
            // can scroll (centerIn alone leaves the item at full implicit height,
            // which the container only clips — never scrolls).
            width:  item ? item.implicitWidth : 320
            height: Math.min(item ? item.implicitHeight : 0, root._popoutMaxHeight)
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }

        Loader {
            id: _networkLoader
            anchors.centerIn: parent
            source: "panels/NetworkPanel.qml"
            readonly property bool _active: PopoutService.currentName === "network"
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }

        Loader {
            id: _bluetoothLoader
            anchors.centerIn: parent
            source: "panels/BluetoothPanel.qml"
            readonly property bool _active: PopoutService.currentName === "bluetooth"
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }

        Loader {
            id: _trayMenuLoader
            anchors.centerIn: parent
            source: "panels/TrayMenuPanel.qml"
            readonly property bool _active: PopoutService.currentName === "traymenu"
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }

        Loader {
            id: _workspacesLoader
            anchors.centerIn: parent
            source: "panels/WorkspaceOverview.qml"
            readonly property bool _active: PopoutService.currentName === "workspaces"
            enabled: _active
            visible: _active || opacity > 0
            opacity: _active ? 1 : 0
            scale:   _active ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale {
                NumberAnimation {
                    duration:           300
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
                }
            }
        }
    }

    // Click-outside dismiss while the toolbar is keyboard-open
    MouseArea {
        anchors.fill: parent
        visible: root._toolsKbdActive
        onClicked: ToolsService.close()
    }

    // ── Tools toolbar content (buttons over the blob rail) ─────────────────────
    Item {
        id: _toolsArea
        visible: root._toolsEnabled
        // Spans to the screen edge so hovering the border deploys the rail
        x:      root._toolsRight - root._toolsRailW
        y:      root._toolsY
        width:  root._toolsRailW + ThemeManager.borderWidth
        height: root._toolsH

        HoverHandler { id: _toolsHover; onHoveredChanged: root._toolsEval() }

        // Keyboard navigation (Super+R). Exclusive layer focus while open.
        Item {
            anchors.fill: parent
            focus: ToolsService.open || ToolsService.wpOpen
            Keys.onPressed: (e) => {
                if (!(ToolsService.open || ToolsService.wpOpen)) return
                switch (e.key) {
                    case Qt.Key_Up:                          ToolsService.up();       e.accepted = true; break
                    case Qt.Key_Down:                        ToolsService.down();     e.accepted = true; break
                    case Qt.Key_Left:
                    case Qt.Key_Return:
                    case Qt.Key_Enter:                       ToolsService.activate(); e.accepted = true; break
                    case Qt.Key_Right:
                    case Qt.Key_Escape:                      ToolsService.back();     e.accepted = true; break
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -ThemeManager.borderWidth / 2
            spacing: 6
            opacity: root._toolsShow ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            // User-defined custom tools (Settings → Tools)
            Repeater {
                model: ToolsService.customTools
                delegate: ToolBtn {
                    required property var modelData
                    required property int index
                    icon:   modelData.icon || "󰘔"
                    kbdSel: ToolsService.open && ToolsService.selected === index
                    onClicked: { ToolsService._launch(modelData.command); ToolsService.close(); root._toolsHovered = false }
                }
            }
            // Built-in wallpaper / background picker
            ToolBtn {
                visible: ToolsService.wpEnabled
                icon: "󰸉"; active: root._toolsWpOpen
                kbdSel: ToolsService.open && ToolsService.selected === ToolsService.wpIndex
                onClicked: { if (ToolsService.wpOpen) ToolsService.wpOpen = false; else { ToolsService.wpOpen = true; WallpaperService.refresh() } }
            }
        }
    }

    // ── Wallpaper picker ───────────────────────────────────────────────────────
    Rectangle {
        id: _toolsPicker
        visible: root._toolsWpOpen
        layer.enabled: true
        layer.effect: Elevation { level: 3 }
        width:   root._toolsWpW
        x:       root._toolsRight - root._toolsRailW - 8 - root._toolsWpW
        y:       ThemeManager.barHeight + 8
        height:  root.height - ThemeManager.barHeight - 24
        radius:  ThemeManager.panelRadius
        color:   ThemeManager.surfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)
        opacity: root._toolsWpOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        HoverHandler { id: _toolsPickHover; onHoveredChanged: root._toolsEval() }

        Text {
            id: _wpTitle
            anchors { left: parent.left; top: parent.top; margins: 12 }
            text: "Wallpaper"
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm; font.weight: Font.Medium
        }

        Flickable {
            anchors { left: parent.left; right: parent.right; top: _wpTitle.bottom; bottom: parent.bottom; margins: 12; topMargin: 8 }
            clip: true
            contentWidth: width
            contentHeight: _wpCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: _wpCol
                width: parent.width
                spacing: 8
                Repeater {
                    model: WallpaperService.wallpapers
                    delegate: ClippingRectangle {
                        required property var modelData
                        required property int index
                        readonly property bool _kbdSel: ToolsService.wpOpen && ToolsService.wpSelected === index
                        width:  parent.width
                        height: 90
                        radius: ThemeManager.chipRadius
                        color:  ThemeManager.surfaceContainer
                        Image {
                            anchors.fill: parent
                            source: "file://" + modelData
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            sourceSize.width: 360
                        }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: "transparent"
                            border.width: (WallpaperService.current === modelData || parent._kbdSel) ? 2 : 0
                            border.color: ThemeManager.primary
                        }
                        HoverHandler {
                            id: _wpItemHov
                            // Hovering previews the wallpaper, reusing the keyboard
                            // selection + debounced-preview machinery. Leaving the
                            // picker without clicking reverts (onWpOpenChanged).
                            onHoveredChanged: if (hovered) ToolsService.wpSelected = index
                        }
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius
                            color: Qt.rgba(0, 0, 0, (_wpItemHov.hovered || parent._kbdSel) ? 0.18 : 0)
                        }
                        TapHandler {
                            onTapped: { ToolsService.commitWallpaper(modelData); root._toolsHovered = false }
                        }
                    }
                }
            }
        }
    }

    // ── App launcher content + click-outside dismiss ──────────────────────────
    MouseArea {
        anchors.fill: parent
        visible: root._launcherActive
        onClicked: LauncherService.hide()
    }
    Item {
        id: _launcherContent
        x:       root._launcherX
        y:       root._launcherY
        width:   root._launcherW
        height:  root._launcherH
        clip:    true
        opacity: root._launcherActive && root._launcherH > 20 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }

        Loader {
            anchors.fill: parent
            active:          root._launcherActive || parent.opacity > 0
            sourceComponent: Launcher { active: root._launcherActive }
        }
    }

    // ── Tool button ────────────────────────────────────────────────────────────
    component ToolBtn: Rectangle {
        id: tb
        property string icon:   ""
        property bool   active: false
        property bool   kbdSel: false     // keyboard selection highlight
        signal clicked()
        width: 38; height: 38; radius: 10
        color: (tb.active || tb.kbdSel)
            ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, tb.kbdSel ? 0.28 : 0.20)
            : (_tbHov.hovered
               ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)
               : "transparent")
        border.width: tb.kbdSel ? 1 : 0
        border.color: ThemeManager.primary
        Text {
            anchors.centerIn: parent
            text: tb.icon
            color: (tb.active || tb.kbdSel) ? ThemeManager.primary : ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: 24
        }
        HoverHandler { id: _tbHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tb.clicked() }
    }
}
