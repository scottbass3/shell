pragma Singleton
import QtQuick
import Quickshell

// Resolves filesystem paths for the shell. This file lives in services/, so
// ".." is the config root. Two roots:
//   configDir — the (read-only) checkout: code, presets, scripts, plugin.
//   stateDir  — mutable user state, kept OUTSIDE the checkout under XDG state
//               ($XDG_STATE_HOME/quickshell, default ~/.local/state/quickshell):
//               settings, themes, pins, usage, generated binds.
QtObject {
    // e.g. "/home/<user>/.config/quickshell"
    readonly property string configDir:
        Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "").replace(/\/+$/, "")
    readonly property string scriptsDir: configDir + "/scripts/hypr"
    function script(name) { return scriptsDir + "/" + name }

    // $XDG_STATE_HOME/quickshell, else ~/.local/state/quickshell — same logic
    // as hypr/quickshell.lua and install.sh so all three agree.
    readonly property string stateDir: {
        let base = String(Quickshell.env("XDG_STATE_HOME") || "").trim().replace(/\/+$/, "")
        if (base === "") {
            const home = String(Quickshell.env("HOME") || "").replace(/\/+$/, "")
            base = (home !== "" ? home : configDir.replace(/\/\.config\/quickshell$/, "")) + "/.local/state"
        }
        return base + "/quickshell"
    }
    function state(name) { return stateDir + "/" + name }
}
