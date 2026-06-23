pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// Watches the battery and emits desktop notifications (via notify-send, which
// routes through our own NotificationServer → toast + notification center) on:
//   • charger plugged / unplugged
//   • low battery (crosses threshold while discharging)
QtObject {
    id: root

    readonly property var device: UPower.displayDevice

    readonly property int  batState: device?.state ?? UPowerDeviceState.Unknown
    readonly property int  pct:      device ? Math.round(device.percentage * 100) : -1
    readonly property bool present:  device?.isPresent ?? false
    readonly property bool charging: batState === UPowerDeviceState.Charging
                                  || batState === UPowerDeviceState.PendingCharge
                                  || batState === UPowerDeviceState.FullyCharged

    // Thresholds
    readonly property int _lowPct:      20
    readonly property int _criticalPct: 10
    readonly property int _resetPct:    25   // re-arm low warning above this

    // Don't fire on the initial state read at startup.
    property bool _ready:       false
    property bool _lowNotified: false

    property Process _notifyProc: Process {}

    function _notify(title, body, icon, urgency) {
        _notifyProc.running = false
        _notifyProc.command = ["notify-send", "-a", "Battery",
                               "-i", icon, "-u", urgency, title, body]
        _notifyProc.running = true
    }

    // ── Plug / unplug ─────────────────────────────────────────────────────────
    onChargingChanged: {
        if (!_ready || !present) return
        if (charging)
            _notify("Charger connected",
                    pct >= 0 ? "Battery at " + pct + "%" : "", "battery-charging", "low")
        else
            _notify("Charger disconnected",
                    pct >= 0 ? "Battery at " + pct + "%" : "", "battery", "low")
    }

    // ── Low battery ─────────────────────────────────────────────────────────--
    onPctChanged: {
        if (!_ready || !present || pct < 0) return

        // Re-arm once we charge back up
        if (charging || pct > _resetPct) {
            _lowNotified = false
            return
        }

        if (!_lowNotified && pct <= _lowPct) {
            _lowNotified = true
            const crit = pct <= _criticalPct
            _notify(crit ? "Battery critically low" : "Battery low",
                    pct + "% remaining" + (crit ? " — plug in now" : ""),
                    "battery-caution",
                    crit ? "critical" : "normal")
        }
    }

    // Arm after first event loop tick so startup state doesn't notify.
    property Timer _armTimer: Timer {
        interval: 1500; repeat: false; running: true
        onTriggered: root._ready = true
    }
}
