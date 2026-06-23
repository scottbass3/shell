pragma Singleton
import QtQuick

// Resolves filesystem paths for the shell. This file lives in services/, so
// ".." is the config root. Two roots:
//   configDir — the (read-only) checkout: code, presets, scripts, plugin.
//   stateDir  — mutable user state, kept OUTSIDE the checkout under XDG state
//               (~/.local/state/quickshell): settings, themes, pins, usage.
QtObject {
    // e.g. "/home/<user>/.config/quickshell"
    readonly property string configDir:
        Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "").replace(/\/+$/, "")
    readonly property string scriptsDir: configDir + "/scripts/hypr"
    function script(name) { return scriptsDir + "/" + name }

    // ~/.local/state/quickshell — derived from configDir's home so no env
    // access is needed. Falls back gracefully for non-default XDG_CONFIG_HOME.
    readonly property string stateDir: {
        let home = configDir.replace(/\/\.config\/quickshell$/, "")
        if (home === configDir) home = configDir.replace(/\/quickshell$/, "")
        return home + "/.local/state/quickshell"
    }
    function state(name) { return stateDir + "/" + name }
}
