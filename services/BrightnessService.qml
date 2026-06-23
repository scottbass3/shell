pragma Singleton
import QtQuick
import Quickshell.Io

// Screen backlight control via brightnessctl. Degrades gracefully (available=false)
// if brightnessctl is missing — the dashboard hides the slider in that case.
QtObject {
    id: root

    property int  value:     50      // percent 0..100
    property bool available:  false

    function set(pct) {
        const p = Math.max(1, Math.min(100, Math.round(pct)))
        value = p
        _set.command = ["brightnessctl", "-q", "s", p + "%"]
        _set.running = true
    }

    function refresh() {
        _get.running = true
    }

    property Process _set: Process { running: false }

    property Process _get: Process {
        command: ["sh", "-c",
            "max=$(brightnessctl m); cur=$(brightnessctl g); " +
            "[ \"$max\" -gt 0 ] && echo $((100 * cur / max)) || echo -1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text)
                if (!isNaN(v) && v >= 0) {
                    root.value     = v
                    root.available = true
                }
            }
        }
    }

    // Poll occasionally so external brightness changes reflect in the slider.
    property Timer _poll: Timer {
        interval: 5000; repeat: true; running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
