pragma Singleton
import QtQuick
import Quickshell.Io

// Region screen recording via wf-recorder. recording == wf-recorder alive.
// Configurable via settings: tools.recorder.dir, tools.recorder.audio.
QtObject {
    id: root

    // True while wf-recorder runs (start process stays alive for the recording).
    readonly property bool recording: _rec.running
    // Last stderr line from wf-recorder/slurp (empty when clean). For debugging.
    property string lastError: ""

    function toggle() {
        if (_rec.running) { _stop.running = true; return }
        lastError = ""

        const raw   = (SettingsService.get("tools.recorder.dir", "") || "").trim()
        const dir   = raw.length ? raw : "$HOME/Videos"
        const audio = SettingsService.get("tools.recorder.audio", false)

        // tilde expansion handled in-shell (POSIX); $HOME default expands via double quotes.
        _rec.command = ["sh", "-c",
            "D=\"" + dir + "\"; case \"$D\" in \"~\"|\"~/\"*) D=\"$HOME${D#~}\";; esac; mkdir -p \"$D\"; " +
            "G=\"$(slurp)\" || { echo 'slurp: region selection cancelled' >&2; exit 1; }; " +
            "exec wf-recorder " + (audio ? "-a " : "") +
            "-g \"$G\" -f \"$D/rec-$(date +%Y%m%d-%H%M%S).mp4\""]
        _rec.running = true
    }

    // slurp picks a region; wf-recorder records until killed.
    // wf-recorder stderr flows through exec to Quickshell's pipe → SplitParser → lastError.
    property Process _rec: Process {
        running: false
        stderr: SplitParser {
            onRead: line => { if (line.trim().length) root.lastError = line }
        }
    }
    // Graceful stop so the file is finalized.
    property Process _stop: Process { command: ["pkill", "-INT", "-x", "wf-recorder"]; running: false }
}
