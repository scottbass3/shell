pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."

// Clipboard history from the clipd daemon (github.com/scottbass3/clipd), over
// its socket: one JSON request per line, replies in order, plus event lines
// once subscribed. Also holds the open state of the clipboard panel, which
// MainWindow draws like the launcher.
QtObject {
    id: root

    property bool   open:       false
    property string screenName: ""
    property string query:      ""

    readonly property bool installed: DependencyService.available("clipd")
    readonly property bool connected: _sockConnected

    property var  entries:    []   // history, newest first (filtered by `query`)
    property var  pins:       []
    property var  categories: []
    property bool paused:     false
    property var  pausedUntil: null   // ms since epoch, null = until resumed
    property bool loaded:     false   // first history reply received
    property int  entryCount: 0       // whole history, pinned entries included
    property int  pinCount:   0
    property string error:    ""      // last refused request, shown for a few seconds

    function show() {
        LauncherService.hide()
        screenName = Hyprland.focusedMonitor?.name ?? ""
        query = ""
        open = true
        if (!connected) _connect()
    }
    function hide() { open = false; query = "" }
    function toggle() { if (open) hide(); else show() }

    function copy(id)   { _call({ method: "copy", id: id }) }
    function remove(id) { _call({ method: "delete", id: id }) }
    function pin(id, category) { _call({ method: "pin", id: id, category: category ?? null }) }
    function unpin(id)  { _call({ method: "unpin", id: id }) }
    function clear()    { _call({ method: "clear" }) }
    // position: index in the category, null = last.
    function movePin(id, category, position) {
        _call({ method: "move_pin", id: id, category: category ?? null, position: position ?? null })
    }
    function createCategory(name)     { _call({ method: "create_category", name: name }) }
    function renameCategory(id, name) { _call({ method: "rename_category", id: id, name: name }) }
    function deleteCategory(id)       { _call({ method: "delete_category", id: id }) }
    function moveCategory(id, position) { _call({ method: "move_category", id: id, position: position }) }
    function setPaused(on) { _call({ method: on ? "pause" : "resume" }) }

    // ── Socket ───────────────────────────────────────────────────────────────
    readonly property string _path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/clipd.sock"
    property var _pending: []   // reply callbacks, in request order

    function _call(request, cb) {
        if (!_sockConnected) return
        _pending.push(cb ?? null)
        _sock.write(JSON.stringify(request) + "\n")
        _sock.flush()
    }

    // A Socket whose connection failed keeps its dead QLocalSocket and never
    // tries again, so each attempt gets a fresh one.
    property var  _sock: null
    property bool _sockConnected: false

    function _connect() {
        if (_sock) return
        _sock = _sockComponent.createObject(root)
        _sock.connected = true
    }
    function _drop(s) {
        if (s !== _sock) return
        _sock = null
        _sockConnected = false
        loaded = false
        _pending = []
        s.destroy()
    }

    function _onLine(line) {
        let msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (msg.event !== undefined) { _onEvent(msg.event); return }
        const cb = _pending.shift()
        if (msg.error !== undefined) {
            root.error = msg.error
            _errorTimer.restart()
            return
        }
        if (cb) cb(msg.result)
    }

    // Changes come in bursts (a pin is both "pins" and "history"); refetch once.
    property var _dirty: ({})
    function _onEvent(name) {
        _dirty[name] = true
        _refetch.restart()
    }
    property Timer _refetch: Timer {
        interval: 60
        onTriggered: {
            const d = root._dirty
            root._dirty = {}
            if (d.history)    root._fetchHistory()
            if (d.pins)       root._fetchPins()
            if (d.categories) root._fetchCategories()
            if (d.status || d.history) root._fetchStatus()
        }
    }

    function _fetchHistory() {
        const q = query.trim()
        const req = { method: "list", limit: 500 }
        if (q !== "") req.query = q
        _call(req, r => { if (q === root.query.trim()) { root.entries = r; root.loaded = true } })
    }
    function _fetchPins()       { _call({ method: "pins" }, r => root.pins = r) }
    function _fetchCategories() { _call({ method: "categories" }, r => root.categories = r) }
    function _fetchStatus() {
        _call({ method: "status" }, r => {
            root.paused = r.paused
            root.pausedUntil = r.until_ms
            root.entryCount = r.entries
            root.pinCount = r.pins
        })
    }
    function _fetchAll() { _fetchHistory(); _fetchPins(); _fetchCategories(); _fetchStatus() }

    property Timer _errorTimer: Timer { interval: 4000; onTriggered: root.error = "" }

    onQueryChanged: _search.restart()
    property Timer _search: Timer { interval: 120; onTriggered: root._fetchHistory() }

    property Component _sockComponent: Component {
        Socket {
            id: s
            path: root._path
            parser: SplitParser { onRead: line => { if (s === root._sock) root._onLine(line) } }
            onError: root._drop(s)
            onConnectionStateChanged: {
                if (s !== root._sock) return
                if (!connected) { root._drop(s); return }
                root._pending = []
                root._sockConnected = true
                root._call({ method: "subscribe" })
                root._fetchAll()
            }
        }
    }

    // The daemon may start after the shell, or restart. A daemon found outside
    // PATH (e.g. a Nix user service) is used all the same.
    property Timer _retry: Timer {
        interval: 3000
        repeat: true
        running: !root.connected
        onTriggered: root._connect()
    }

    Component.onCompleted: _connect()
}
