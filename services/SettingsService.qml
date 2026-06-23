pragma Singleton
import QtQuick
import Quickshell.Io

// Central, forward-compatible config for the shell. Persists to
// ~/.config/quickshell/settings.json. Components read values with
//   SettingsService.get("bar.clock.use24h", true)
// and write with SettingsService.set(path, value) — both dotted paths. Reads
// depend on `rev` so bindings update live; unknown keys return the caller's
// default (so old config files keep working as new keys are added).
QtObject {
    id: root

    // Config root (this file lives in services/, so go up one).
    readonly property string _path:
        Qt.resolvedUrl("../settings.json").toString().replace(/^file:\/\//, "")

    property var _data: ({})
    property int rev: 0          // bump → re-eval get() bindings

    function get(path, def) {
        void root.rev
        const parts = path.split(".")
        let o = _data
        for (let i = 0; i < parts.length; i++) {
            if (o === null || typeof o !== "object") return def
            o = o[parts[i]]
        }
        return (o === undefined || o === null) ? def : o
    }

    function set(path, value) {
        const parts = path.split(".")
        const d = JSON.parse(JSON.stringify(_data || {}))   // deep clone
        let o = d
        for (let i = 0; i < parts.length - 1; i++) {
            if (typeof o[parts[i]] !== "object" || o[parts[i]] === null) o[parts[i]] = {}
            o = o[parts[i]]
        }
        o[parts[parts.length - 1]] = value
        _data = d
        rev++
        _save()
    }

    function toggle(path, def) { set(path, !get(path, def)) }
    function reset() { _data = ({}); rev++; _save() }

    // ── Persistence ─────────────────────────────────────────────────────────--
    property FileView _view: FileView {
        path:         root._path
        watchChanges: false
        blockLoading: true
        onLoaded: { try { root._data = JSON.parse(text()) || {}; root.rev++ } catch (e) { root._data = ({}) } }
    }

    property Process _write: Process { running: false }
    function _save() {
        const json = JSON.stringify(_data).replace(/'/g, "'\\''")
        const p = _path.replace(/'/g, "'\\''")
        _write.command = ["sh", "-c",
            "mkdir -p \"$(dirname '" + p + "')\" && printf '%s' '" + json + "' > '" + p + "'"]
        _write.running = true
    }

    Component.onCompleted: { try { _data = JSON.parse(_view.text()) || {} } catch (e) { _data = ({}) } }
}
