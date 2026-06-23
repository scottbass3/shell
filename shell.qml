import QtQuick
import Quickshell
import Quickshell.Io
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
