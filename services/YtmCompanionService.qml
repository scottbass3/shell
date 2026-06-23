pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// YouTube Music Desktop App — companion-server integration (ytmdesktop v2).
// REST polling (GET /api/v1/state ~1/s) + commands (POST /api/v1/command),
// authenticated with a token kept in the keyring (secret-tool, never plaintext
// on disk). Gives an always-present YT Music player (even when paused) with
// richer data than MPRIS: album art, like status, volume, queue. Position is
// interpolated between polls. MPRIS remains the fallback when this is offline.
QtObject {
    id: root

    readonly property string _base: "http://127.0.0.1:9863/api/v1"
    property string _token: ""
    property bool   active:  false   // UI sets true while watching (gates polling)

    // ── Exposed state ─────────────────────────────────────────────────────────
    property bool   reachable: false          // server answered the last poll
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

    readonly property string _scriptPath:
        Qt.resolvedUrl("../scripts/ytmd-bridge/bridge.js").toString().replace(/^file:\/\//, "")

    // ── Token load (keyring) — for commands (the bridge reads its own) ─────────
    property Process _tokenProc: Process {
        command: ["secret-tool", "lookup", "service", "ytmd-companion", "key", "token"]
        stdout: StdioCollector { onStreamFinished: root._token = text.trim() }
    }

    // ── Realtime bridge (socket.io via node) ───────────────────────────────────
    // The companion REST /state is rate-limited to 1/5s; realtime is socket.io.
    // A small node helper streams compact JSON state lines on stdout. Runs only
    // while active (UI watching); stopping it disconnects the socket.
    // bash -lc so nvm's `node` is on PATH.
    // Always on (once the token is loaded) so YT's state is known globally —
    // needed for cross-player auto-pause and always-present in the UI. socket.io
    // is push (idle is cheap), so a persistent connection is fine.
    property Process _bridge: Process {
        running: root._token !== "" && SettingsService.get("media.ytm", true)
        command: ["bash", "-lc", "exec node '" + root._scriptPath + "'"]
        stdout: SplitParser { onRead: line => root._parseLine(line) }
        onRunningChanged: if (!running) root.reachable = false
        onExited: root.reachable = false
    }

    function _parseLine(line) {
        if (!line || line.trim() === "") return
        let c
        try { c = JSON.parse(line) } catch (e) { return }   // ignore stray stderr/noise
        if (!c.ok) return
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

    // ── Commands ────────────────────────────────────────────────────────────--
    property Process _cmd: Process {}
    function _send(command, data) {
        if (_token === "") return
        const body = data !== undefined ? JSON.stringify({ command: command, data: data })
                                        : JSON.stringify({ command: command })
        _cmd.command = ["curl", "-s", "-m", "3", "-X", "POST", _base + "/command",
                        "-H", "Authorization: " + _token,
                        "-H", "Content-Type: application/json",
                        "-d", body]
        _cmd.running = true
        // No immediate re-poll: /state is rate-limited to 1/5s. Optimistic local
        // updates (below) cover the gap until the next scheduled poll.
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
