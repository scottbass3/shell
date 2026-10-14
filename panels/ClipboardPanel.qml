import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../theme"
import "../services"

// Clipboard history picker — CONTENT ONLY. MainWindow draws the blob surface,
// animates it and owns keyboard focus, as for the launcher. Data comes from
// ClipboardService (the clipd daemon). Two tabs: the history, and the pinned
// entries grouped by category, reordered by drag and drop.
Item {
    id: root

    property bool active: false

    onActiveChanged: {
        if (active) {
            _idx = -1
            _pidx = -1
            _follow = null
            _confirmClear = false
            _creating = false
            _renaming = null
            _closeMenu()
            _cancelDrag()
            _focusSearch()
        }
    }
    Component.onCompleted: if (active) _search.forceActiveFocus()

    function _focusSearch() { Qt.callLater(() => _search.forceActiveFocus()) }

    property string _tab: "history"   // "history" | "pinned"
    function _switchTab() {
        _tab = _tab === "history" ? "pinned" : "history"
        _follow = null
        _closeMenu()
        _creating = false
        _renaming = null
    }

    readonly property var  _entries: ClipboardService.entries
    readonly property bool _searching: ClipboardService.query.trim() !== ""

    // ── Pinned rows: a header per category, then its pins ────────────────────
    // Pins are filtered here (the daemon only searches the history); a
    // category without pins keeps an "empty" row to drop onto.
    readonly property var _words: ClipboardService.query.toLowerCase().split(/\s+/).filter(w => w !== "")
    function _matches(e) {
        const text = (e.preview || "").toLowerCase()
        return _words.every(w => text.includes(w))
    }
    readonly property var _groups:
        [{ id: null, name: "Uncategorized" }].concat(ClipboardService.categories)
    readonly property var _pinRows: {
        const rows = []
        for (const g of _groups) {
            const pins = ClipboardService.pins.filter(e => (e.pin.category ?? null) === g.id)
            if (g.id === null && pins.length === 0 && ClipboardService.categories.length > 0 && !_drag) continue
            rows.push({ type: "header", category: g.id, name: g.name, count: pins.length })
            const shown = pins.filter(e => _matches(e))
            for (const e of shown) rows.push({ type: "pin", category: g.id, entry: e })
            if (shown.length === 0) rows.push({ type: "empty", category: g.id, filtered: pins.length > 0 })
        }
        return rows
    }
    // Keyboard stops in the pinned tab: the pins, and the categories' headers
    // (to rename, delete or move them).
    readonly property var _pinNav:
        _pinRows.filter(r => r.type === "pin" || (r.type === "header" && r.category !== null))
    readonly property var _pinEntries: _pinRows.filter(r => r.type === "pin").map(r => r.entry)
    function _sameRow(a, b) {
        return !!a && !!b && a.type === b.type
            && (a.type === "pin" ? a.entry.id === b.entry.id : a.category === b.category)
    }
    function _showPinRow(r) {
        const row = _pinRows.findIndex(x => _sameRow(x, r))
        if (row >= 0) _pinList.positionViewAtIndex(row, ListView.Contain)
    }
    // Row moved by keyboard, kept selected through the refresh it causes.
    property var _follow: null
    on_PinNavChanged: {
        if (_follow) {
            const i = _pinNav.findIndex(r => _sameRow(r, _follow))
            if (i >= 0) { _pidx = i; _showPinRow(_pinNav[i]) }
        }
        if (_pidx >= _pinNav.length) _pidx = _pinNav.length - 1
    }

    // ── Selection: -1 = search field ─────────────────────────────────────────
    property int _idx: -1    // in _entries (history tab)
    property int _pidx: -1   // in _pinNav (pinned tab)
    on_EntriesChanged: if (_idx >= _entries.length) _idx = _entries.length - 1
    readonly property var _pinSel: _pidx >= 0 ? (_pinNav[_pidx] ?? null) : null
    readonly property bool _categorySelected: _tab === "pinned" && _pinSel?.type === "header"

    function _list()     { return _tab === "history" ? _entries : _pinNav }
    function _sel()      { return _tab === "history" ? _idx : _pidx }
    function _setSel(i)  { if (_tab === "history") _idx = i; else _pidx = i }
    // The entry Enter copies: the selected one, else the first.
    function _selected() {
        if (_tab === "history") return _idx >= 0 ? (_entries[_idx] ?? null) : (_entries[0] ?? null)
        if (_pinSel) return _pinSel.type === "pin" ? _pinSel.entry : null
        return _pinEntries[0] ?? null
    }
    function _selectedEntry() {
        if (_tab === "history") return _idx >= 0 ? (_entries[_idx] ?? null) : null
        return _pinSel?.type === "pin" ? _pinSel.entry : null
    }
    function _move(d) {
        _follow = null
        const l = _list()
        if (l.length === 0) return
        const i = Math.max(-1, Math.min(l.length - 1, _sel() + d))
        _setSel(i)
        if (i < 0) return
        if (_tab === "history") _historyList.positionViewAtIndex(i, ListView.Contain)
        else _showPinRow(l[i])
    }
    // Ctrl+Up/Down. A category moves among the categories. A pin moves within
    // its category, and past its first or last place into the previous or
    // next category.
    function _nudge(d) {
        const r = _pinSel
        if (!r) return
        _follow = r
        if (r.type === "header") {
            const cats = ClipboardService.categories
            const at = cats.findIndex(c => c.id === r.category) + d
            if (at >= 0 && at < cats.length) ClipboardService.moveCategory(r.category, at)
            return
        }
        const e = r.entry
        const cat = e.pin.category ?? null
        const size = ClipboardService.pins.filter(p => (p.pin.category ?? null) === cat).length
        const pos = e.pin.position + d
        if (pos >= 0 && pos < size) {
            ClipboardService.movePin(e.id, cat, pos)
            return
        }
        const g = _groups.findIndex(x => x.id === cat) + d
        if (g < 0 || g >= _groups.length) return
        ClipboardService.movePin(e.id, _groups[g].id, d < 0 ? null : 0)
    }

    function _copy(e) {
        if (!e) return
        ClipboardService.copy(e.id)
        ClipboardService.hide()
    }
    function _togglePin(e) {
        if (!e) return
        if (e.pin) ClipboardService.unpin(e.id); else ClipboardService.pin(e.id)
    }

    // Clearing the history asks first, in a dialog over the panel.
    property bool _confirmClear: false
    readonly property int _clearable: ClipboardService.entryCount - ClipboardService.pinCount
    function _askClear() { _closeMenu(); _confirmClear = true }
    function _doClear() { _confirmClear = false; ClipboardService.clear(); _idx = -1; _focusSearch() }

    // ── Categories: create / rename inline ───────────────────────────────────
    property bool _creating: false
    property var  _renaming: null   // category id being renamed
    function _startCreate() {
        if (_tab !== "pinned") _switchTab()
        _renaming = null
        _creating = true
        Qt.callLater(() => _newCategory.forceActiveFocus())
    }
    function _finishCreate(name) {
        _creating = false
        if (name.trim() !== "") ClipboardService.createCategory(name.trim())
        _focusSearch()
    }
    function _finishRename(id, name) {
        _renaming = null
        if (name.trim() !== "") ClipboardService.renameCategory(id, name.trim())
        _focusSearch()
    }

    // ── Context menu ─────────────────────────────────────────────────────────
    property bool _menuOpen: false
    property var  _menuItems: []
    property int  _menuSel: 0
    property real _menuX: 0
    property real _menuY: 0

    function _openMenu(items, sx, sy) {
        _menuItems = items
        _menuSel = 0
        const p = root.mapFromItem(null, sx, sy)
        _menuX = Math.min(Math.max(0, p.x), root.width - 250)
        _menuY = Math.min(Math.max(0, p.y), root.height - (items.length * 36 + 12))
        _menuOpen = true
    }
    function _closeMenu() { _menuOpen = false; _menuItems = [] }
    function _menuDown() { if (_menuItems.length) _menuSel = (_menuSel + 1) % _menuItems.length }
    function _menuUp()   { if (_menuItems.length) _menuSel = (_menuSel - 1 + _menuItems.length) % _menuItems.length }
    function _menuRun() {
        const it = _menuItems[_menuSel]
        _closeMenu()
        if (it && it.run) it.run()
        _focusSearch()
    }

    function _entryMenu(e, sx, sy) {
        const items = [{ label: "Copy", run: () => root._copy(e) }]
        const current = e.pin ? (e.pin.category ?? null) : undefined
        for (const g of _groups) {
            if (g.id === current) continue
            const verb = e.pin ? "Move to " : "Pin in "
            items.push({ label: verb + g.name, run: () => ClipboardService.pin(e.id, g.id) })
        }
        if (e.pin) items.push({ label: "Unpin", run: () => ClipboardService.unpin(e.id) })
        items.push({ label: "Delete", danger: true, run: () => ClipboardService.remove(e.id) })
        _openMenu(items, sx, sy)
    }
    function _categoryMenu(id, sx, sy) {
        const cats = ClipboardService.categories
        const i = cats.findIndex(c => c.id === id)
        if (i < 0) return
        const items = [{ label: "Rename", run: () => root._renaming = id }]
        if (i > 0) items.push({ label: "Move up", run: () => ClipboardService.moveCategory(id, i - 1) })
        if (i < cats.length - 1) items.push({ label: "Move down", run: () => ClipboardService.moveCategory(id, i + 1) })
        items.push({ label: "Delete (pins are kept)", danger: true, run: () => ClipboardService.deleteCategory(id) })
        _openMenu(items, sx, sy)
    }

    // ── Drag and drop in the pinned tab ──────────────────────────────────────
    // _drag: { kind: "pin", entry } or { kind: "category", id, name }
    property var  _drag: null
    property real _dragX: 0
    property real _dragY: 0
    property real _dragSceneY: 0
    property int  _dropRow: -1
    property bool _dropAfter: false
    property var  _dropTarget: null

    function _startDrag(d) { _closeMenu(); _drag = d }
    function _cancelDrag() { _drag = null; _dropRow = -1; _dropTarget = null }
    function _dragMove(sx, sy) {
        if (!_drag) return
        const p = root.mapFromItem(null, sx, sy)
        _dragX = p.x
        _dragY = p.y
        _dragSceneY = sy
        _updateDrop(sx, sy)
    }
    function _updateDrop(sx, sy) {
        const lp = _pinList.mapFromItem(null, sx, sy)
        const i = _pinList.indexAt(lp.x, lp.y + _pinList.contentY)
        const r = i >= 0 ? _pinRows[i] : null
        if (!r) { _dropRow = -1; _dropTarget = null; return }

        if (_drag.kind === "category") {
            const cats = ClipboardService.categories
            const to = Math.max(0, cats.findIndex(c => c.id === r.category))
            _dropRow = _pinRows.findIndex(x => x.type === "header" && x.category === cats[to]?.id)
            _dropAfter = false
            _dropTarget = { position: to }
            return
        }
        const item = _pinList.itemAtIndex(i)
        const after = r.type === "pin" && !!item && item.mapFromItem(null, sx, sy).y > item.height / 2
        let pos = r.type === "pin" ? r.entry.pin.position + (after ? 1 : 0) : 0
        const from = _drag.entry.pin
        // The daemon removes the pin before inserting it again.
        if ((from.category ?? null) === r.category && from.position < pos) pos -= 1
        _dropRow = i
        _dropAfter = after
        _dropTarget = { category: r.category, position: pos }
    }
    function _endDrag() {
        const d = _drag, t = _dropTarget
        _cancelDrag()
        if (!d || !t) return
        if (d.kind === "pin") {
            const from = d.entry.pin
            if ((from.category ?? null) !== t.category || from.position !== t.position)
                ClipboardService.movePin(d.entry.id, t.category, t.position)
        } else {
            const at = ClipboardService.categories.findIndex(c => c.id === d.id)
            if (at !== t.position) ClipboardService.moveCategory(d.id, t.position)
        }
    }
    // Scroll while dragging near the list's edges.
    Timer {
        interval: 16
        repeat: true
        running: root._drag !== null
        onTriggered: {
            const y = _pinList.mapFromItem(null, 0, root._dragSceneY).y
            const edge = 48
            let d = 0
            if (y < edge) d = -Math.ceil((edge - y) / 4)
            else if (y > _pinList.height - edge) d = Math.ceil((y - _pinList.height + edge) / 4)
            if (d === 0) return
            _pinList.contentY = Math.max(0, Math.min(_pinList.contentHeight - _pinList.height, _pinList.contentY + d))
        }
    }

    // ── Formatting ───────────────────────────────────────────────────────────
    function _ago(ms) {
        const s = Math.max(0, (Date.now() - ms) / 1000)
        if (s < 60)    return "now"
        if (s < 3600)  return Math.floor(s / 60) + " min"
        if (s < 86400) return Math.floor(s / 3600) + " h"
        if (s < 86400 * 30) return Math.floor(s / 86400) + " d"
        return new Date(ms).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }
    // Relative times are refreshed while the panel is open.
    property real _now: Date.now()
    Timer { interval: 30000; repeat: true; running: root.active; onTriggered: root._now = Date.now() }

    function _size(n) {
        if (n < 1024) return n + " B"
        if (n < 1024 * 1024) return Math.ceil(n / 1024) + " KiB"
        return (n / 1024 / 1024).toFixed(1) + " MiB"
    }

    // ── Content ──────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        anchors.bottomMargin: 22 + ThemeManager.borderWidth
        spacing: 12

        // ── Search + actions ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 22
                color: ThemeManager.surfaceContainerHigh
                border.width: _search.activeFocus && root._sel() < 0 ? 2 : 1
                border.color: _search.activeFocus && root._sel() < 0 ? ThemeManager.primary : ThemeManager.outlineVariant

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
                        placeholderText: root._tab === "history" ? "Search the clipboard history…" : "Search the pinned entries…"
                        placeholderTextColor: ThemeManager.onSurfaceVariant
                        verticalAlignment: TextInput.AlignVCenter
                        text: ClipboardService.query
                        onTextChanged: {
                            if (text !== ClipboardService.query) ClipboardService.query = text
                            root._idx = -1
                            root._pidx = -1
                            root._follow = null
                        }
                        onAccepted: {
                            if (root._menuOpen) root._menuRun()
                            else if (root._categorySelected) root._renaming = root._pinSel.category
                            else root._copy(root._selected())
                        }
                        Keys.onTabPressed:     (e) => { root._switchTab(); e.accepted = true }
                        Keys.onBacktabPressed: (e) => { root._switchTab(); e.accepted = true }
                        Keys.onDownPressed: (e) => {
                            if (root._menuOpen) root._menuDown()
                            else if (root._tab === "pinned" && (e.modifiers & Qt.ControlModifier)) root._nudge(1)
                            else root._move(1)
                            e.accepted = true
                        }
                        Keys.onUpPressed: (e) => {
                            if (root._menuOpen) root._menuUp()
                            else if (root._tab === "pinned" && (e.modifiers & Qt.ControlModifier)) root._nudge(-1)
                            else root._move(-1)
                            e.accepted = true
                        }
                        Keys.onPressed: (e) => {
                            // The clear dialog takes every key: Enter confirms, Esc cancels.
                            if (root._confirmClear) {
                                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root._doClear()
                                else if (e.key === Qt.Key_Escape) root._confirmClear = false
                                e.accepted = true
                                return
                            }
                            if (root._menuOpen) return
                            const ctrl = e.modifiers & Qt.ControlModifier
                            if (e.key === Qt.Key_N && ctrl) {
                                root._startCreate()
                                e.accepted = true
                                return
                            }
                            if (root._categorySelected) {
                                const id = root._pinSel.category
                                if (e.key === Qt.Key_F2) {
                                    root._renaming = id
                                    e.accepted = true
                                } else if (e.key === Qt.Key_Delete) {
                                    ClipboardService.deleteCategory(id)
                                    e.accepted = true
                                }
                                return
                            }
                            const entry = root._selectedEntry()
                            if (!entry) return
                            if (e.key === Qt.Key_Delete) {
                                ClipboardService.remove(entry.id)
                                e.accepted = true
                            } else if (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier)) {
                                root._togglePin(entry)
                                e.accepted = true
                            }
                        }
                        Keys.onEscapePressed: {
                            if (root._menuOpen) root._closeMenu()
                            else if (root._drag) root._cancelDrag()
                            else if (root._searching) ClipboardService.query = ""
                            else ClipboardService.hide()
                        }
                    }
                }
            }

            IconButton {
                visible: ClipboardService.connected
                icon: ClipboardService.paused ? "󰐊" : "󰏤"
                tip: ClipboardService.paused ? "Resume recording" : "Pause recording"
                highlighted: ClipboardService.paused
                onClicked: ClipboardService.setPaused(!ClipboardService.paused)
            }
            IconButton {
                visible: ClipboardService.connected && root._tab === "history" && root._clearable > 0
                icon: "󰃢"
                label: "Clear"
                tip: "Delete the whole history, except pinned entries"
                onClicked: root._askClear()
            }
            IconButton {
                visible: ClipboardService.connected && root._tab === "pinned"
                icon: "󰉗"
                tip: "New category (Ctrl+N)"
                highlighted: root._creating
                onClicked: { if (root._creating) root._creating = false; else root._startCreate() }
            }
        }

        // ── Tabs ──────────────────────────────────────────────────────────────
        RowLayout {
            visible: ClipboardService.connected
            Layout.fillWidth: true
            spacing: 6
            TabChip {
                label: "History"
                selected: root._tab === "history"
                onClicked: if (!selected) root._switchTab()
            }
            TabChip {
                label: "Pinned" + (ClipboardService.pins.length ? "  " + ClipboardService.pins.length : "")
                selected: root._tab === "pinned"
                onClicked: if (!selected) root._switchTab()
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Tab switches"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeXs
            }
        }

        // ── Banners ───────────────────────────────────────────────────────────
        Banner {
            visible: ClipboardService.connected && ClipboardService.paused
            text: ClipboardService.pausedUntil
                ? "Recording paused until " + new Date(ClipboardService.pausedUntil).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                : "Recording paused: new copies are not kept"
        }
        Banner {
            visible: ClipboardService.error !== ""
            error: true
            text: ClipboardService.error
        }

        // ── History ───────────────────────────────────────────────────────────
        ListView {
            id: _historyList
            visible: root._tab === "history" && ClipboardService.connected && root._entries.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root._entries
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: EntryRow {
                required property var modelData
                required property int index
                width: ListView.view.width - 8
                entry: modelData
                selected: root._idx === index
                onCopyRequested: root._copy(modelData)
                onPinToggled: root._togglePin(modelData)
                onDeleteRequested: ClipboardService.remove(modelData.id)
                onMenuRequested: (sx, sy) => root._entryMenu(modelData, sx, sy)
            }
        }

        // ── Pinned ────────────────────────────────────────────────────────────
        Rectangle {
            visible: root._tab === "pinned" && root._creating
            Layout.fillWidth: true
            implicitHeight: 40
            radius: ThemeManager.chipRadius
            color: ThemeManager.surfaceContainerHigh
            border.width: 1
            border.color: ThemeManager.primary
            TextField {
                id: _newCategory
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                background: null
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeMd
                placeholderText: "Category name, Enter to create"
                placeholderTextColor: ThemeManager.onSurfaceVariant
                verticalAlignment: TextInput.AlignVCenter
                onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                onAccepted: root._finishCreate(text)
                Keys.onEscapePressed: { root._creating = false; root._focusSearch() }
            }
        }

        ListView {
            id: _pinList
            visible: root._tab === "pinned" && ClipboardService.connected && root._pinRows.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            interactive: root._drag === null
            model: root._pinRows
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
                id: pr
                required property var modelData
                required property int index
                readonly property bool _dropHere: root._dropRow === index && root._drag !== null
                width: ListView.view.width - 8
                height: modelData.type === "pin" ? _pinEntry.height : (modelData.type === "header" ? 38 : 44)

                CategoryHeader {
                    visible: pr.modelData.type === "header"
                    anchors.fill: parent
                    categoryId: pr.modelData.category
                    name: pr.modelData.name ?? ""
                    count: pr.modelData.count ?? 0
                    dropHere: pr._dropHere
                    selected: pr.modelData.type === "header" && root._categorySelected
                              && root._pinSel.category === pr.modelData.category
                }

                Rectangle {
                    visible: pr.modelData.type === "empty"
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    radius: ThemeManager.chipRadius
                    color: pr._dropHere ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.12) : "transparent"
                    border.width: 1
                    border.color: pr._dropHere ? ThemeManager.primary : ThemeManager.outlineVariant
                    Text {
                        anchors.centerIn: parent
                        text: pr.modelData.filtered ? "No match in this category" : "Drag pins here"
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                    }
                }

                EntryRow {
                    id: _pinEntry
                    visible: pr.modelData.type === "pin"
                    width: parent.width
                    entry: pr.modelData.type === "pin" ? pr.modelData.entry : null
                    selected: !!entry && root._pinSel?.type === "pin" && root._pinSel.entry.id === entry.id
                    draggable: true
                    dimmed: !!entry && root._drag?.kind === "pin" && root._drag.entry.id === entry.id
                    dropBefore: pr._dropHere && !root._dropAfter
                    dropAfter: pr._dropHere && root._dropAfter
                    onCopyRequested: root._copy(entry)
                    onPinToggled: root._togglePin(entry)
                    onDeleteRequested: ClipboardService.remove(entry.id)
                    onMenuRequested: (sx, sy) => root._entryMenu(entry, sx, sy)
                    onDragStarted: root._startDrag({ kind: "pin", entry: entry })
                    onDragMoved: (sx, sy) => root._dragMove(sx, sy)
                    onDragEnded: root._endDrag()
                }
            }
        }

        // ── Empty states ──────────────────────────────────────────────────────
        Item {
            visible: !_historyList.visible && !_pinList.visible
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root._tab === "pinned" && ClipboardService.connected ? "󰐃" : "󰅍"
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 40
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: ThemeManager.onSurface
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeMd
                    text: !ClipboardService.connected
                            ? (ClipboardService.installed ? "clipd is not running" : "Install clipd to keep a clipboard history")
                        : !ClipboardService.loaded ? "…"
                        : root._tab === "pinned" ? "Nothing pinned yet"
                        : root._searching ? "Nothing matches this search"
                        : "Copied text and images appear here"
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeSm
                    textFormat: Text.PlainText
                    text: !ClipboardService.connected
                            ? (ClipboardService.installed ? "Start it with: systemctl --user enable --now clipd.service"
                                                          : "Package: " + DependencyService.pkg("clipd"))
                        : root._tab === "pinned" ? "Pin entries from the history with Ctrl+P or a right click. Pinned entries are never cleared, and categories keep them organized."
                        : ""
                }
            }
        }

        // ── Hints ─────────────────────────────────────────────────────────────
        Text {
            visible: _historyList.visible || _pinList.visible
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root._tab === "history"
                ? "Enter copies  ·  Ctrl+P pins  ·  Del deletes  ·  right click for more"
                : root._categorySelected
                    ? "Ctrl+↑↓ moves the category  ·  F2 or Enter renames  ·  Del deletes, pins are kept"
                    : "Drag or Ctrl+↑↓ to move  ·  Ctrl+N new category"
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeXs
        }
    }

    // ── Drag proxy (follows the cursor above the clipped lists) ──────────────
    Rectangle {
        visible: root._drag !== null
        x: root._dragX + 14
        y: root._dragY - height / 2
        width: Math.min(260, _proxyText.implicitWidth + 28)
        height: 34
        radius: ThemeManager.chipRadius
        color: ThemeManager.surfaceContainerHigh
        border.width: 2
        border.color: ThemeManager.primary
        opacity: 0.95
        z: 300
        Text {
            id: _proxyText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 14
            width: Math.min(implicitWidth, 232)
            elide: Text.ElideRight
            text: !root._drag ? ""
                : root._drag.kind === "category" ? "󰉋  " + root._drag.name
                : root._drag.entry.kind === "image" ? "󰋩  Image" : root._drag.entry.preview
            color: ThemeManager.onSurface
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
        }
    }

    // ── Clear confirmation ───────────────────────────────────────────────────
    Rectangle {
        visible: root._confirmClear
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        z: 250
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: { root._confirmClear = false; root._focusSearch() }
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 400)
            height: _confirmCol.implicitHeight + 40
            radius: ThemeManager.panelRadius
            color: ThemeManager.surfaceContainerHigh
            border.width: 1
            border.color: ThemeManager.outlineVariant
            // Clicks on the dialog must not cancel it.
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

            ColumnLayout {
                id: _confirmCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 12
                RowLayout {
                    spacing: 10
                    Text {
                        text: "󰃢"
                        color: ThemeManager.error
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 22
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Clear the clipboard history?"
                        color: ThemeManager.onSurface
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeLg
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeSm
                    text: (root._clearable === 1 ? "1 entry will be deleted" : root._clearable + " entries will be deleted")
                        + " for good."
                        + (ClipboardService.pinCount > 0
                           ? " Your " + ClipboardService.pinCount + " pinned " + (ClipboardService.pinCount === 1 ? "entry is" : "entries are") + " kept."
                           : "")
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Enter clears, Esc cancels."
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeXs
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: 4
                    spacing: 8
                    DialogButton {
                        label: "Cancel"
                        onClicked: { root._confirmClear = false; root._focusSearch() }
                    }
                    DialogButton {
                        label: "Clear history"
                        danger: true
                        onClicked: root._doClear()
                    }
                }
            }
        }
    }

    // ── Context menu overlay ─────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        visible: root._menuOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: { root._closeMenu(); root._focusSearch() }
    }
    Rectangle {
        visible: root._menuOpen
        x: root._menuX
        y: root._menuY
        width: 240
        height: _menuCol.implicitHeight + 8
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
                    color: (root._menuSel === index || _mh.hovered) ? ThemeManager.secondaryContainer : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        width: parent.width - 28
                        elide: Text.ElideRight
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

    // ── Components ───────────────────────────────────────────────────────────

    // One clipboard entry. Left click copies, right click opens the menu, and
    // dragging (pinned tab) moves it.
    component EntryRow: Rectangle {
        id: er
        property var  entry: null
        property bool selected: false
        property bool draggable: false
        property bool dimmed: false
        property bool dropBefore: false
        property bool dropAfter: false
        signal copyRequested()
        signal pinToggled()
        signal deleteRequested()
        signal menuRequested(real sx, real sy)
        signal dragStarted()
        signal dragMoved(real sx, real sy)
        signal dragEnded()

        readonly property bool _image: !!entry && entry.kind === "image"
        readonly property bool _thumb: _image && !!entry.thumbnail
        height: _thumb ? 76 : 52
        radius: ThemeManager.chipRadius + 2
        opacity: dimmed ? 0.35 : 1
        color: selected ? ThemeManager.secondaryContainer
             : (_erHov.hovered ? ThemeManager.surfaceContainerHigh : "transparent")
        border.width: selected ? 1 : 0
        border.color: ThemeManager.primary

        Rectangle {
            visible: er.dropBefore || er.dropAfter
            anchors.left: parent.left
            anchors.right: parent.right
            y: er.dropBefore ? -3 : parent.height + 1
            height: 2
            radius: 1
            color: ThemeManager.primary
        }

        RowLayout {
            visible: !!er.entry
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 12

            Image {
                visible: er._thumb
                Layout.preferredWidth: 96
                Layout.preferredHeight: 60
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // Ids can be reused after deletions, and the file with them.
                cache: false
                sourceSize.width: 192
                source: er._thumb ? "file://" + er.entry.thumbnail : ""
            }
            Text {
                visible: !er._thumb
                text: er._image ? "󰋩" : "󰅍"
                color: ThemeManager.onSurfaceVariant
                font.family: ThemeManager.fontFamily
                font.pixelSize: 18
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: !er.entry ? ""
                        : er._image ? (er.entry.width ? er.entry.width + " × " + er.entry.height : "Image")
                        : er.entry.preview
                    color: ThemeManager.onSurface
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeMd
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Text {
                    Layout.fillWidth: true
                    text: {
                        void root._now
                        if (!er.entry) return ""
                        const parts = [root._ago(er.entry.last_used_ms)]
                        if (er._image) parts.push(er.entry.mime.replace("image/", "").toUpperCase())
                        parts.push(root._size(er.entry.size))
                        if (er.entry.use_count > 1) parts.push(er.entry.use_count + "×")
                        return parts.join("  ·  ")
                    }
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeXs
                    elide: Text.ElideRight
                }
            }
            IconButton {
                visible: !!er.entry && (!!er.entry.pin || _erHov.hovered || er.selected)
                small: true
                icon: "󰐃"
                tip: er.entry && er.entry.pin ? "Unpin (Ctrl+P)" : "Pin (Ctrl+P)"
                highlighted: !!er.entry && !!er.entry.pin
                onClicked: er.pinToggled()
            }
            IconButton {
                visible: _erHov.hovered || er.selected
                small: true
                icon: "󰆴"
                tip: "Delete (Del)"
                onClicked: er.deleteRequested()
            }
        }
        HoverHandler { id: _erHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { acceptedButtons: Qt.LeftButton; onTapped: er.copyRequested() }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: er.menuRequested(point.scenePosition.x, point.scenePosition.y)
        }
        DragHandler {
            enabled: er.draggable
            target: null
            onActiveChanged: active ? er.dragStarted() : er.dragEnded()
            onCentroidChanged: if (active) er.dragMoved(centroid.scenePosition.x, centroid.scenePosition.y)
        }
    }

    // A category title in the pinned tab: drag it to reorder the categories,
    // right click (or the buttons) to rename or delete it.
    component CategoryHeader: Rectangle {
        id: ch
        property var    categoryId: null
        property string name: ""
        property int    count: 0
        property bool   dropHere: false
        property bool   selected: false
        readonly property bool _real: categoryId !== null && categoryId !== undefined
        readonly property bool _renaming: _real && root._renaming === categoryId
        radius: ThemeManager.chipRadius
        color: dropHere ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.14)
             : selected ? ThemeManager.secondaryContainer : "transparent"
        border.width: dropHere || selected ? 1 : 0
        border.color: ThemeManager.primary
        opacity: _real && root._drag?.kind === "category" && root._drag.id === categoryId ? 0.35 : 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 4
            spacing: 8
            Text {
                text: ch._real ? "󰉋" : "󰐃"
                color: ThemeManager.primary
                font.family: ThemeManager.fontFamily
                font.pixelSize: 16
            }
            Text {
                visible: !ch._renaming
                Layout.fillWidth: true
                text: ch.name + "  ·  " + ch.count
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            TextField {
                visible: ch._renaming
                Layout.fillWidth: true
                color: ThemeManager.onSurface
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm
                verticalAlignment: TextInput.AlignVCenter
                background: Rectangle {
                    radius: ThemeManager.chipRadius
                    color: ThemeManager.surfaceContainerHigh
                    border.width: 1
                    border.color: ThemeManager.primary
                }
                onVisibleChanged: if (visible) { text = ch.name; forceActiveFocus(); selectAll() }
                onAccepted: root._finishRename(ch.categoryId, text)
                Keys.onEscapePressed: { root._renaming = null; root._focusSearch() }
            }
            IconButton {
                visible: ch._real && !ch._renaming && (_chHov.hovered || ch.selected)
                small: true
                icon: "󰏫"
                tip: "Rename (F2)"
                onClicked: root._renaming = ch.categoryId
            }
            IconButton {
                visible: ch._real && !ch._renaming && (_chHov.hovered || ch.selected)
                small: true
                icon: "󰆴"
                tip: "Delete the category, its pins are kept (Del)"
                onClicked: ClipboardService.deleteCategory(ch.categoryId)
            }
        }
        HoverHandler { id: _chHov; cursorShape: ch._real ? Qt.OpenHandCursor : Qt.ArrowCursor }
        TapHandler {
            enabled: ch._real
            acceptedButtons: Qt.RightButton
            onTapped: root._categoryMenu(ch.categoryId, point.scenePosition.x, point.scenePosition.y)
        }
        DragHandler {
            enabled: ch._real && !ch._renaming
            target: null
            onActiveChanged: active ? root._startDrag({ kind: "category", id: ch.categoryId, name: ch.name }) : root._endDrag()
            onCentroidChanged: if (active) root._dragMove(centroid.scenePosition.x, centroid.scenePosition.y)
        }
    }

    component TabChip: Rectangle {
        id: tc
        property string label: ""
        property bool selected: false
        signal clicked()
        implicitWidth: _tcText.implicitWidth + 28
        implicitHeight: 30
        radius: 15
        color: selected ? ThemeManager.secondaryContainer
             : (_tcHov.hovered ? ThemeManager.surfaceContainerHigh : "transparent")
        border.width: selected ? 0 : 1
        border.color: ThemeManager.outlineVariant
        Text {
            id: _tcText
            anchors.centerIn: parent
            text: tc.label
            color: tc.selected ? ThemeManager.onSurface : ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            font.weight: tc.selected ? Font.DemiBold : Font.Normal
        }
        HoverHandler { id: _tcHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tc.clicked() }
    }

    component Banner: Rectangle {
        id: bn
        property string text: ""
        property bool error: false
        readonly property color _fg: error ? ThemeManager.error : ThemeManager.primary
        Layout.fillWidth: true
        implicitHeight: 36
        radius: ThemeManager.chipRadius
        color: Qt.rgba(_fg.r, _fg.g, _fg.b, 0.12)
        Text {
            anchors.centerIn: parent
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: bn.text
            color: bn._fg
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
        }
    }

    component DialogButton: Rectangle {
        id: db
        property string label: ""
        property bool danger: false
        signal clicked()
        implicitWidth: _dbText.implicitWidth + 32
        implicitHeight: 36
        radius: 18
        color: danger ? (_dbMouse.containsMouse ? Qt.lighter(ThemeManager.error, 1.12) : ThemeManager.error)
             : (_dbMouse.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08) : "transparent")
        border.width: danger ? 0 : 1
        border.color: ThemeManager.outlineVariant
        Text {
            id: _dbText
            anchors.centerIn: parent
            text: db.label
            color: db.danger ? ThemeManager.onError : ThemeManager.onSurface
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            font.weight: Font.Medium
        }
        MouseArea {
            id: _dbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: db.clicked()
        }
    }

    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""
        property bool highlighted: false
        property bool danger: false
        property bool small: false
        property string label: ""
        signal clicked()
        implicitWidth: label !== "" ? _ibText.implicitWidth + 32 : (small ? 32 : 44)
        implicitHeight: small ? 32 : 44
        radius: height / 2
        readonly property color _fg: danger ? ThemeManager.error
                                   : highlighted ? ThemeManager.primary : ThemeManager.onSurfaceVariant
        color: danger ? Qt.rgba(ThemeManager.error.r, ThemeManager.error.g, ThemeManager.error.b, _ibMouse.containsMouse ? 0.22 : 0.14)
             : _ibMouse.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)
             : (small ? "transparent" : ThemeManager.surfaceContainerHigh)
        Text {
            id: _ibText
            anchors.centerIn: parent
            text: ib.label !== "" ? ib.icon + "  " + ib.label : ib.icon
            color: ib._fg
            font.family: ThemeManager.fontFamily
            font.pixelSize: ib.label !== "" ? ThemeManager.fontSizeSm : (ib.small ? 16 : 18)
        }
        // A MouseArea, not a TapHandler: the click must not reach the row below.
        MouseArea {
            id: _ibMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
        ToolTip.visible: _ibMouse.containsMouse && ib.tip !== ""
        ToolTip.text: ib.tip
        ToolTip.delay: 500
    }
}
