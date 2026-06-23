pragma Singleton
import QtQuick
import Quickshell.Io

// Probes whether optional binaries are installed, so opt-in features can be
// gated and the user prompted to install what's missing (never auto-installed —
// this shell is meant to be distributed with minimal hard dependencies).
QtObject {
    id: root

    // name → { bin, pkg (install hint), desc }
    readonly property var deps: ({
        "cava":         { bin: "cava",         pkg: "cava",          desc: "Audio visualizer" },
        "wf-recorder":  { bin: "wf-recorder",  pkg: "wf-recorder",   desc: "Screen recording" },
        "slurp":        { bin: "slurp",        pkg: "slurp",         desc: "Region select (recorder/screenshot)" },
        "matugen":      { bin: "matugen",      pkg: "matugen (AUR)", desc: "Wallpaper-based theming" },
        "node":         { bin: "node",         pkg: "nodejs",        desc: "YouTube Music companion bridge" },
        "superfile":    { bin: "spf",          pkg: "superfile",     desc: "File explorer tool" },
        "beacon":       { bin: "beacon",       pkg: "beacon",        desc: "Docker repo explorer" },
        "jq":           { bin: "jq",           pkg: "jq",            desc: "Workspace / window helper scripts" },
        "secret-tool":  { bin: "secret-tool",  pkg: "libsecret",     desc: "Keyring (tokens, CalDAV)" },
        "brightnessctl":{ bin: "brightnessctl",pkg: "brightnessctl", desc: "Brightness control" }
    })

    property var present: ({})   // name → bool
    property int rev: 0

    function available(name) { void root.rev; return present[name] === true }
    function pkg(name)  { const d = deps[name]; return d ? d.pkg  : name }
    function desc(name) { const d = deps[name]; return d ? d.desc : "" }

    property Process _probe: Process {
        stdout: StdioCollector { onStreamFinished: root._parse(text) }
    }
    function recheck() {
        const names = Object.keys(root.deps)
        const parts = []
        for (let i = 0; i < names.length; i++) {
            const b = root.deps[names[i]].bin
            parts.push("command -v '" + b + "' >/dev/null 2>&1 && echo '" + names[i] + "=1' || echo '" + names[i] + "=0'")
        }
        _probe.command = ["sh", "-c", parts.join(";")]
        _probe.running = true
    }
    function _parse(txt) {
        const m = {}
        const lines = txt.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const t = lines[i].trim()
            const eq = t.indexOf("=")
            if (eq < 0) continue
            m[t.slice(0, eq)] = t.slice(eq + 1) === "1"
        }
        present = m
        rev++
    }

    Component.onCompleted: recheck()
}
