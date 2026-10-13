import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import "../theme"
import "../services"
import "../widgets/launcher"

// Windows 11-style start menu — CONTENT ONLY (no window).
// MainWindow draws the blob surface (merged into the bottom screen border),
// positions/animates it, and owns keyboard focus + the input mask. This item
// holds the search field, pinned/recommended/results grids, keyboard nav and
// the context menu. Phases 9a–9f.
Item {
    id: root

    // Driven by MainWindow's loader: true while open on this screen.
    property bool active: false

    onActiveChanged: {
        if (active) {
            _pinnedPage = 0
            LauncherService.query = ""
            Qt.callLater(() => _search.forceActiveFocus())
        }
    }
    Component.onCompleted: if (active) _search.forceActiveFocus()

    // ── Data ──────────────────────────────────────────────────────────────────
    readonly property var _pinnedKeys: PinnedService.pinned
    readonly property var _pinned:
        _pinnedKeys.map(k => AppService.byKey(k)).filter(a => a)
    readonly property var _recommended:
        AppUsageService.recommended(_pinnedKeys, 6)
            .map(k => AppService.byKey(k)).filter(a => a)

    // Pinned pagination (tabs on overflow): cols × 3 rows per page.
    readonly property int _pinPageSize: _cols * 3
    readonly property int _pinnedPages: Math.max(1, Math.ceil(_pinned.length / _pinPageSize))
    property int _pinnedPage: 0
    readonly property int _pinPageOff: _pinnedPage * _pinPageSize
    readonly property var _pinnedPageApps: _pinned.slice(_pinPageOff, _pinPageOff + _pinPageSize)
    Connections {
        target: PinnedService
        function onPinnedChanged() {
            if (root._pinnedPage >= root._pinnedPages) root._pinnedPage = root._pinnedPages - 1
            if (root._pinnedPage < 0) root._pinnedPage = 0
        }
    }

    // ── Search ────────────────────────────────────────────────────────────────
    readonly property string _q: LauncherService.query.trim()
    readonly property bool   _searching: _q.length > 0
    // A "=" query is a calculation only; plain arithmetic still lists apps below.
    readonly property var    _results: (_searching && !_q.startsWith("=")) ? AppService.search(_q).slice(0, 40) : []

    // Calculator help: clicking an example puts it in the search field.
    readonly property var _calcHelp: [
        { ex: "2 ^ 10",     desc: "power" },
        { ex: "17 % 5",     desc: "remainder" },
        { ex: "sqrt(2)",    desc: "square root" },
        { ex: "abs(-3)",    desc: "absolute value" },
        { ex: "sin(pi/2)",  desc: "sin, cos, tan (radians)" },
        { ex: "asin(1)",    desc: "asin, acos, atan" },
        { ex: "ln(e)",      desc: "natural log" },
        { ex: "log(1000)",  desc: "base-10 log" },
        { ex: "exp(2)",     desc: "e to the power" },
        { ex: "round(2.5)", desc: "round, floor, ceil" }
    ]
    readonly property var _calcHelpQalc: [
        { ex: "5 km to miles",   desc: "units" },
        { ex: "100 USD to EUR",  desc: "currencies (ISO codes)" },
        { ex: "20 C to F",       desc: "temperatures (C, F, K)" }
    ]
    function _tryExample(ex) {
        LauncherService.query = "= " + ex
        _search.cursorPosition = _search.text.length
        _search.forceActiveFocus()
    }

    // Copy the calculator result and close, as Enter does with nothing selected.
    function _copyResult() {
        if (CalculatorService.result === "") return
        CalculatorService.copy()
        LauncherService.hide()
    }

    function _launch(app) {
        if (!app) return
        AppService.launch(app)
        LauncherService.hide()
    }

    // ── Keyboard navigation (2D grid in every section) ────────────────────────
    //   _sec: "none" | "results" | "pinned" | "reco"   _idx: index within section
    property string _sec: "none"
    property int    _idx: -1
    readonly property int _cols: 6

    function _resetSel() { _sec = _searching ? "results" : "none"; _idx = -1 }

    function _list(sec) {
        if (sec === "results") return _results
        if (sec === "pinned")  return _pinnedPageApps
        if (sec === "reco")    return _recommended
        return []
    }

    function _navDown() {
        if (_searching) {
            if (_idx < 0) { if (_results.length) _idx = 0; return }
            const ni = _idx + _cols
            if (ni < _results.length) _idx = ni
            return
        }
        if (_sec === "none") { if (_pinnedPageApps.length) { _sec = "pinned"; _idx = 0 } return }
        if (_sec === "pinned") {
            const ni = _idx + _cols
            if (ni < _pinnedPageApps.length) _idx = ni
            else if (_recommended.length) { _sec = "reco"; _idx = Math.min(_idx % _cols, _recommended.length - 1) }
            return
        }
        if (_sec === "reco") {
            const ni = _idx + _cols
            if (ni < _recommended.length) _idx = ni
        }
    }
    function _navUp() {
        if (_searching) {
            const ni = _idx - _cols
            _idx = ni >= 0 ? ni : -1
            return
        }
        if (_sec === "reco") {
            const ni = _idx - _cols
            if (ni >= 0) _idx = ni
            else if (_pinnedPageApps.length) {
                const lastRow = Math.floor((_pinnedPageApps.length - 1) / _cols) * _cols
                _sec = "pinned"; _idx = Math.min(lastRow + (_idx % _cols), _pinnedPageApps.length - 1)
            }
            return
        }
        if (_sec === "pinned") {
            const ni = _idx - _cols
            if (ni >= 0) _idx = ni
            else { _sec = "none"; _idx = -1 }
        }
    }
    function _navLeft() {
        if (_searching) {
            if (_idx > 0) _idx--
            else if (_idx < 0 && _results.length) _idx = 0
            return
        }
        if (_sec === "none") return
        if (_sec === "pinned" && _idx % _cols === 0) {
            if (_pinnedPage > 0) { _pinnedPage--; _idx = Math.min(_idx + _cols - 1, _pinnedPageApps.length - 1) }
            return
        }
        if (_idx > 0) _idx--
    }
    function _navRight() {
        if (_searching) {
            if (_idx < _results.length - 1) _idx = Math.max(_idx + 1, 0)
            return
        }
        if (_sec === "none") return
        const l = _list(_sec)
        if (_sec === "pinned" && (_idx % _cols === _cols - 1 || _idx === l.length - 1)) {
            if (_pinnedPage < _pinnedPages - 1) {
                _pinnedPage++
                _idx = Math.min(_idx - (_idx % _cols), _pinnedPageApps.length - 1)
            }
            return
        }
        if (_idx < l.length - 1) _idx++
    }

    function _activateSel() {
        if (_searching && _idx < 0 && CalculatorService.active) { _copyResult(); return }
        if (_searching) { _launch(_idx >= 0 ? (_results[_idx] ?? null) : (_results[0] ?? null)); return }
        const l = _list(_sec)
        if (_idx >= 0 && _idx < l.length) _launch(l[_idx])
    }

    // ── Context menu ────────────────────────────────────────────────────────--
    property bool _menuOpen: false
    property var  _menuItems: []
    property int  _menuSel: 0
    property real _menuX: 0
    property real _menuY: 0

    // Drag proxy (rendered at root, above the clipped Flickable)
    property var  _dragApp: null
    property real _dragX: 0
    property real _dragY: 0

    function _openMenuFor(section, app, sx, sy) {
        if (!app) return
        const key = AppService.keyOf(app)
        const items = []
        items.push({ label: "Launch", danger: false, run: () => root._launch(app) })
        if (section === "pinned") {
            items.push({ label: "Unpin", danger: true, run: () => PinnedService.unpin(key) })
        } else {
            items.push(PinnedService.isPinned(key)
                ? { label: "Unpin", danger: true, run: () => PinnedService.unpin(key) }
                : { label: "Pin",   danger: false, run: () => PinnedService.pin(key) })
        }
        if (section === "reco")
            items.push({ label: "Remove from recommended", danger: true, run: () => AppUsageService.reset(key) })
        _menuItems = items
        _menuSel = 0
        // AppGrid emits scene coords → convert to this item's local space.
        const p = root.mapFromItem(null, sx, sy)
        _menuX = Math.min(Math.max(0, p.x), root.width  - 230)
        _menuY = Math.min(Math.max(0, p.y), root.height - (items.length * 36 + 12))
        _menuOpen = true
    }
    function _closeMenu() { _menuOpen = false; _menuItems = [] }
    function _menuDown() { if (_menuItems.length) _menuSel = (_menuSel + 1) % _menuItems.length }
    function _menuUp()   { if (_menuItems.length) _menuSel = (_menuSel - 1 + _menuItems.length) % _menuItems.length }
    function _menuRun()  {
        const it = _menuItems[_menuSel]
        _closeMenu()
        if (it && it.run) it.run()
    }

    // ── Content ─────────────────────────────────────────────────────────────--
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        anchors.bottomMargin: 22 + ThemeManager.borderWidth   // clear the bottom border strip
        spacing: 18

        // ── Search bar ────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: 22
            color: ThemeManager.surfaceContainerHigh
            border.width: _search.activeFocus ? 2 : 1
            border.color: _search.activeFocus ? ThemeManager.primary
                                              : ThemeManager.outlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    text: ""
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 16
                    color: ThemeManager.onSurfaceVariant
                }
                TextField {
                    id: _search
                    Layout.fillWidth: true
                    background: null
                    color: ThemeManager.onSurface
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 15
                    placeholderText: "Search apps, or = to calculate…"
                    placeholderTextColor: ThemeManager.onSurfaceVariant
                    verticalAlignment: TextInput.AlignVCenter
                    text: LauncherService.query
                    onTextChanged: {
                        if (text !== LauncherService.query) LauncherService.query = text
                        root._resetSel()
                    }
                    onAccepted: { if (root._menuOpen) root._menuRun(); else root._activateSel() }
                    Keys.onDownPressed:  (e) => { if (root._menuOpen) root._menuDown(); else root._navDown(); e.accepted = true }
                    Keys.onUpPressed:    (e) => { if (root._menuOpen) root._menuUp();   else root._navUp();   e.accepted = true }
                    // Left/Right edit the text until Down enters the grid; then they move
                    // between apps.
                    Keys.onLeftPressed:  (e) => { if (root._idx < 0 && !root._menuOpen) { e.accepted = false; return } if (!root._menuOpen) root._navLeft();  e.accepted = true }
                    Keys.onRightPressed: (e) => { if (root._idx < 0 && !root._menuOpen) { e.accepted = false; return } if (!root._menuOpen) root._navRight(); e.accepted = true }
                    Keys.onEscapePressed: {
                        if (root._menuOpen) root._closeMenu()
                        else if (root._searching) LauncherService.query = ""
                        else LauncherService.hide()
                    }
                }
            }
        }

        // ── Content: search results OR pinned + recommended ───────────────────
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: _content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: _content
                width: parent.width
                spacing: 14

                // ── Calculator result ─────────────────────────────────────────
                Rectangle {
                    id: _calcCard
                    visible: CalculatorService.active
                    Layout.fillWidth: true
                    implicitHeight: 64
                    radius: ThemeManager.chipRadius + 4
                    color: _calcHov.hovered && CalculatorService.result !== ""
                        ? Qt.lighter(ThemeManager.surfaceContainerHigh, 1.15) : ThemeManager.surfaceContainerHigh
                    border.width: root._idx < 0 ? 2 : 1
                    border.color: root._idx < 0 ? ThemeManager.primary : ThemeManager.outlineVariant

                    readonly property string _status: {
                        if (CalculatorService.result !== "") return ""
                        if (CalculatorService.busy) return "…"
                        if (CalculatorService.needsQalc) return "Install libqalculate (qalc) for units and conversions"
                        if (CalculatorService.hint !== "") return CalculatorService.hint
                        return "Can't calculate this"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 14
                        Text {
                            text: "󰃬"
                            color: ThemeManager.primary
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: 22
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: CalculatorService.expr
                                color: ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily
                                font.pixelSize: ThemeManager.fontSizeSm
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: CalculatorService.result !== "" ? "= " + CalculatorService.result : _calcCard._status
                                color: CalculatorService.result !== "" ? ThemeManager.onSurface : ThemeManager.onSurfaceVariant
                                font.family: ThemeManager.fontFamily
                                font.pixelSize: CalculatorService.result !== "" ? 20 : ThemeManager.fontSizeSm
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            visible: CalculatorService.result !== ""
                            text: "Enter to copy"
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeXs
                        }
                    }
                    HoverHandler { id: _calcHov; cursorShape: CalculatorService.result !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { onTapped: root._copyResult() }
                }

                // ── Calculator help ───────────────────────────────────────────
                Rectangle {
                    visible: CalculatorService.active
                    Layout.fillWidth: true
                    implicitHeight: _helpCol.implicitHeight + 24
                    radius: ThemeManager.chipRadius + 4
                    color: ThemeManager.surfaceContainer

                    ColumnLayout {
                        id: _helpCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            columnSpacing: 10
                            rowSpacing: 4
                            Repeater {
                                model: root._calcHelp.concat(CalculatorService.hasQalc ? root._calcHelpQalc : [])
                                delegate: HelpItem { required property var modelData; ex: modelData.ex; desc: modelData.desc }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: "Constants pi and e. \"1,5\" works like 1.5 and \"2x3\" like 2*3. Click an example to try it, Enter copies the result."
                                + (CalculatorService.hasQalc ? "" : " Install libqalculate (qalc) for units, conversions and currencies.")
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeXs
                        }
                    }
                }

                AppGrid {
                    visible: root._results.length > 0
                    Layout.fillWidth: true
                    title: "Results"
                    apps: root._results
                    columns: root._cols
                    selectedIndex: root._sec === "results" ? root._idx : -1
                    onActivated: app => root._launch(app)
                    onContextRequested: (app, mx, my) => root._openMenuFor("results", app, mx, my)
                }

                AppGrid {
                    visible: !root._searching
                    Layout.fillWidth: true
                    title: "Pinned"
                    apps: root._pinnedPageApps
                    columns: root._cols
                    selectedIndex: root._sec === "pinned" ? root._idx : -1
                    draggable: true
                    onActivated: app => root._launch(app)
                    // Reorder by key (display list is filtered/paginated, so raw
                    // indices would desync from PinnedService's key array).
                    onReordered: (from, to) => {
                        const movedApp = root._pinnedPageApps[from]
                        if (!movedApp) return
                        const tgtIdx    = root._pinPageOff + to
                        const beforeApp = tgtIdx < root._pinned.length ? root._pinned[tgtIdx] : null
                        PinnedService.moveBefore(AppService.keyOf(movedApp),
                                                 beforeApp ? AppService.keyOf(beforeApp) : "")
                    }
                    onContextRequested: (app, mx, my) => root._openMenuFor("pinned", app, mx, my)
                    onDragMove: (app, wx, wy) => {
                        root._dragApp = app
                        const p = root.mapFromItem(null, wx, wy)
                        root._dragX = p.x - 46
                        root._dragY = p.y - 46
                    }
                    onDragEnd: root._dragApp = null
                }

                RowLayout {
                    visible: !root._searching && root._pinnedPages > 1
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    Repeater {
                        model: root._pinnedPages
                        delegate: Rectangle {
                            required property int index
                            implicitWidth: index === root._pinnedPage ? 22 : 8
                            implicitHeight: 8
                            radius: 4
                            color: index === root._pinnedPage ? ThemeManager.primary
                                                              : ThemeManager.outlineVariant
                            Behavior on implicitWidth { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            TapHandler { onTapped: { root._pinnedPage = index; root._idx = 0 } }
                        }
                    }
                }

                AppGrid {
                    visible: !root._searching && root._recommended.length > 0
                    Layout.fillWidth: true
                    title: "Recommended"
                    apps: root._recommended
                    columns: root._cols
                    selectedIndex: root._sec === "reco" ? root._idx : -1
                    onActivated: app => root._launch(app)
                    onContextRequested: (app, mx, my) => root._openMenuFor("reco", app, mx, my)
                }

                Item {
                    visible: !root._searching && root._recommended.length === 0
                    Layout.fillWidth: true
                    implicitHeight: 40
                    Text {
                        anchors.centerIn: parent
                        text: "Recommended apps appear here as you use them"
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                    }
                }
            }
        }
    }

    // ── Drag proxy (above the clipped Flickable, follows the cursor) ──────────
    Rectangle {
        visible: root._dragApp !== null
        x: root._dragX
        y: root._dragY
        width: 92; height: 92
        radius: ThemeManager.chipRadius
        color: ThemeManager.surfaceContainerHigh
        border.width: 2
        border.color: ThemeManager.primary
        opacity: 0.92
        z: 300
        IconImage {
            anchors.centerIn: parent
            implicitSize: 40
            source: root._dragApp ? AppService.iconFor(root._dragApp) : ""
        }
    }

    // ── Context menu overlay (local coords) ───────────────────────────────────
    MouseArea {
        anchors.fill: parent
        visible: root._menuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root._closeMenu()
    }
    Rectangle {
        visible: root._menuOpen
        x: root._menuX
        y: root._menuY
        width: 220
        implicitHeight: _menuCol.implicitHeight + 8
        height: implicitHeight
        radius: ThemeManager.chipRadius
        color: ThemeManager.surfaceContainerHigh
        border.width: 1
        border.color: ThemeManager.outlineVariant
        z: 200

        Column {
            id: _menuCol
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: root._menuItems
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 36
                    radius: ThemeManager.chipRadius
                    readonly property bool _sel: root._menuSel === index
                    color: (_sel || _mh.hovered) ? ThemeManager.secondaryContainer : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        text: modelData.label
                        color: modelData.danger ? ThemeManager.error : ThemeManager.onSurface
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeMd
                    }
                    HoverHandler { id: _mh; onHoveredChanged: if (hovered) root._menuSel = index }
                    TapHandler { onTapped: root._menuRun() }
                }
            }
        }
    }

    // One calculator help entry: a clickable example and what it does.
    component HelpItem: RowLayout {
        id: hi
        property string ex: ""
        property string desc: ""
        Layout.columnSpan: 2
        Layout.fillWidth: true
        Layout.preferredWidth: 1   // both columns share the width equally
        spacing: 8
        Rectangle {
            implicitWidth: _hiText.implicitWidth + 12
            implicitHeight: 22
            radius: ThemeManager.chipRadius
            color: _hiHov.hovered ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.22)
                                  : Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.1)
            Text {
                id: _hiText
                anchors.centerIn: parent
                text: hi.ex
                color: ThemeManager.primary
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm
            }
            HoverHandler { id: _hiHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root._tryExample(hi.ex) }
        }
        Text {
            Layout.fillWidth: true
            text: hi.desc
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            elide: Text.ElideRight
        }
    }
}
