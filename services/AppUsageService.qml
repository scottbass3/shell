pragma Singleton
import QtQuick
import Quickshell.Io

// App launch history → frecency scoring (frequency + recency).
// Persists per-app launch timestamps to ~/.config/quickshell/launcher/usage.json
//   { "<app-id>": [epochMs, epochMs, ...], ... }
// score(key) = Σ weight(age) over stored launches; recent + frequent ranks high.
QtObject {
    id: root

    readonly property string _path:
        Qt.resolvedUrl("../launcher/usage.json").toString().replace(/^file:\/\//, "")

    // { id: [ts, ...] } — kept in a plain JS object, reassigned to notify bindings.
    property var history: ({})
    property int _rev: 0          // bump to force recommended() re-eval
    readonly property int _cap: 50   // max timestamps kept per app

    // ── Frecency ──────────────────────────────────────────────────────────────
    function _weight(ageMs) {
        const h = 3600000, d = 24 * h
        if (ageMs < h)        return 100
        if (ageMs < d)        return 80
        if (ageMs < 7 * d)    return 40
        if (ageMs < 30 * d)   return 20
        return 10
    }

    function score(key) {
        const ts = history[key]
        if (!ts || !ts.length) return 0
        const now = Date.now()
        let s = 0
        for (let i = 0; i < ts.length; i++) s += _weight(now - ts[i])
        return s
    }

    // Top-n app ids by frecency, excluding `exclude` (e.g. pinned keys).
    function recommended(exclude, n) {
        void root._rev   // dependency: re-run when history changes
        const ex = exclude || []
        const keys = Object.keys(history).filter(k => ex.indexOf(k) < 0 && score(k) > 0)
        keys.sort((a, b) => score(b) - score(a))
        return keys.slice(0, n || 8)
    }

    // ── Mutations ───────────────────────────────────────────────────────────--
    function record(key) {
        if (!key) return
        const h = Object.assign({}, history)
        const ts = (h[key] || []).slice()
        ts.push(Date.now())
        if (ts.length > _cap) ts.splice(0, ts.length - _cap)
        h[key] = ts
        history = h
        _rev++
        _save()
    }

    // Clear an app's history (right-click → Remove resets its score to 0).
    function reset(key) {
        if (!(key in history)) return
        const h = Object.assign({}, history)
        delete h[key]
        history = h
        _rev++
        _save()
    }

    // ── Persistence ─────────────────────────────────────────────────────────--
    property FileView _view: FileView {
        path:         root._path
        watchChanges: false
        blockLoading: true
        onLoaded: {
            try { root.history = JSON.parse(text()) || {} ; root._rev++ } catch(e) { root.history = {} }
        }
    }

    property Process _write: Process { running: false }
    function _save() {
        // JSON contains only double quotes (safe inside single-quoted shell);
        // escape any stray single quote defensively.
        const json = JSON.stringify(history).replace(/'/g, "'\\''")
        const p = _path.replace(/'/g, "'\\''")
        _write.command = ["sh", "-c",
            "mkdir -p \"$(dirname '" + p + "')\" && printf '%s' '" + json + "' > '" + p + "'"]
        _write.running = true
    }

    Component.onCompleted: { try { history = JSON.parse(_view.text()) || {} } catch(e) { history = {} } }
}
