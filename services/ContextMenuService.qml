pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// Floating right-click context menu shared by the network and bluetooth panels.
// The menu itself is rendered top-level in MainWindow (so it can overflow the
// clipped popout); this service just holds what to show and where. Also owns the
// bluetooth audio-profile query (pw-dump) / switch (wpctl) used by the BT menu.
QtObject {
    id: root

    property bool   open:    false
    property real   anchorX: 0          // window-space anchor (cursor)
    property real   anchorY: 0
    property var    screen:  null
    property string kind:    ""         // "wifi" | "bt"
    property var    target:  null       // Network or BluetoothDevice

    function show(k, t, x, y, scr) {
        kind = k; target = t; anchorX = x; anchorY = y; screen = scr
        _profiles = []; _profilePwId = -1
        open = true
        // Keep the underlying panel alive while the menu is up.
        PopoutService.pinned = true
        if (k === "bt" && t && t.connected && DependencyService.available("wpctl"))
            queryProfiles("" + t.address)
    }
    function close() {
        open = false
        target = null
        _profiles = []
        PopoutService.keyboardActive = false
        PopoutService.pinned = false
    }

    // ── Bluetooth audio profiles (pw-dump to read, wpctl to set) ──────────────
    property var    _profiles:    []    // [{ index, desc, active }]
    property int    _profilePwId: -1
    property string _profileAddr: ""

    function _cardName(a) { return "bluez_card." + ("" + a).replace(/:/g, "_") }

    function queryProfiles(addr) {
        _profileAddr = addr
        _profiles    = []
        _profilePwId = -1
        _profileProc.running = false
        _profileProc.running = true
    }
    property Process _profileProc: Process {
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr
                try { arr = JSON.parse(text) } catch (e) { return }
                const want = root._cardName(root._profileAddr)
                for (const o of arr) {
                    if (o.type !== "PipeWire:Interface:Device") continue
                    const props = (o.info && o.info.props) || {}
                    if (props["device.name"] !== want) continue
                    const params = (o.info && o.info.params) || {}
                    const active = (params.Profile && params.Profile[0] && params.Profile[0].index)
                    const list = []
                    for (const p of (params.EnumProfile || [])) {
                        if (p.available && p.available !== "yes") continue
                        list.push({ index: p.index, desc: p.description || p.name, active: p.index === active })
                    }
                    root._profilePwId = o.id
                    root._profiles    = list
                    break
                }
            }
        }
    }
    property Process _setProfileProc: Process { running: false }
    function setProfile(idx) {
        if (_profilePwId < 0) return
        _setProfileProc.command = ["wpctl", "set-profile", "" + _profilePwId, "" + idx]
        _setProfileProc.running = false
        _setProfileProc.running = true
        _reQuery.restart()
    }
    property Timer _reQuery: Timer { interval: 700; onTriggered: root.queryProfiles(root._profileAddr) }
}
