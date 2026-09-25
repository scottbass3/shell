pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Hyprland config OVERRIDE layer, managed from Settings → Hyprland. Mirrors
// BindingService: user-set values live under the `hypr.*` namespace in
// SettingsService, get generated into ~/.local/state/quickshell/hypr.generated.lua,
// and hypr/quickshell.lua sources that file AFTER the user's own config so it
// overrides (last-wins). Only keys the user actually changed are emitted — the
// user's hyprland.lua/.conf is never touched.
//
// Current effective values are read live via `hyprctl getoption` / `hyprctl
// monitors all -j`, so the panes show the real config as their baseline.
//
// Appearance + input changes apply live (write + `hyprctl reload`). Monitor
// changes stage, then apply behind a confirm-or-revert countdown (a bad mode can
// black out a screen).
QtObject {
    id: root

    readonly property string _file: Paths.state("hypr.generated.lua")

    // ── Exposed scalar options ─────────────────────────────────────────────────
    // path  — SettingsService key under "hypr." AND the getoption key with ":".
    // type  — how to serialize into Lua and parse from getoption.
    // lua   — nested key path inside hl.config({...}).
    readonly property var opts: [
        { path: "general.gaps_in",              opt: "general:gaps_in",              type: "int",    lua: ["general", "gaps_in"] },
        { path: "general.gaps_out",             opt: "general:gaps_out",             type: "int",    lua: ["general", "gaps_out"] },
        { path: "general.border_size",          opt: "general:border_size",          type: "int",    lua: ["general", "border_size"] },
        { path: "general.layout",               opt: "general:layout",               type: "str",    lua: ["general", "layout"] },
        { path: "general.allow_tearing",        opt: "general:allow_tearing",        type: "bool",   lua: ["general", "allow_tearing"] },
        { path: "general.col.active_border",    opt: "general:col.active_border",    type: "colstr", lua: ["general", "col", "active_border"] },
        { path: "general.col.inactive_border",  opt: "general:col.inactive_border",  type: "colstr", lua: ["general", "col", "inactive_border"] },
        { path: "decoration.rounding",          opt: "decoration:rounding",          type: "int",    lua: ["decoration", "rounding"] },
        { path: "decoration.blur.enabled",      opt: "decoration:blur:enabled",      type: "bool",   lua: ["decoration", "blur", "enabled"] },
        { path: "decoration.blur.size",         opt: "decoration:blur:size",         type: "int",    lua: ["decoration", "blur", "size"] },
        { path: "decoration.blur.passes",       opt: "decoration:blur:passes",       type: "int",    lua: ["decoration", "blur", "passes"] },
        { path: "decoration.shadow.enabled",    opt: "decoration:shadow:enabled",    type: "bool",   lua: ["decoration", "shadow", "enabled"] },
        { path: "input.kb_layout",              opt: "input:kb_layout",              type: "str",    lua: ["input", "kb_layout"] },
        { path: "input.kb_variant",             opt: "input:kb_variant",             type: "str",    lua: ["input", "kb_variant"] },
        { path: "input.sensitivity",            opt: "input:sensitivity",            type: "float",  lua: ["input", "sensitivity"] },
        { path: "input.follow_mouse",           opt: "input:follow_mouse",           type: "int",    lua: ["input", "follow_mouse"] },
        { path: "input.touchpad.natural_scroll",opt: "input:touchpad:natural_scroll",type: "bool",   lua: ["input", "touchpad", "natural_scroll"] },
        { path: "animations.enabled",           opt: "animations:enabled",           type: "bool",   lua: ["animations", "enabled"] }
    ]

    // ── Live baseline (read from hyprctl) ──────────────────────────────────────
    property var _liveOpts: ({})     // getoption key → current effective value
    property var monitors:  []       // [{ name,width,height,refreshRate,x,y,scale,transform,disabled,modes:[] }]

    // Current effective value for an option key, else the caller's fallback.
    function live(opt, fb) {
        void root._liveOpts   // dependency
        const v = root._liveOpts[opt]
        return (v === undefined || v === null) ? fb : v
    }

    function refresh() { _probe.running = false; _probe.running = true; _monProbe.running = false; _monProbe.running = true }

    property Process _probe: Process {
        // One getoption per exposed key, newline-delimited JSON.
        command: {
            const keys = root.opts.map(o => o.opt).join(" ")
            return ["sh", "-c", "for o in " + keys + "; do hyprctl -j getoption \"$o\"; printf '\\n'; done"]
        }
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                for (const ln of text.split("\n")) {
                    const s = ln.trim()
                    if (s === "") continue
                    let o
                    try { o = JSON.parse(s) } catch (e) { continue }
                    if (!o.option) continue
                    let v
                    if (o.int !== undefined)           v = o.int
                    else if (o.float !== undefined)    v = o.float
                    else if (o.str !== undefined)      v = o.str
                    else if (o.gradient !== undefined) v = o.gradient
                    else if (o.css !== undefined)      v = parseInt(("" + o.css).trim().split(/\s+/)[0]) || 0
                    else                               v = undefined
                    map[o.option] = v
                }
                root._liveOpts = map
            }
        }
    }

    property Process _monProbe: Process {
        command: ["hyprctl", "monitors", "all", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let arr
                try { arr = JSON.parse(text) } catch (e) { return }
                if (!Array.isArray(arr)) return
                const out = []
                for (const m of arr) {
                    out.push({
                        name:        m.name,
                        width:       m.width,
                        height:      m.height,
                        refreshRate: m.refreshRate,
                        x:           m.x,
                        y:           m.y,
                        scale:       m.scale,
                        transform:   m.transform,
                        disabled:    !!m.disabled,
                        modes:       (m.availableModes || []).map(s => ("" + s).replace(/Hz$/, ""))
                    })
                }
                root.monitors = out
                // Monitor lines need the probed outputs; the startup write ran
                // before this and dropped them. Skip while edits are staged.
                if (!root._monDirty) root._write(false)
            }
        }
    }

    function _monitorByName(n) { for (const m of monitors) if (m.name === n) return m; return null }

    // ── Lua serialization ──────────────────────────────────────────────────────
    function _luaLeaf(type, v) {
        if (type === "bool")  return v ? "true" : "false"
        if (type === "int")   return "" + Math.round(v)
        if (type === "float") return "" + v
        // str / colstr → quoted
        return '"' + ("" + v).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
    }

    function _setNested(obj, keys, leaf) {
        let o = obj
        for (let i = 0; i < keys.length - 1; i++) {
            if (o[keys[i]] === undefined || o[keys[i]].__lua !== undefined) o[keys[i]] = {}
            o = o[keys[i]]
        }
        o[keys[keys.length - 1]] = { __lua: leaf }
    }

    function _serialize(obj, indent) {
        const pad  = "    ".repeat(indent)
        const pad2 = "    ".repeat(indent + 1)
        let out = "{\n"
        for (const k of Object.keys(obj)) {
            const val = obj[k]
            if (val && typeof val === "object" && val.__lua !== undefined)
                out += pad2 + k + " = " + val.__lua + ",\n"
            else if (val && typeof val === "object")
                out += pad2 + k + " = " + _serialize(val, indent + 1) + ",\n"
        }
        out += pad + "}"
        return out
    }

    // Full monitor line for an output that has any staged override (partial
    // overrides fall back to the live value so the emitted rule stays valid).
    function _monitorLua(name) {
        const base = "hypr.monitors." + name + "."
        const keys = ["enabled", "mode", "scale", "x", "y", "transform"]
        let any = false
        for (const k of keys) if (SettingsService.get(base + k, undefined) !== undefined) { any = true; break }
        if (!any) return null

        const enabled = SettingsService.get(base + "enabled", true)
        if (enabled === false) return 'hl.monitor({ output = "' + name + '", disable = true })'

        const m = _monitorByName(name)
        const defMode = m ? (m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2)) : "preferred"
        const mode  = SettingsService.get(base + "mode",  defMode)
        const scale = SettingsService.get(base + "scale", m ? m.scale : "auto")
        const x     = SettingsService.get(base + "x",     m ? m.x : 0)
        const y     = SettingsService.get(base + "y",     m ? m.y : 0)
        const tr    = SettingsService.get(base + "transform", m ? m.transform : 0)
        return 'hl.monitor({ output = "' + name + '", mode = "' + mode + '", position = "'
             + x + "x" + y + '", scale = ' + scale + ", transform = " + tr + " })"
    }

    function _luaContent() {
        const lines = [
            "-- AUTO-GENERATED by Quickshell Settings → Hyprland. Do not edit.",
            "-- Sourced by hypr/quickshell.lua AFTER your config, so it overrides.",
            "-- Only settings you changed in the UI are emitted here.",
            ""
        ]
        const cfg = {}
        for (const o of opts) {
            const v = SettingsService.get("hypr." + o.path, undefined)
            if (v === undefined || v === null || v === "") continue
            _setNested(cfg, o.lua, _luaLeaf(o.type, v))
        }
        if (Object.keys(cfg).length > 0) lines.push("hl.config(" + _serialize(cfg, 0) + ")", "")

        for (const m of monitors) {
            const ml = _monitorLua(m.name)
            if (ml) lines.push(ml)
        }
        lines.push("")
        return lines.join("\n")
    }

    // ── Write + apply ──────────────────────────────────────────────────────────
    property Process _reload: Process { command: ["hyprctl", "reload"] }
    property bool _pendingReload: false
    property Process _writer: Process {
        onExited: if (root._pendingReload) { root._reload.running = false; root._reload.running = true }
    }
    function _write(doReload) {
        _pendingReload = (doReload !== false)
        _writer.command = ["sh", "-c", 'printf "%s" "$2" > "$1"', "_", root._file, root._luaContent()]
        _writer.running = false
        _writer.running = true
    }

    // Appearance / input: apply immediately.
    function applyLive() { _write(true) }

    // hl.monitor(...) line (effective override-or-live values) for a monitor —
    // emitted for EVERY output so a revert also restores un-overridden ones.
    // Applied LIVE via `hyprctl eval`, which reconfigures the output WITHOUT a
    // full `hyprctl reload`. A reload re-lays-out every layer surface (the bar's
    // reserved zone doesn't re-settle while the fullscreen Settings overlay is
    // mapped), so monitor edits must avoid it. (`hyprctl keyword` is refused
    // under the Lua parser — eval is the supported live path.)
    function _monitorEvalLine(m) {
        const base = "hypr.monitors." + m.name + "."
        if (SettingsService.get(base + "enabled", !m.disabled) === false)
            return 'hl.monitor({ output = "' + m.name + '", disable = true })'
        const defMode = m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2)
        const mode  = SettingsService.get(base + "mode",  defMode)
        const scale = SettingsService.get(base + "scale", m.scale)
        const x     = SettingsService.get(base + "x",     m.x)
        const y     = SettingsService.get(base + "y",     m.y)
        const tr    = SettingsService.get(base + "transform", m.transform)
        return 'hl.monitor({ output = "' + m.name + '", mode = "' + mode + '", position = "'
             + x + "x" + y + '", scale = ' + scale + ", transform = " + tr + " })"
    }
    property Process _monLive: Process { running: false }
    function _applyMonitorsLive() {
        if (monitors.length === 0) return
        _monLive.command = ["hyprctl", "eval", monitors.map(m => _monitorEvalLine(m)).join("\n")]
        _monLive.running = false
        _monLive.running = true
    }

    // Reset one override key back to the user's own config (removes it, reloads).
    function resetKey(path) { SettingsService.unset("hypr." + path); applyLive() }
    function resetKeys(paths) { for (const p of paths) SettingsService.unset("hypr." + p); applyLive() }

    // ── Monitors: staged edits + confirm-or-revert ─────────────────────────────
    property bool monitorConfirmPending: false
    property int  monitorCountdown:      0
    property bool _monDirty:             false
    property var  _prevMon:              ({})
    readonly property bool monitorsDirty: _monDirty

    // Snapshot the last-applied monitor state on the first edit of a clean cycle.
    function _snapMon() {
        if (_monDirty) return
        _prevMon  = JSON.parse(JSON.stringify(SettingsService.get("hypr.monitors", {}) || {}))
        _monDirty = true
    }
    function stageMonitor(name, key, value) { _snapMon(); SettingsService.set("hypr.monitors." + name + "." + key, value) }
    function resetMonitor(name)             { _snapMon(); SettingsService.unset("hypr.monitors." + name) }

    function applyMonitors() {
        if (!_monDirty) return
        _write(false)           // persist for next launch; no reload
        _applyMonitorsLive()    // live via keyword — no bar reflow
        monitorCountdown      = 15
        monitorConfirmPending = true
    }
    function confirmMonitors() { monitorConfirmPending = false; _monDirty = false; refresh() }
    function revertMonitors() {
        monitorConfirmPending = false
        _monDirty = false
        SettingsService.set("hypr.monitors", _prevMon)
        _write(false)
        _applyMonitorsLive()    // re-apply effective (restored) values to all outputs
        refresh()
    }

    property Timer _cdTimer: Timer {
        interval: 1000; repeat: true
        running: root.monitorConfirmPending
        onTriggered: { root.monitorCountdown -= 1; if (root.monitorCountdown <= 0) root.revertMonitors() }
    }

    // Re-sync the file on start (no reload — Hyprland already sourced it at launch)
    // and read the live baseline for the panes.
    Component.onCompleted: { refresh(); _write(false) }
}
