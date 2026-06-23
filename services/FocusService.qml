pragma Singleton
import QtQuick
import Quickshell.Hyprland

// Keyboard-focus restore after a layer surface (launcher / settings / tools)
// releases its exclusive grab — Hyprland doesn't auto-restore it. Replaces the
// old hyprctl|jq helper scripts: reads window data from the native Hyprland
// service and bounces focus via dispatch. Addresses use lastIpcObject.address
// (the hyprctl form, with the 0x prefix) to match dispatch's expectations.
QtObject {
    id: root

    // Snapshot the focused window's address before a layer grabs the keyboard.
    function savePrev() {
        const a = Hyprland.activeToplevel
        return (a && a.lastIpcObject) ? (a.lastIpcObject.address || "") : ""
    }

    function _addr(t) { return (t && t.lastIpcObject) ? (t.lastIpcObject.address || "") : "" }

    // Re-focus `addr`. Hyprland treats re-focusing the still-"active" window as a
    // no-op, so we force a real change: bounce through another window on the same
    // workspace, or — if it's the only one — through an empty workspace, then back.
    function refocus(addr) {
        if (!addr) return
        const all = Hyprland.toplevels.values
        let me = null
        for (let i = 0; i < all.length; i++)
            if (root._addr(all[i]) === addr) { me = all[i]; break }
        if (!me) return
        const wsId = me.workspace ? me.workspace.id : null
        let other = ""
        for (let i = 0; i < all.length; i++) {
            const a = root._addr(all[i])
            if (a === "" || a === addr) continue
            const w = all[i].workspace
            if (w && w.id === wsId) { other = a; break }
        }
        if (other !== "") {
            Hyprland.dispatch('hl.dsp.focus({window = "address:' + other + '"})')
            Hyprland.dispatch('hl.dsp.focus({window = "address:' + addr + '"})')
        } else {
            Hyprland.dispatch('hl.dsp.focus({workspace = "emptynm"})')
            Hyprland.dispatch('hl.dsp.focus({window = "address:' + addr + '"})')
        }
    }
}
