import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import "../theme"
import "../services"

// Workspace overview: one cell per workspace on the bar's monitor, each a
// scaled mini-screen showing live thumbnails of its windows (app icon
// fallback). Click a cell to switch. Opens on hover of the bar workspace dots.
Item {
    id: root

    // Bar monitor (logical geometry) the popout is anchored to.
    readonly property var scr: PopoutService.anchorScreen
    readonly property var hyprMon: scr ? Hyprland.monitorFor(scr) : null
    readonly property real _aspect: (scr && scr.height > 0) ? scr.width / scr.height : 1.6

    // Drag-and-drop state: dragging a window thumbnail to another cell moves it.
    property string _dragAddr:    ""
    property string _dragClass:   ""
    property var    _dragWayland: null   // toplevel handle → live preview in proxy
    readonly property bool _dragging: _dragAddr !== ""

    readonly property int cellH:   136
    readonly property int cellW:   Math.round(cellH * _aspect)
    readonly property int _cols:   Math.min(_wsList.length + 1, 3)   // +1 for the add cell

    // Per-monitor workspace numbering: eDP-1 = 1-10 (base 0), HDMI-A-1 = 11-20
    // (base 10). The bar/overview show the local number (id - base).
    readonly property int _base: hyprMon ? hyprMon.id * 10 : 0
    function _localNum(id) { return id - _base }

    // Move a window to a workspace without stealing focus / warping the cursor.
    function _moveWin(addr, wsId) {
        if (addr === "") return
        const a = Hyprland.activeToplevel
        const prev = (a && a.lastIpcObject) ? (a.lastIpcObject.address || "") : ""
        Hyprland.dispatch('hl.dsp.exec_cmd("' + Paths.script("movewin.sh") + ' ' + addr + ' ' + wsId + ' ' + prev + '")')
    }

    // Next free workspace in this monitor's range (max existing + 1, capped).
    readonly property int _nextWs: {
        let m = _base
        const l = _wsList
        for (let i = 0; i < l.length; i++) if (l[i].id > m) m = l[i].id
        return Math.min(m + 1, _base + 10)
    }
    readonly property int _gap:    ThemeManager.spacing
    readonly property int _pad:    ThemeManager.spacingLg

    // Normal workspaces on this monitor, sorted by id (skip special: id < 0).
    readonly property var _wsList: {
        const out = []
        const all = Hyprland.workspaces?.values ?? []
        for (let i = 0; i < all.length; i++) {
            const w = all[i]
            if (!w || w.id < 0) continue
            if (root.hyprMon && w.monitor !== root.hyprMon) continue
            out.push(w)
        }
        out.sort((a, b) => a.id - b.id)
        return out
    }

    // Other monitors (for the "Screens" section).
    readonly property var _otherMons: {
        const out = []
        const all = Hyprland.monitors?.values ?? []
        const myId = root.hyprMon ? root.hyprMon.id : -99
        for (let i = 0; i < all.length; i++)
            if (all[i] && all[i].id !== myId) out.push(all[i])
        return out
    }

    // Pull fresh geometry/window data when shown, and keep it current while open
    // (cross-monitor moves don't always emit an event that refreshes lastIpcObject).
    function _refresh() {
        Hyprland.refreshToplevels()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshMonitors()
    }
    onVisibleChanged: if (visible) _refresh()
    Timer {
        running: root.visible
        interval: 700
        repeat: true
        onTriggered: root._refresh()
    }

    implicitWidth:  _pad * 2 + Math.max(_col.implicitWidth, cellW)
    implicitHeight: _pad * 2 + _col.implicitHeight

    ColumnLayout {
        id: _col
        anchors.fill: parent
        anchors.margins: root._pad
        spacing: ThemeManager.spacing

        Text {
            id: _title
            text: "Espaces de travail"
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            Layout.alignment: Qt.AlignHCenter
        }

        Grid {
            id: _grid
            Layout.alignment: Qt.AlignHCenter
            columns: Math.max(1, root._cols)
            rowSpacing: root._gap
            columnSpacing: root._gap

            Repeater {
                model: root._wsList

                delegate: Rectangle {
                    id: cell
                    required property var modelData          // HyprlandWorkspace
                    readonly property bool focused: modelData.focused
                    readonly property bool active:  modelData.active
                    property bool dropHover: false

                    width:  root.cellW
                    height: root.cellH
                    radius: ThemeManager.chipRadius
                    color:  ThemeManager.surfaceContainer
                    border.width: (focused || dropHover) ? 2 : 1
                    border.color: dropHover ? ThemeManager.tertiary
                                  : focused ? ThemeManager.primary
                                            : Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.10)
                    clip: true

                    // Drop target: a window dropped here moves to this workspace (silent).
                    DropArea {
                        anchors.fill: parent
                        onEntered:  cell.dropHover = true
                        onExited:   cell.dropHover = false
                        onDropped:  (drop) => {
                            cell.dropHover = false
                            if (root._dragAddr !== "")
                                root._moveWin(root._dragAddr, cell.modelData.id)
                        }
                    }

                    // Windows in this workspace, positioned + scaled to the cell.
                    Repeater {
                        model: cell.modelData.toplevels?.values ?? []
                        delegate: Item {
                            id: winItem
                            required property var modelData   // HyprlandToplevel
                            readonly property var ipc: modelData.lastIpcObject ?? ({})
                            readonly property real _sw: root.scr && root.scr.width  > 0 ? root.scr.width  : 1
                            readonly property real _sh: root.scr && root.scr.height > 0 ? root.scr.height : 1
                            readonly property bool _ok: ipc.at !== undefined && ipc.size !== undefined

                            z: 1                              // above the cell's activate MouseArea
                            visible: _ok
                            // Hide from its cell while being dragged ("disappears")
                            opacity: (root._dragging && root._dragAddr === (ipc.address ?? "_")) ? 0 : 1
                            x:      _ok ? cell.width  * Math.max(0, Math.min(1, (ipc.at[0]   - (root.scr?.x ?? 0)) / _sw)) : 0
                            y:      _ok ? cell.height * Math.max(0, Math.min(1, (ipc.at[1]   - (root.scr?.y ?? 0)) / _sh)) : 0
                            width:  _ok ? cell.width  * Math.max(0.04, Math.min(1, ipc.size[0] / _sw)) : 0
                            height: _ok ? cell.height * Math.max(0.04, Math.min(1, ipc.size[1] / _sh)) : 0

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 3
                                color: ThemeManager.surfaceContainerHigh
                                border.width: 1
                                border.color: Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)
                                clip: true

                                // App icon fallback (behind the thumbnail)
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: Math.max(12, Math.min(parent.width, parent.height) * 0.5)
                                    source: Quickshell.iconPath((winItem.ipc.class ?? "").toLowerCase(), "application-x-executable")
                                    visible: !_thumb.hasContent
                                }

                                // Live thumbnail (only the focused workspace renders reliably)
                                ScreencopyView {
                                    id: _thumb
                                    anchors.fill: parent
                                    captureSource: winItem.modelData.wayland ?? null   // qmllint disable unresolved-type
                                    live: root.visible && cell.focused
                                    paintCursor: false
                                    opacity: hasContent ? 1 : 0
                                }
                            }

                            // Drag to another cell to move the window; plain click
                            // switches to this workspace.
                            MouseArea {
                                id: _winMa
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: root._dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                property bool _moved: false
                                onPressed: _moved = false
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                    const g = mapToItem(root, m.x, m.y)
                                    _dragProxy.x = g.x - _dragProxy.width / 2
                                    _dragProxy.y = g.y - _dragProxy.height / 2
                                    if (!root._dragging) {
                                        root._dragAddr    = winItem.ipc.address ?? ""
                                        root._dragClass   = (winItem.ipc.class ?? "")
                                        root._dragWayland = winItem.modelData.wayland
                                    }
                                    _moved = true
                                }
                                onReleased: {
                                    if (root._dragging) _dragProxy.Drag.drop()
                                    root._dragAddr    = ""
                                    root._dragWayland = null
                                    if (!_moved) { cell.modelData.activate(); PopoutService.close() }
                                }
                            }
                        }
                    }

                    // Workspace id badge
                    Rectangle {
                        anchors { top: parent.top; left: parent.left; margins: 5 }
                        width: 18; height: 18; radius: 9
                        color: cell.focused ? ThemeManager.primary
                                            : Qt.rgba(ThemeManager.surface.r, ThemeManager.surface.g, ThemeManager.surface.b, 0.7)
                        Text {
                            anchors.centerIn: parent
                            text: root._localNum(cell.modelData.id)
                            color: cell.focused ? ThemeManager.onPrimary : ThemeManager.onSurface
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: 11; font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) cell.color = ThemeManager.surfaceContainerHigh
                                                else cell.color = ThemeManager.surfaceContainer
                        onClicked: { cell.modelData.activate(); PopoutService.close() }
                    }
                }
            }

            // Add-workspace cell
            Rectangle {
                id: _addCell
                property bool dropHover: false
                width:  root.cellW
                height: root.cellH
                radius: ThemeManager.chipRadius
                color:  (_addMa.containsMouse || dropHover) ? ThemeManager.surfaceContainerHigh : ThemeManager.surfaceContainer
                border.width: dropHover ? 2 : 1
                border.color: dropHover ? ThemeManager.tertiary
                                        : Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.35)

                // Drop a window here → move it to a brand-new workspace
                DropArea {
                    anchors.fill: parent
                    onEntered: _addCell.dropHover = true
                    onExited:  _addCell.dropHover = false
                    onDropped: (drop) => {
                        _addCell.dropHover = false
                        if (root._dragAddr !== "")
                            root._moveWin(root._dragAddr, root._nextWs)
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰐕"
                        color: ThemeManager.primary
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 28
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Espace " + root._localNum(root._nextWs)
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                    }
                }

                MouseArea {
                    id: _addMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Hyprland.dispatch("hl.dsp.focus({workspace = " + root._nextWs + "})")
                        PopoutService.close()
                    }
                }
            }
        }

        // ── Screens: other monitors (their active workspace only) ─────────────
        Text {
            visible: root._otherMons.length > 0
            text: "Écrans"
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: ThemeManager.spacing
        }
        Row {
            visible: root._otherMons.length > 0
            Layout.alignment: Qt.AlignHCenter
            spacing: root._gap
            Repeater {
                model: root._otherMons
                delegate: ScreenCell {
                    required property var modelData   // HyprlandMonitor
                    mon: modelData
                }
            }
        }
    }

    // Cell representing another monitor's active workspace: shows its windows,
    // accepts dropped windows (→ move to that monitor), click focuses it.
    component ScreenCell: Rectangle {
        id: sc
        property var mon                                   // HyprlandMonitor
        readonly property var ipc: mon?.lastIpcObject ?? ({})
        readonly property var aws: mon?.activeWorkspace ?? null
        readonly property real _scale: ipc.scale ? ipc.scale : 1
        readonly property real _lw: ipc.width  ? ipc.width  / _scale : 1
        readonly property real _lh: ipc.height ? ipc.height / _scale : 1
        readonly property real _mx: ipc.x ?? 0
        readonly property real _my: ipc.y ?? 0
        property bool dropHover: false

        height: root.cellH
        width:  Math.round(root.cellH * (_lh > 0 ? _lw / _lh : 1.6))
        radius: ThemeManager.chipRadius
        color:  ThemeManager.surfaceContainer
        border.width: dropHover ? 2 : 1
        border.color: dropHover ? ThemeManager.tertiary
                                : Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.10)
        clip: true

        DropArea {
            anchors.fill: parent
            onEntered: sc.dropHover = true
            onExited:  sc.dropHover = false
            onDropped: (drop) => {
                sc.dropHover = false
                if (root._dragAddr !== "" && sc.aws)
                    root._moveWin(root._dragAddr, sc.aws.id)
            }
        }

        // Windows in this monitor's active workspace
        Repeater {
            model: sc.aws ? (sc.aws.toplevels?.values ?? []) : []
            delegate: Item {
                id: scWin
                required property var modelData
                readonly property var wipc: modelData.lastIpcObject ?? ({})
                readonly property bool _ok: wipc.at !== undefined && wipc.size !== undefined
                z: 1
                visible: _ok
                opacity: (root._dragging && root._dragAddr === (wipc.address ?? "_")) ? 0 : 1
                x:      _ok ? sc.width  * Math.max(0, Math.min(1, (wipc.at[0]   - sc._mx) / sc._lw)) : 0
                y:      _ok ? sc.height * Math.max(0, Math.min(1, (wipc.at[1]   - sc._my) / sc._lh)) : 0
                width:  _ok ? sc.width  * Math.max(0.04, Math.min(1, wipc.size[0] / sc._lw)) : 0
                height: _ok ? sc.height * Math.max(0.04, Math.min(1, wipc.size[1] / sc._lh)) : 0

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 3
                    color: ThemeManager.surfaceContainerHigh
                    border.width: 1
                    border.color: Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)
                    clip: true
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: Math.max(12, Math.min(parent.width, parent.height) * 0.5)
                        source: Quickshell.iconPath((scWin.wipc.class ?? "").toLowerCase(), "application-x-executable")
                        visible: !_scThumb.hasContent
                    }
                    ScreencopyView {
                        id: _scThumb
                        anchors.fill: parent
                        captureSource: scWin.modelData.wayland ?? null   // qmllint disable unresolved-type
                        live: root.visible
                        paintCursor: false
                        opacity: hasContent ? 1 : 0
                    }
                }

                // Drag to another cell/screen to move; plain click focuses this screen.
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: root._dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    property bool _moved: false
                    onPressed: _moved = false
                    onPositionChanged: (m) => {
                        if (!pressed) return
                        const g = mapToItem(root, m.x, m.y)
                        _dragProxy.x = g.x - _dragProxy.width / 2
                        _dragProxy.y = g.y - _dragProxy.height / 2
                        if (!root._dragging) {
                            root._dragAddr    = scWin.wipc.address ?? ""
                            root._dragClass   = (scWin.wipc.class ?? "")
                            root._dragWayland = scWin.modelData.wayland
                        }
                        _moved = true
                    }
                    onReleased: {
                        if (root._dragging) _dragProxy.Drag.drop()
                        root._dragAddr    = ""
                        root._dragWayland = null
                        if (!_moved && sc.aws) { sc.aws.activate(); PopoutService.close() }
                    }
                }
            }
        }

        // Monitor name + active workspace badge
        Rectangle {
            anchors { top: parent.top; left: parent.left; margins: 5 }
            height: 18; radius: 9
            width: _scLabel.implicitWidth + 14
            color: Qt.rgba(ThemeManager.surface.r, ThemeManager.surface.g, ThemeManager.surface.b, 0.75)
            Text {
                id: _scLabel
                anchors.centerIn: parent
                text: (sc.mon?.name ?? "?")
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily
                font.pixelSize: 10; font.weight: Font.Bold
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: sc.color = containsMouse ? ThemeManager.surfaceContainerHigh : ThemeManager.surfaceContainer
            onClicked: { if (sc.aws) sc.aws.activate(); PopoutService.close() }
        }
    }

    // Floating drag proxy: a live preview of the window following the cursor.
    Item {
        id: _dragProxy
        width: 132
        height: Math.round(132 / root._aspect)
        z: 1000
        visible: root._dragging
        Drag.active:    root._dragging
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: ThemeManager.surfaceContainerHigh
            border.width: 2
            border.color: ThemeManager.primary
            opacity: 0.97
            clip: true

            IconImage {
                anchors.centerIn: parent
                implicitSize: 32
                source: Quickshell.iconPath(root._dragClass.toLowerCase(), "application-x-executable")
                visible: !_proxyThumb.hasContent
            }
            ScreencopyView {
                id: _proxyThumb
                anchors.fill: parent
                anchors.margins: 2
                captureSource: root._dragWayland   // qmllint disable unresolved-type
                live: root._dragging
                paintCursor: false
                opacity: hasContent ? 1 : 0
            }
        }
    }
}
