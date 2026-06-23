pragma Singleton
import QtQuick
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "."

QtObject {
    id: root

    property bool doNotDisturb: SettingsService.get("notifications.dndDefault", false)
    property bool centerOpen:   false
    property var  centerScreen: null   // null = all screens (toast); screen obj = bell click
    property int  unreadCount:  0
    property int  notifCount:   0      // explicitly maintained — drives reactive bindings
    property bool toastMode:    false  // true = show only latest notification

    // Hover state
    property bool bellHovered:  false
    property bool panelHovered: false

    readonly property var notifications: _server.trackedNotifications  // raw QML list
    property var notifList: []  // JS array copy — safe for arr[i], .length, etc.

    // ── Toast stack ──────────────────────────────────────────────────────────
    // Each new notification adds its own toast with an independent 5 s expiry —
    // toasts stack instead of replacing one another.
    readonly property int _toastTTL: SettingsService.get("notifications.toastMs", 5000)
    readonly property int _toastMax: SettingsService.get("notifications.toastMax", 5)  // cap visible toast stack
    property var _toastEntries: []                // [{ n: notif, exp: ms }]

    readonly property int toastCount: _toastEntries.length
    // Newest-first for display (newest toast on top)
    readonly property var toastNotifs: {
        const a = []
        for (let i = _toastEntries.length - 1; i >= 0; i--) a.push(_toastEntries[i].n)
        return a
    }

    // Prunes expired toasts; pauses while hovering so they don't vanish mid-read.
    property Timer _toastTimer: Timer {
        interval: 250
        repeat:   true
        onTriggered: {
            if (root.bellHovered || root.panelHovered) return
            const now  = Date.now()
            const kept = root._toastEntries.filter(e => e.exp > now)
            if (kept.length !== root._toastEntries.length) root._toastEntries = kept
            if (kept.length === 0) {
                stop()
                if (root.toastMode) root.closeCenter()
            }
        }
    }

    // Hover-away close delay (300 ms) — only active when NOT opened by bell
    property Timer _closeTimer: Timer {
        interval: 300
        repeat:   false
        onTriggered: { if (!root.bellHovered && !root.panelHovered) root.closeCenter() }
    }

    onBellHoveredChanged:  _evalHover()
    onPanelHoveredChanged: _evalHover()

    function _evalHover() {
        if (!centerOpen) return
        if (bellHovered || panelHovered) {
            _closeTimer.stop()
            _toastTimer.stop()
            if (toastMode) toastMode = false   // expand toast → full view
        } else {
            _closeTimer.restart()
        }
    }

    property NotificationServer _server: NotificationServer {
        keepOnReload:     true
        actionsSupported: true
        bodySupported:    true
        imageSupported:   true

        onNotification: (notif) => {
            notif.tracked = true
            // When the app closes or replaces this notification its backing
            // object is invalidated — drop it so it doesn't linger as a blank
            // row in the center. (Our toast expiry does NOT close notifications,
            // so genuinely-received ones still persist until dismissed.)
            notif.closed.connect(() => root._drop(notif))
            root.notifList = [...root.notifList, notif]
            root.notifCount++
            if (!root.doNotDisturb) {
                root.unreadCount++
                // Suppress toast only when the full center is open (bell popout, or
                // inline non-toast center). Otherwise add to the toast stack.
                const popoutOpen     = PopoutService.currentName === "notif"
                const fullCenterOpen = root.centerOpen && !root.toastMode
                if (!popoutOpen && !fullCenterOpen) {
                    let q = [...root._toastEntries, { n: notif, exp: Date.now() + root._toastTTL }]
                    if (q.length > root._toastMax) q = q.slice(q.length - root._toastMax)
                    root._toastEntries = q
                    root.toastMode    = true
                    root.centerScreen = null   // show on all screens
                    root.centerOpen   = true
                    root._toastTimer.restart()
                }
            }
        }
    }

    // Bell opened the center via popout — clear unread + dismiss any live toast
    function markRead() {
        unreadCount = 0
    }

    // Click a notification → bring its app forward.
    //  - window on a special (tray-parked) workspace → reveal that workspace
    //  - window elsewhere → focus it (switches to its workspace)
    //  - no window found → launch the app from its desktop entry
    function activate(notif) {
        if (!notif) return
        const cands = []
        if (notif.desktopEntry) cands.push(("" + notif.desktopEntry).toLowerCase())
        if (notif.appName)      cands.push(("" + notif.appName).toLowerCase())

        // Find a matching Hyprland window (class ↔ desktop-entry/app-name).
        const tops = Hyprland.toplevels?.values ?? []
        let match = null
        for (let i = 0; i < tops.length && !match; i++) {
            const o = tops[i].lastIpcObject
            if (!o) continue
            const c = ("" + (o["class"] ?? "")).toLowerCase()
            if (!c) continue
            for (let j = 0; j < cands.length; j++) {
                const k = cands[j]
                if (c === k || c.indexOf(k) >= 0 || k.indexOf(c) >= 0) { match = o; break }
            }
        }

        if (match) {
            const addr = match.address
            const wsName = match.workspace ? ("" + (match.workspace.name ?? "")) : ""
            if (wsName.indexOf("special:") === 0) {
                // Reveal the special workspace (tray-parked app) only if it isn't
                // already shown on some monitor — toggle would otherwise hide it.
                const sw = wsName.substring("special:".length)
                let shown = false
                const mons = Hyprland.monitors?.values ?? []
                for (let m = 0; m < mons.length; m++) {
                    const mo = mons[m].lastIpcObject
                    if (mo && mo.specialWorkspace && ("" + (mo.specialWorkspace.name ?? "")) === wsName) { shown = true; break }
                }
                if (!shown)
                    Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + sw + '")')
                if (addr) Hyprland.dispatch('hl.dsp.focus({window = "address:' + addr + '"})')
            } else if (addr) {
                Hyprland.dispatch('hl.dsp.focus({window = "address:' + addr + '"})')
            }
        } else {
            // No live window — launch from the desktop entry if resolvable.
            let app = null
            if (notif.desktopEntry) app = AppService.byKey("" + notif.desktopEntry) || AppService.byClass("" + notif.desktopEntry)
            if (!app && notif.appName) app = AppService.byClass("" + notif.appName)
            if (app) AppService.launch(app)
        }
        closeCenter()
    }

    function dismiss(notif) {
        notif.tracked = false
        notifList = notifList.filter(n => n !== notif)
        _toastEntries = _toastEntries.filter(e => e.n !== notif)
        if (notifCount > 0) notifCount--
        if (unreadCount > 0) unreadCount--
    }

    // Notification was closed/replaced by the app (not a user dismiss). Remove it
    // from the list/toasts so the center never shows a blanked-out entry.
    function _drop(notif) {
        if (notifList.indexOf(notif) < 0) return
        notifList = notifList.filter(n => n !== notif)
        _toastEntries = _toastEntries.filter(e => e.n !== notif)
        notifCount = notifList.length
    }

    function dismissAll() {
        notifList.forEach(n => { n.tracked = false })
        notifList     = []
        _toastEntries = []
        notifCount    = 0
        unreadCount   = 0
    }

    function openCenter(screen) {
        centerScreen = screen
        toastMode    = false
        centerOpen   = true
        unreadCount  = 0
        _toastTimer.stop()
        _closeTimer.stop()
    }

    function closeCenter() {
        centerOpen    = false
        toastMode     = false
        bellHovered   = false
        panelHovered  = false
        _toastEntries = []
        _closeTimer.stop()
        _toastTimer.stop()
    }

    function toggleCenter(screen) {
        if (centerOpen && !toastMode && centerScreen?.name === screen?.name)
            closeCenter()
        else
            openCenter(screen)
    }
}
