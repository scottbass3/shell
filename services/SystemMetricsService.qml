pragma Singleton
import QtQuick
import Quickshell.Io

// CPU %, RAM %, and temperature via /proc + /sys, polled every 2s.
// CPU % needs two samples — previous totals kept between polls.
QtObject {
    id: root

    property real cpu:  0      // percent 0..100
    property real ram:  0      // percent 0..100
    property real temp: -1     // °C, -1 if unavailable

    property double _prevIdle:  0
    property double _prevTotal: 0

    property Process _proc: Process {
        command: ["sh", "-c",
            "head -1 /proc/stat; " +
            "grep -E 'MemTotal|MemAvailable' /proc/meminfo; " +
            "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo -1000"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._parse(text)
        }
    }

    function _parse(out) {
        const lines = out.trim().split("\n")
        let memTotal = 0, memAvail = 0, tempRaw = -1000

        for (const ln of lines) {
            if (ln.startsWith("cpu ")) {
                const p = ln.split(/\s+/).slice(1).map(Number)
                const idle  = p[3] + (p[4] || 0)          // idle + iowait
                const total = p.reduce((a, b) => a + b, 0)
                const dIdle  = total - root._prevTotal > 0 ? (idle  - root._prevIdle)  : 0
                const dTotal = total - root._prevTotal
                if (dTotal > 0)
                    root.cpu = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)))
                root._prevIdle  = idle
                root._prevTotal = total
            } else if (ln.startsWith("MemTotal")) {
                memTotal = parseInt(ln.replace(/\D+/g, ""))
            } else if (ln.startsWith("MemAvailable")) {
                memAvail = parseInt(ln.replace(/\D+/g, ""))
            } else {
                const t = parseInt(ln)
                if (!isNaN(t)) tempRaw = t
            }
        }

        if (memTotal > 0)
            root.ram = Math.max(0, Math.min(100, 100 * (1 - memAvail / memTotal)))
        root.temp = tempRaw > -1000 ? Math.round(tempRaw / 1000) : -1
    }

    property Timer _poll: Timer {
        interval: 2000; repeat: true; running: true
        onTriggered: root._proc.running = true
    }
    Component.onCompleted: _proc.running = true
}
