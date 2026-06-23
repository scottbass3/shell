pragma Singleton
import QtQuick
import Quickshell.Io
import "." as Svc

// Pinned apps for the launcher. Ordered list of app keys (DesktopEntry ids),
// persisted to ~/.config/quickshell/launcher/pinned.json as { "pinned": [...] }.
// Seeded with a few common apps on first run so the grid isn't empty before
// the context menu (9e) lets the user manage pins.
QtObject {
    id: root

    readonly property string _path:
        Qt.resolvedUrl("../launcher/pinned.json").toString().replace(/^file:\/\//, "")

    property var pinned: []          // array of keys, in display order
    property bool _loaded: false

    function isPinned(key) { return pinned.indexOf(key) >= 0 }

    function pin(key) {
        if (!key || isPinned(key)) return
        const p = pinned.slice(); p.push(key); pinned = p; _save()
    }
    function unpin(key) {
        const i = pinned.indexOf(key)
        if (i < 0) return
        const p = pinned.slice(); p.splice(i, 1); pinned = p; _save()
    }
    function toggle(key) { isPinned(key) ? unpin(key) : pin(key) }

    // Reorder by KEY (robust to display filtering/pagination): move `key` to just
    // before `beforeKey`. Empty/unknown beforeKey → move to the end.
    function moveBefore(key, beforeKey) {
        if (!key) return
        const p = pinned.slice()
        const fi = p.indexOf(key)
        if (fi < 0) return
        p.splice(fi, 1)
        let dst
        if (beforeKey && beforeKey !== key) {
            dst = p.indexOf(beforeKey)
            if (dst < 0) dst = p.length
        } else {
            dst = p.length
        }
        p.splice(dst, 0, key)
        let same = p.length === pinned.length
        for (let i = 0; same && i < p.length; i++) if (p[i] !== pinned[i]) same = false
        if (same) return
        pinned = p; _save()
    }

    // ── Persistence ─────────────────────────────────────────────────────────--
    property FileView _view: FileView {
        path:         root._path
        watchChanges: false
        blockLoading: true
        onLoaded: root._ingest(text())
    }

    function _ingest(txt) {
        try {
            const d = JSON.parse(txt)
            if (d && Array.isArray(d.pinned)) { pinned = d.pinned; _loaded = true; return true }
        } catch(e) {}
        return false
    }

    property Process _write: Process { running: false }
    function _save() {
        const json = JSON.stringify({ pinned: pinned }).replace(/'/g, "'\\''")
        const p = _path.replace(/'/g, "'\\''")
        _write.command = ["sh", "-c",
            "mkdir -p \"$(dirname '" + p + "')\" && printf '%s' '" + json + "' > '" + p + "'"]
        _write.running = true
    }

    // Seed defaults from the installed apps if nothing was loaded.
    function _seed() {
        if (_loaded || pinned.length) return
        const a = Svc.AppService.apps
        const want = ["firefox", "chromium", "kitty", "Alacritty", "code", "codium",
                      "thunar", "nautilus", "org.gnome.Nautilus", "spotify",
                      "discord", "vesktop", "Rocket.Chat"]
        const keys = []
        for (let i = 0; i < a.length; i++) {
            const k = Svc.AppService.keyOf(a[i])
            const n = (a[i].name || "").toLowerCase()
            if (want.some(w => k.toLowerCase().indexOf(w.toLowerCase()) >= 0 ||
                               n.indexOf(w.toLowerCase()) >= 0)) keys.push(k)
        }
        // fall back to first few apps if none of the wanted ones exist
        if (!keys.length) for (let i = 0; i < Math.min(8, a.length); i++) keys.push(Svc.AppService.keyOf(a[i]))
        pinned = keys
        if (keys.length) _save()
    }

    Component.onCompleted: {
        if (!_ingest(_view.text())) {
            // No file yet — seed once the app list is available.
            _seedTimer.start()
        }
    }
    property Timer _seedTimer: Timer {
        interval: 400; repeat: false
        onTriggered: root._seed()
    }
}
