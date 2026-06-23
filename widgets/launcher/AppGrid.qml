import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../theme"
import "../../services"

// A titled fixed-column grid of app tiles.
//   activated(app)        — click / keyboard-enter
//   reordered(from, to)   — drag reorder (only when `draggable`)
//   contextRequested(app, mx, my) — right-click (9e)
// `selectedIndex` highlights one tile for keyboard navigation (-1 = none).
ColumnLayout {
    id: root

    property string title: ""
    property var    apps:  []          // list of DesktopEntry
    property int    columns: 6
    property int    selectedIndex: -1
    property bool   draggable: false
    property real   tileW: 92
    property real   tileH: 92

    signal activated(var app)
    signal reordered(int from, int to)
    signal contextRequested(var app, real mx, real my)
    // Drag proxy is rendered by the parent (outside the clipped Flickable) so it
    // isn't cut off at the grid edges. Coords are window-space (mapToItem null).
    signal dragMove(var app, real wx, real wy)
    signal dragEnd()

    spacing: 8

    // ── Drag state ────────────────────────────────────────────────────────────
    property int  _dragFrom: -1
    property int  _hoverIdx: -1
    // Bar position taken from the CURSOR (not reconstructed from the slot), so the
    // right edge of a row stays in that row instead of wrapping to the next.
    property int  _barRow: 0
    property int  _barCol: 0

    // Insertion slot (0..N) for a cursor position — the gap BETWEEN tiles.
    function _insertAt(gx, gy) {
        const cw = tileW + _grid.columnSpacing
        const ch = tileH + _grid.rowSpacing
        let row = Math.floor(gy / ch)
        const maxRow = Math.floor(Math.max(0, apps.length - 1) / columns)
        row = Math.max(0, Math.min(row, maxRow))
        let col = Math.round(gx / cw)               // nearest gap: 0..columns
        col = Math.max(0, Math.min(col, columns))
        let idx = row * columns + col
        return Math.max(0, Math.min(idx, apps.length))
    }

    Text {
        visible: root.title.length > 0
        text: root.title
        color: ThemeManager.onSurfaceVariant
        font.family: ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeSm
        font.bold: true
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: _grid.implicitHeight

        Grid {
            id: _grid
            columns: root.columns
            columnSpacing: 6
            rowSpacing: 6

            Repeater {
                model: root.apps
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    width:  root.tileW
                    height: root.tileH
                    radius: ThemeManager.chipRadius

                    readonly property bool _selected: root.selectedIndex === index
                    readonly property bool _dragging: root._dragFrom === index
                    opacity: _dragging ? 0.25 : 1.0
                    color: _selected ? ThemeManager.secondaryContainer
                           : (_ma.containsMouse ? ThemeManager.surfaceContainerHigh : "transparent")
                    border.width: _selected ? 2 : 0
                    border.color: ThemeManager.primary

                    MouseArea {
                        id: _ma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // Keep the grab during a drag so the parent Flickable can't
                        // steal it (which would swallow the release → stuck proxy).
                        preventStealing: root.draggable
                        property bool _moved: false
                        property real _sx: 0
                        property real _sy: 0

                        onPressed: (m) => {
                            _moved = false; _sx = m.x; _sy = m.y
                        }
                        onPositionChanged: (m) => {
                            if (!root.draggable || !(m.buttons & Qt.LeftButton)) return
                            if (!_moved && Math.hypot(m.x - _sx, m.y - _sy) > 8) {
                                _moved = true
                                root._dragFrom = tile.index
                            }
                            if (_moved) {
                                const wp = mapToItem(null, m.x, m.y)   // window coords
                                root.dragMove(tile.modelData, wp.x, wp.y)
                                const gp = mapToItem(_grid, m.x, m.y)
                                const cw = root.tileW + _grid.columnSpacing
                                const ch = root.tileH + _grid.rowSpacing
                                const maxRow = Math.floor(Math.max(0, root.apps.length - 1) / root.columns)
                                const row = Math.max(0, Math.min(Math.floor(gp.y / ch), maxRow))
                                let col = Math.max(0, Math.min(Math.round(gp.x / cw), root.columns))
                                const inRow = Math.min(root.columns, root.apps.length - row * root.columns)
                                if (col > inRow) col = inRow      // can't insert past the last item in a row
                                root._barRow = row
                                root._barCol = col
                                root._hoverIdx = Math.min(row * root.columns + col, root.apps.length)
                            }
                        }
                        onReleased: (m) => {
                            // Capture, then RESET STATE FIRST: reordered() rebuilds
                            // the pinned model and destroys this delegate, so any
                            // code after the emit would never run (stuck proxy).
                            const moved = _moved
                            const from  = root._dragFrom
                            const hover = root._hoverIdx
                            const btn   = m.button
                            const ctx   = (!moved && btn === Qt.RightButton) ? mapToItem(null, m.x, m.y) : null
                            const app   = tile.modelData
                            root._dragFrom = -1; root._hoverIdx = -1; _moved = false
                            root.dragEnd()

                            if (moved && from >= 0) {
                                // hover is an insertion slot; dropping at `from` or
                                // `from+1` leaves the item where it is → no-op.
                                if (hover >= 0 && hover !== from && hover !== from + 1)
                                    root.reordered(from, hover)
                            } else if (btn === Qt.RightButton && ctx) {
                                root.contextRequested(app, ctx.x, ctx.y)
                            } else if (btn === Qt.LeftButton) {
                                root.activated(app)
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        IconImage {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 40
                            source: AppService.iconFor(tile.modelData)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: tile.modelData?.name ?? ""
                            color: ThemeManager.onSurface
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }

        // Insertion bar — shows the gap where the dragged app will land. Position
        // comes from the cursor (_barRow/_barCol), so the right edge of a row stays
        // in that row.
        Rectangle {
            visible: root.draggable && root._dragFrom >= 0 && root._hoverIdx >= 0
            readonly property real _gridW: root.columns * root.tileW + (root.columns - 1) * _grid.columnSpacing
            readonly property real _rawX: _grid.x + root._barCol * (root.tileW + _grid.columnSpacing) - _grid.columnSpacing / 2 - 1
            // Keep the bar inside the grid at the left/right edges (else clipped).
            x: Math.max(_grid.x, Math.min(_rawX, _grid.x + _gridW - width))
            y: _grid.y + root._barRow * (root.tileH + _grid.rowSpacing)
            width: 3
            height: root.tileH
            radius: 1.5
            color: ThemeManager.primary
            z: 50
            Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        }
    }
}
