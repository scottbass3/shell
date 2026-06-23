import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "./theme"
import "./bar"
import "./panels"
import "./services"

ShellRoot {
    id: root
    // Deduplicated screen list — Quickshell can report phantom/duplicate
    // screens (Qt HiDPI quirk). Filter to one entry per unique screen name.
    property var _seenNames: []
    property var uniqueScreens: []

    Connections {
        target: Quickshell
        function onScreensChanged() { root._rebuildScreens() }
    }

    function _rebuildScreens() {
        const seen = {}
        const result = []
        const all = Quickshell.screens
        for (let i = 0; i < all.length; i++) {
            const s = all[i]
            if (s && s.name && !seen[s.name]) {
                seen[s.name] = true
                result.push(s)
            }
        }
        uniqueScreens = result
    }

    Component.onCompleted: _rebuildScreens()

    // Exclusive zone shim — pushes app windows below barHeight
    Variants {
        model: uniqueScreens
        BarExclusionZone {}
    }

    // Single fullscreen layer — bar + borders + panels + right-edge tools toolbar
    // (all share the SDF blob rendering so panels blend into the border)
    Variants {
        model: uniqueScreens
        MainWindow {}
    }

    // App launcher (Win11-style start menu) — rendered inside MainWindow's blob
    // layer (merges with the bottom screen border), driven by LauncherService.

    // External launcher trigger:  qs ipc call launcher toggle
    IpcHandler {
        target: "launcher"
        function toggle(): void { LauncherService.toggle() }
        function open():   void { LauncherService.show() }
        function close():  void { LauncherService.hide() }
    }

    // Per-monitor workspaces:  qs ipc call ws go <n> <switch|move>
    // Monitor k owns workspaces k*10+1 .. k*10+10, so every screen has its own
    // "1..10". switch uses the focused monitor; move uses the active window's
    // monitor (keeps it on its own screen). Replaces scripts/hypr/ws.sh.
    IpcHandler {
        target: "ws"
        function go(n: string, action: string): void {
            const N = parseInt(n); if (isNaN(N)) return
            const useWin = action === "move" && Hyprland.activeToplevel && Hyprland.activeToplevel.monitor
            const mon = useWin ? Hyprland.activeToplevel.monitor : Hyprland.focusedMonitor
            const monid   = mon ? mon.id   : 0
            const monname = mon ? mon.name : ""
            const ws = monid * 10 + N
            // Pin the target workspace to its home monitor (fixes drift); harmless
            // if it doesn't exist yet — focus/move below creates it correctly.
            if (monname !== "")
                Hyprland.dispatch('hl.dsp.workspace.move({workspace = "' + ws + '", monitor = "' + monname + '"})')
            if (action === "move") Hyprland.dispatch('hl.dsp.window.move({workspace = ' + ws + '})')
            else                   Hyprland.dispatch('hl.dsp.focus({workspace = ' + ws + '})')
        }
    }

    // Scratchpad:  qs ipc call scratchpad toggle
    // Closes whichever special workspace is open on the focused monitor, else
    // opens special:magic. The monitor IPC object's specialWorkspace isn't
    // refreshed on special-ws changes, so we query hyprctl fresh each time and
    // parse the JSON in QML (no jq).
    property Process _scratchProbe: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                let mons
                try { mons = JSON.parse(text) } catch (e) { return }
                const m  = mons.find(x => x.focused) || mons[0]
                const sw = (m && m.specialWorkspace) ? (m.specialWorkspace.name || "") : ""
                const ws = sw !== "" ? sw.replace(/^special:/, "") : "magic"
                Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + ws + '")')
            }
        }
    }
    IpcHandler {
        target: "scratchpad"
        function toggle(): void {
            root._scratchProbe.command = ["hyprctl", "monitors", "-j"]
            root._scratchProbe.running = false
            root._scratchProbe.running = true
        }
    }

    // Settings window (centered modal) — one per screen, shows on focused one
    Variants {
        model: uniqueScreens
        Settings {}
    }

    // External settings trigger:  qs ipc call settings toggle
    IpcHandler {
        target: "settings"
        function toggle(): void { SettingsUi.toggle() }
        function open():   void { SettingsUi.show() }
        function close():  void { SettingsUi.hide() }
    }

    // Notification center:  qs ipc call notifications toggle
    IpcHandler {
        target: "notifications"
        function toggle(): void { NotificationService.centerOpen && !NotificationService.toastMode
            ? NotificationService.closeCenter() : NotificationService.openCenter(null) }
        function open():   void { NotificationService.openCenter(null) }
        function close():  void { NotificationService.closeCenter() }
    }

    // Custom session lock (WlSessionLock) — see LockScreen.qml
    LockScreen {}

    // External lock trigger:  qs ipc call lock lock
    IpcHandler {
        target: "lock"
        function lock(): void { LockService.lock() }
    }

    // Tools toolbar (keyboard mode):  qs ipc call tools toggle
    IpcHandler {
        target: "tools"
        function toggle(): void { ToolsService.toggle() }
        function open():   void { ToolsService.openKbd() }
        function close():  void { ToolsService.close() }
    }

    // Toast handled by MainWindow's notification panel (extends with newest notif,
    // hover to expand full stack, auto-dismisses after 5 s)
}
