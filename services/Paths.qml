pragma Singleton
import QtQuick
import Quickshell

// Resolves filesystem paths for the shell. This file lives in services/, so
// ".." is the config root. Two roots:
//   configDir — the (read-only) checkout: code, presets, scripts, plugin.
//   stateDir  — mutable user state, kept OUTSIDE the checkout under XDG state
//               ($XDG_STATE_HOME/scottbass3-shell, default
//               ~/.local/state/scottbass3-shell): settings, themes, pins, usage,
//               generated binds.
QtObject {
    // e.g. "/home/<user>/.config/quickshell"
    readonly property string configDir:
        Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "").replace(/\/+$/, "")
    readonly property string scriptsDir: configDir + "/scripts/hypr"
    function script(name) { return scriptsDir + "/" + name }

    // $XDG_STATE_HOME/scottbass3-shell, else ~/.local/state/scottbass3-shell —
    // same logic as hypr/quickshell.lua and install.sh so all three agree.
    readonly property string stateDir: {
        let base = String(Quickshell.env("XDG_STATE_HOME") || "").trim().replace(/\/+$/, "")
        if (base === "") base = String(Quickshell.env("HOME") || "").replace(/\/+$/, "") + "/.local/state"
        return base + "/scottbass3-shell"
    }
    function state(name) { return stateDir + "/" + name }
}
