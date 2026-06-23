pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// YouTube Music Desktop App — companion-server integration (ytmdesktop v2).
// Realtime state over the companion's socket.io channel, spoken directly from
// QML via QtWebSockets (no node bridge). Commands go over REST (POST
// /api/v1/command); a REST /state seed fills the UI immediately on connect.
// Authenticated with a token kept in the keyring (secret-tool, never plaintext).
// Gives an always-present YT Music player (even when paused) with richer data
// than MPRIS: album art, volume, queue. Position is interpolated between
// updates. MPRIS remains the fallback when this is offline.
QtObject {
    id: root

    readonly property string _host: "127.0.0.1:9863"
    readonly property string _base: "http://" + _host + "/api/v1"
    readonly property string _ns:   "/api/v1/realtime"     // socket.io namespace
    property string _token: ""
    property bool   active:  false   // UI sets true while watching (legacy gate)

    // ── Exposed state ─────────────────────────────────────────────────────────
    property bool   reachable: false          // connected + namespace joined
    property bool   hasVideo:  false          // a track is loaded
    readonly property bool available: reachable && hasVideo

    property string title:  ""
    property string artist: ""
    property string album:  ""
    property string artUrl: ""
    property int    durationMs: 0
    property bool   playing:    false
    property int    volume:     100
    property int    repeatMode: 0              // 0 none, 1 all, 2 one

    // Interpolated position
    property real _anchorSec:  0
    property real _anchorTime: 0
    readonly property int positionMs: {
        let s = _anchorSec
        if (playing) s += (Date.now() - _anchorTime) / 1000
        const ms = Math.round(s * 1000)
        return durationMs > 0 ? Math.min(ms, durationMs) : ms
    }

    // Enabled once the token is loaded and the feature is on. Always-on (not
    // gated on `active`) so YT state is known globally — needed for cross-player
    // auto-pause and always-present in the UI. socket.io is push, idle is cheap.
    // Also requires the optional qt6-websockets QML module; without it the
    // socket never loads and MPRIS remains the source of truth.
    readonly property bool _enabled: _token !== ""
        && SettingsService.get("media.ytm", true)
        && DependencyService.available("qt6-websockets")
    on_EnabledChanged: { if (_enabled) _open(); else if (_wsLoader.item) _wsLoader.item.wsActive = false }

    // ── Token load (keyring) ──────────────────────────────────────────────────
    property Process _tokenProc: Process {
        command: ["secret-tool", "lookup", "service", "ytmd-companion", "key", "token"]
        stdout: StdioCollector { onStreamFinished: root._token = text.trim() }
    }

    // ── Realtime: socket.io over WebSocket (engine.io v4) ─────────────────────
    // The WebSocket itself lives in YtmSocket.qml, loaded only when the optional
    // qt6-websockets module is present (DependencyService gate) — so the import
    // can't hard-fail the shell when the module is absent.
    property Loader _wsLoader: Loader {
        active: root._enabled
        source: "YtmSocket.qml"
        onLoaded: {
            item.url = "ws://" + root._host + "/socket.io/?EIO=4&transport=websocket"
            item.messageReceived.connect(root._onMsg)
            item.disconnected.connect(root._onDisconnect)
            root._open()
        }
    }
    function _wsSend(m) { if (_wsLoader.item) _wsLoader.item.send(m) }
    function _onDisconnect() {
        root.reachable = false
        if (root._enabled) root._reTimer.restart()
    }
    property Timer _reTimer: Timer { interval: 3000; onTriggered: if (root._enabled) root._open() }

    function _open() {
        const it = _wsLoader.item
        if (!it) return
        it.wsActive = false
        it.wsActive = true
        _seedTries = 0
    }

    // engine.io/socket.io framing: <engine-type><socket-type><namespace,><json>
    //   0{…}  engine OPEN  → send CONNECT for our namespace (with auth)
    //   2     engine PING  → reply PONG (3)
    //   40…   CONNECT ack  → joined namespace, seed via REST
    //   42…   EVENT        → ["evt", payload]
    function _onMsg(m) {
        if (!m || m.length === 0) return
        const t = m.charAt(0)
        if (t === "0") {   // engine OPEN → join namespace with auth
            _wsSend("40" + root._ns + "," + JSON.stringify({ token: root._token }))
            return
        }
        if (t === "2") { _wsSend("3"); return }   // ping → pong
        if (t !== "4") return                                  // only engine messages below
        const st = m.charAt(1)
        let rest = m.slice(2)
        if (rest.charAt(0) === "/") {                          // strip "<namespace>,"
            const ci = rest.indexOf(",")
            rest = ci >= 0 ? rest.slice(ci + 1) : ""
        }
        if (st === "0") {                                      // CONNECT ack
            root.reachable = true
            root._seed()
            return
        }
        if (st === "2") {                                      // EVENT
            let arr
            try { arr = JSON.parse(rest) } catch (e) { return }
            if (!Array.isArray(arr) || arr.length < 2) return
            const data = arr[1]
            if (data && data.player) root._ingest(data)
        }
    }

    // ── State shaping (ported from the old node bridge) ───────────────────────
    property var    _cur: ({ has: false, title: "", artist: "", album: "", art: "", durationSeconds: 0 })
    property string _lastSig: ""

    function _durToSec(s) {
        if (!s) return 0
        const a = ("" + s).split(":").map(n => parseInt(n, 10) || 0)
        if (a.length === 3) return a[0] * 3600 + a[1] * 60 + a[2]
        if (a.length === 2) return a[0] * 60 + a[1]
        return a[0] || 0
    }

    // Events are often partial (progress-only), so we carry the last known video
    // and only overwrite its fields when a new one is present.
    function _ingest(state) {
        if (!state) return
        const p = state.player || {}
        let v = state.video
        if (!v || !v.title) {
            const q = p.queue
            if (q && q.items && q.items.length) {
                const it = q.items[q.selectedItemIndex] || q.items.find(x => x.selected)
                if (it) v = { title: it.title, author: it.author, album: "",
                              thumbnails: it.thumbnails, durationSeconds: _durToSec(it.duration) }
            }
        }
        if (v && v.title) {
            const th = v.thumbnails || []
            _cur = { has: true, title: v.title, artist: v.author || "", album: v.album || "",
                     art: (th.length ? th[th.length - 1].url : "") || _cur.art,
                     durationSeconds: v.durationSeconds || 0 }
        }
        const c = {
            has: _cur.has, title: _cur.title, artist: _cur.artist, album: _cur.album, art: _cur.art,
            durationSeconds: _cur.durationSeconds,
            progress: p.videoProgress || 0,
            trackState: p.trackState,
            volume: p.volume,
            repeatMode: p.repeatMode || 0,
        }
        // de-dupe identical states (ignoring progress) while paused/stopped
        const sig = "" + c.has + c.title + c.artist + c.trackState + c.volume + c.repeatMode
        if (sig === _lastSig && c.trackState !== 1) return
        _lastSig = sig
        _apply(c)
    }

    function _apply(c) {
        reachable = true
        hasVideo  = !!c.has
        if (c.has) {
            title      = c.title  || ""
            artist     = c.artist || ""
            album      = c.album  || ""
            artUrl     = c.art    || ""
            durationMs = (c.durationSeconds || 0) * 1000
        }
        volume     = c.volume !== undefined ? c.volume : volume
        repeatMode = c.repeatMode || 0
        playing    = (c.trackState === 1)
        _anchorSec  = c.progress || 0
        _anchorTime = Date.now()
    }

    // ── REST seed (immediate track on connect) ────────────────────────────────
    // /state is rate-limited to 1/5s and returns an invalid-JSON stub when
    // throttled, so retry every 5.5s until a track lands (max 6 tries).
    property int _seedTries: 0
    property Timer _seedTimer: Timer { interval: 5500; onTriggered: root._seed() }
    function _seed() {
        if (_token === "") return
        const xhr = new XMLHttpRequest()
        xhr.timeout = 3000
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) root._onSeed(xhr.responseText)
        }
        xhr.open("GET", _base + "/state")
        xhr.setRequestHeader("Authorization", _token)
        xhr.send()
    }
    function _onSeed(txt) {
        let ok = false
        try { _ingest(JSON.parse(txt)); ok = _cur.has } catch (e) {}
        if (!ok && ++_seedTries < 6) _seedTimer.restart()
    }

    // ── Commands ────────────────────────────────────────────────────────────--
    function _send(command, data) {
        if (_token === "") return
        const body = data !== undefined ? JSON.stringify({ command: command, data: data })
                                        : JSON.stringify({ command: command })
        const xhr = new XMLHttpRequest()
        xhr.timeout = 3000
        xhr.open("POST", _base + "/command")
        xhr.setRequestHeader("Authorization", _token)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(body)
    }

    function playPause() { _send("playPause"); playing = !playing; _anchorSec = positionMs / 1000; _anchorTime = Date.now() }
    function next()      { _send("next") }
    function previous()  { _send("previous") }
    function seek(ms)    { _send("seekTo", Math.round(ms / 1000)); _anchorSec = ms / 1000; _anchorTime = Date.now() }
    function setVolume(v){ _send("setVolume", Math.max(0, Math.min(100, Math.round(v)))); volume = v }
    function cycleRepeat()   { _send("switchRepeat", 1) }
    function raise()         { } // app window raise handled via Hyprland special-ws elsewhere

    Component.onCompleted: _tokenProc.running = true
}
