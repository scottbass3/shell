pragma Singleton
import QtQuick

// Resolves filesystem paths inside the shell's config directory without
// hardcoding the user's home. This file lives in services/, so ".." is the
// config root. Used to locate the vendored Hyprland helper scripts.
QtObject {
    // e.g. "/home/<user>/.config/quickshell"
    readonly property string configDir:
        Qt.resolvedUrl("..").toString().replace(/^file:\/\//, "").replace(/\/+$/, "")
    readonly property string scriptsDir: configDir + "/scripts/hypr"
    function script(name) { return scriptsDir + "/" + name }
}
