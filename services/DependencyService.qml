pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Probes whether optional binaries are installed, so opt-in features can be
// gated and the user prompted to install what's missing. Nothing is installed
// automatically: install() opens the package manager in a terminal, where the
// user confirms (and types their password) themselves.
QtObject {
    id: root

    // name → { bin | qml | file, pkg, aur?, post?, desc }
    //   bin: probed with `command -v`   qml: probed for the QML module's qmldir
    //   file: probed for a file the package installs
    //   pkg: Arch package (aur: from the AUR)   post: command run after installing
    readonly property var deps: ({
        "cava":               { bin: "cava",                pkg: "cava",                 desc: "Audio visualizer" },
        "matugen":            { bin: "matugen",             pkg: "matugen", aur: true,   desc: "Wallpaper-based theming" },
        "magick":             { bin: "magick",              pkg: "imagemagick",          desc: "Auto light/dark from wallpaper" },
        "secret-tool":        { bin: "secret-tool",         pkg: "libsecret",            desc: "Keyring (tokens, CalDAV)" },
        "brightnessctl":      { bin: "brightnessctl",       pkg: "brightnessctl",        desc: "Brightness control" },
        "qt6-websockets":     { qml: "QtWebSockets",        pkg: "qt6-websockets",       desc: "YouTube Music companion (realtime)" },
        "hyprpaper":          { bin: "hyprpaper",           pkg: "hyprpaper",            desc: "Wallpaper switcher + theme" },
        "khal":               { bin: "khal",                pkg: "khal",                 desc: "Calendar events" },
        "vdirsyncer":         { bin: "vdirsyncer",          pkg: "vdirsyncer",           desc: "Calendar sync (CalDAV)" },
        "nmcli":              { bin: "nmcli",               pkg: "networkmanager",       desc: "VPN connections (network panel)" },
        "wpctl":              { bin: "wpctl",               pkg: "wireplumber",          desc: "Bluetooth audio profile switching" },
        "curl":               { bin: "curl",                pkg: "curl",                 desc: "Online wallpaper downloads" },
        "qalc":               { bin: "qalc",                pkg: "libqalculate",         desc: "Launcher calculator: units, conversions, currencies" },
        "clipd":              { bin: "clipd",               pkg: "scottbass3-clipd-git", aur: true,
                                post: "systemctl --user enable --now clipd.service",      desc: "Clipboard history" },
        "greeter":            { file: "/usr/share/scottbass3-greeter/shell.qml", pkg: "scottbass3-greeter-git", aur: true,
                                desc: "Login screen (point greetd at it, see its README)" }
    })

    property var present: ({})   // name → bool
    property int rev: 0

    // What the system offers for installing: pacman, an AUR helper, a terminal.
    property bool   hasPacman: false
    property string aurHelper: ""
    property string terminal:  ""

    function available(name) { void root.rev; return present[name] === true }
    function pkg(name)  { const d = deps[name]; return d ? d.pkg + (d.aur ? " (AUR)" : "") : name }
    function desc(name) { const d = deps[name]; return d ? d.desc : "" }

    // The shell command installing `name`, or "" when this system can't.
    function installCommand(name) {
        const d = deps[name]
        if (!d || !hasPacman) return ""
        let cmd = d.aur ? (aurHelper !== "" ? aurHelper + " -S --needed " + d.pkg : "")
                        : "sudo pacman -S --needed " + d.pkg
        if (cmd !== "" && d.post) cmd += " && " + d.post
        return cmd
    }
    function canInstall(name) { return terminal !== "" && installCommand(name) !== "" }

    function install(name) {
        const cmd = installCommand(name)
        if (cmd === "" || terminal === "") return
        const script = 'printf "\\033[1m$ %s\\033[0m\\n\\n" "$1"; sh -c "$1"; '
                     + 'printf "\\nPress Enter to close"; read _'
        Quickshell.execDetached(_terminalArgs(["sh", "-c", script, "sh", cmd]))
        _waitFor = name
        _poll.restart()
    }

    // How each terminal takes a command to run.
    function _terminalArgs(argv) {
        switch (terminal) {
        case "xdg-terminal-exec":
        case "kitty":
        case "foot":           return [terminal].concat(argv)
        case "wezterm":        return ["wezterm", "start", "--"].concat(argv)
        case "gnome-terminal": return ["gnome-terminal", "--"].concat(argv)
        default:               return [terminal, "-e"].concat(argv)
        }
    }

    // Terminals often return at once, so poll until the package shows up.
    property string _waitFor: ""
    property int    _polls: 0
    property Timer _poll: Timer {
        interval: 5000
        repeat: true
        onRunningChanged: if (running) root._polls = 0
        onTriggered: {
            if (root.available(root._waitFor) || ++root._polls > 60) { stop(); return }
            root.recheck()
        }
    }

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
            } else if (d.file) {
                parts.push("[ -e '" + d.file + "' ] && echo '" + n + "=1' || echo '" + n + "=0'")
            } else {
                parts.push("command -v '" + d.bin + "' >/dev/null 2>&1 && echo '" + n + "=1' || echo '" + n + "=0'")
            }
        }
        parts.push("command -v pacman >/dev/null 2>&1 && echo '@pacman=1'")
        parts.push("for h in paru yay; do command -v $h >/dev/null 2>&1 && { echo \"@aur=$h\"; break; }; done")
        parts.push("for t in \"$TERMINAL\" xdg-terminal-exec kitty foot alacritty wezterm ghostty konsole gnome-terminal; do " +
                   "[ -n \"$t\" ] && command -v \"$t\" >/dev/null 2>&1 && { echo \"@term=$t\"; break; }; done")
        _probe.command = ["sh", "-c", parts.join(";")]
        _probe.running = true
    }
    function _parse(txt) {
        const m = {}
        let pacman = false, aur = "", term = ""
        const lines = txt.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const t = lines[i].trim()
            const eq = t.indexOf("=")
            if (eq < 0) continue
            const k = t.slice(0, eq), v = t.slice(eq + 1)
            if (k === "@pacman") pacman = v === "1"
            else if (k === "@aur") aur = v
            else if (k === "@term") term = v
            else m[k] = v === "1"
        }
        hasPacman = pacman
        aurHelper = aur
        terminal = term
        present = m
        rev++
    }

    Component.onCompleted: recheck()
}
