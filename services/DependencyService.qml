pragma Singleton
import QtQuick
import Quickshell.Io

// Probes whether optional binaries are installed, so opt-in features can be
// gated and the user prompted to install what's missing (never auto-installed —
// this shell is meant to be distributed with minimal hard dependencies).
QtObject {
    id: root

    // name → { bin | qml, pkg (install hint), desc }
    //   bin: probed with `command -v`   qml: probed for the QML module's qmldir
    readonly property var deps: ({
        "cava":               { bin: "cava",                pkg: "cava",                 desc: "Audio visualizer" },
        "matugen":            { bin: "matugen",             pkg: "matugen (AUR)",        desc: "Wallpaper-based theming" },
        "magick":             { bin: "magick",              pkg: "imagemagick",          desc: "Auto light/dark from wallpaper" },
        "secret-tool":        { bin: "secret-tool",         pkg: "libsecret",            desc: "Keyring (tokens, CalDAV)" },
        "brightnessctl":      { bin: "brightnessctl",       pkg: "brightnessctl",        desc: "Brightness control" },
        "qt6-websockets":     { qml: "QtWebSockets",        pkg: "qt6-websockets",       desc: "YouTube Music companion (realtime)" },
        "hyprpaper":          { bin: "hyprpaper",           pkg: "hyprpaper",            desc: "Wallpaper switcher + theme" },
        "khal":               { bin: "khal",                pkg: "khal",                 desc: "Calendar events" },
        "vdirsyncer":         { bin: "vdirsyncer",          pkg: "vdirsyncer",           desc: "Calendar sync (CalDAV)" },
        "nmcli":              { bin: "nmcli",               pkg: "networkmanager",       desc: "VPN connections (network panel)" },
        "wpctl":              { bin: "wpctl",               pkg: "wireplumber",          desc: "Bluetooth audio profile switching" },
        "curl":               { bin: "curl",                pkg: "curl",                 desc: "Online wallpaper downloads" }
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
            const n = names[i]
            const d = root.deps[n]
            if (d.qml) {
                // Look for the module's qmldir under the Qt QML import paths.
                parts.push("(for p in \"$(qmake6 -query QT_INSTALL_QML 2>/dev/null)\" " +
                           "/usr/lib/qt6/qml /usr/lib/qt/qml /usr/lib64/qt6/qml; do " +
                           "[ -n \"$p\" ] && [ -e \"$p/" + d.qml + "/qmldir\" ] && { echo '" + n + "=1'; exit 0; }; " +
                           "done; echo '" + n + "=0')")
            } else {
                parts.push("command -v '" + d.bin + "' >/dev/null 2>&1 && echo '" + n + "=1' || echo '" + n + "=0'")
            }
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
