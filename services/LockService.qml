pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pam
import "."

// Lock state + PAM authentication for the custom WlSessionLock screen.
QtObject {
    id: root

    property bool   locked: false
    property bool   busy:   false       // auth in progress
    property string error:  ""
    property string _pw:    ""

    // Live current wallpaper so the lock screen stays in sync with changes /
    // rotation. Falls back to the hyprpaper.conf entry when the service hasn't
    // resolved one (e.g. hyprpaper absent).
    readonly property string wallpaper:
        WallpaperService.current !== "" ? WallpaperService.current : _confWallpaper
    property string _confWallpaper: ""

    // Current username (for the prompt)
    property string userName: ""
    property Process _whoami: Process {
        command: ["whoami"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.userName = text.trim() }
    }

    function lock()   { error = ""; locked = true }

    function submit(pw) {
        if (busy || pw === "") return
        _pw   = pw
        error = ""
        busy  = true
        _pam.start()
    }

    property PamContext _pam: PamContext {
        config: "login"
        onPamMessage: { if (responseRequired) respond(root._pw) }
        onCompleted: (result) => {
            root.busy = false
            root._pw  = ""
            if (result === PamResult.Success) {
                root.error  = ""
                root.locked = false
            } else if (result === PamResult.MaxTries) {
                root.error = "Trop de tentatives"
            } else {
                root.error = "Mot de passe incorrect"
            }
        }
        onError: (msg) => { root.busy = false; root._pw = ""; root.error = "Erreur d'authentification" }
    }

    // Fallback: first wallpaper entry from hyprpaper.conf (used only until the
    // WallpaperService resolves a live path).
    property Process _wp: Process {
        command: ["sh", "-c",
            "grep -m1 '^wallpaper' ~/.config/hypr/hyprpaper.conf 2>/dev/null | sed 's/.*,//' | tr -d ' '"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { const p = text.trim(); if (p !== "") root._confWallpaper = p }
        }
    }
}
