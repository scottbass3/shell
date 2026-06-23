pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Audio spectrum via cava (raw ascii on stdout). Exposes `levels` (0..1 array).
// Only runs while `active` is true (e.g. the media tab is visible) to save CPU.
QtObject {
    id: root

    readonly property int bars: 48
    property var  levels: []
    property bool active: false

    // Spectral-flux onset detection: a "tap" fires when the overall spectrum
    // rises sharply vs the previous frame. Each tap alternates the paw (frame).
    property int   frame:    0       // 0 / 1 → which paw is down
    property var   _prev:    []
    property real  _fluxAvg: 0
    property int   _since:   0

    readonly property string _cfg:
        Qt.resolvedUrl("../cava.conf").toString().replace(/^file:\/\//, "")

    property Process _proc: Process {
        command: ["cava", "-p", root._cfg]
        running: root.active
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line) return
                const parts = line.split(";")
                const out = []
                for (let i = 0; i < parts.length; i++) {
                    if (parts[i] === "") continue
                    const v = parseInt(parts[i])
                    if (!isNaN(v)) out.push(Math.max(0, Math.min(1, v / 100)))
                }
                if (out.length) {
                    root.levels = out
                    // Spectral flux = sum of positive changes vs previous frame
                    let flux = 0
                    const m = Math.min(out.length, root._prev.length)
                    for (let k = 0; k < m; k++) {
                        const d = out[k] - root._prev[k]
                        if (d > 0) flux += d
                    }
                    root._prev = out
                    // Slow baseline so onset spikes don't inflate the threshold
                    root._fluxAvg = root._fluxAvg * 0.93 + flux * 0.07
                    root._since++
                    // Onset → alternate the paw
                    if (flux > root._fluxAvg * 1.28 && flux > 0.3 && root._since > 4) {
                        root.frame = root.frame === 0 ? 1 : 0
                        root._since = 0
                    }
                }
            }
        }
    }

    // Clear bars + detector state when stopped so the ring rests flat.
    onActiveChanged: if (!active) { levels = []; _prev = []; _fluxAvg = 0; _since = 0 }
}
