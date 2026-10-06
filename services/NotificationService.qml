pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "."

// Notification daemon + history. Every notification gets a stable `key` and a
// row in `history` (newest first); rows are inserted, updated and removed one at
// a time, so views never rebuild their delegates on a change. The live
// Notification object (needed for actions) is kept in `_live` until the app or
// the user closes it; an app closing it leaves the row in the history.
QtObject {
    id: root

    property bool doNotDisturb: SettingsService.get("notifications.dndDefault", false)
    property bool centerOpen:   false
    property var  centerScreen: null   // null = all screens (toast); screen obj = bell click
    property int  unreadCount:  0
    property bool toastMode:    false  // true = show only the toast stack

    // Hover state
    property bool bellHovered:  false
    property bool panelHovered: false

    readonly property int _toastTTL:   SettingsService.get("notifications.toastMs", 5000)
    readonly property int _toastMax:   SettingsService.get("notifications.toastMax", 5)
    readonly property int _maxHistory: SettingsService.get("notifications.maxHistory", 100)

    // Rows: key, appName, summary, body, icon, image, desktopEntry, time,
    // critical, transient, live, actions (JSON [{id, text}]). Toasts add `exp`
    // (0 = stays until dismissed).
    property ListModel history: ListModel {}
    property ListModel toasts:  ListModel {}
    readonly property int count: history.count

    property var  _live: ({})   // key -> Notification
    property int  _nextKey: 1
    property bool _clearing: false

    // Drives relative timestamps ("5m") in the views.
    property double now: Date.now()
    property Timer _clock: Timer {
        interval: 30000; repeat: true; running: true
        onTriggered: root.now = Date.now()
    }

    // ── Toast expiry ─────────────────────────────────────────────────────────
    // Paused while the toast/center is hovered so a toast can't vanish mid-read.
    property Timer _toastTimer: Timer {
        interval: 250
        repeat:   true
        onTriggered: {
            if (root.bellHovered || root.panelHovered) return
            const now = Date.now()
            for (let i = root.toasts.count - 1; i >= 0; i--) {
                const t = root.toasts.get(i)
                if (t.exp <= 0 || t.exp > now) continue
                const key = t.key, transient = t.transient
                root.toasts.remove(i)
                if (transient) root.dismiss(key)
            }
            if (root.toasts.count === 0) {
                stop()
                if (root.toastMode) root.closeCenter()
            }
        }
    }

    // Hover-away close delay, only active when NOT opened by the bell
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

        // Notifications carried over from before a shell reload are re-announced
        // with lastGeneration set: restore them without a toast.
        onNotification: (notif) => {
            notif.tracked = true
            root._add(notif, true, !notif.lastGeneration)
        }
    }

    // Any carried-over notification already tracked at startup (oldest first →
    // newest on top); _add skips the ones re-announced above.
    Component.onCompleted: {
        const tracked = _server.trackedNotifications.values
        for (let i = 0; i < tracked.length; i++) _add(tracked[i], true, false)
    }

    // Emit a shell-local notification (no D-Bus). Used for internal alerts like
    // battery state; it has no actions and no live object.
    function notifyLocal(appName, summary, body, icon) {
        _add({ appName: appName, summary: summary, body: body, appIcon: icon }, false, true)
    }

    // ── Rows ─────────────────────────────────────────────────────────────────
    function _iconSource(appIcon, desktopEntry, appName) {
        const s = "" + (appIcon ?? "")
        if (s.startsWith("/") || s.indexOf("://") > 0) return s
        if (s !== "") {
            const p = Quickshell.iconPath(s, true)
            if (p !== "") return p
        }
        const app = (desktopEntry ? (AppService.byKey("" + desktopEntry) || AppService.byClass("" + desktopEntry)) : null)
                 || (appName ? AppService.byClass("" + appName) : null)
        return app ? Quickshell.iconPath(app.icon ?? "", true) : ""
    }

    function _row(key, n, live) {
        const acts = []
        const src = n.actions ?? []
        for (let i = 0; i < src.length; i++)
            acts.push({ id: "" + (src[i].identifier ?? ""), text: "" + (src[i].text ?? "") })
        return {
            key:          key,
            appName:      "" + (n.appName ?? ""),
            summary:      "" + (n.summary ?? ""),
            body:         "" + (n.body ?? ""),
            icon:         _iconSource(n.appIcon, n.desktopEntry, n.appName),
            image:        "" + (n.image ?? ""),
            desktopEntry: "" + (n.desktopEntry ?? ""),
            time:         Date.now(),
            critical:     live && n.urgency === NotificationUrgency.Critical,
            transient:    live && !!n.transient,
            live:         live,
            actions:      JSON.stringify(acts)
        }
    }

    function _indexIn(model, key) {
        for (let i = 0; i < model.count; i++)
            if (model.get(i).key === key) return i
        return -1
    }

    function _add(n, live, toast) {
        if (live && Object.values(_live).indexOf(n) >= 0) return
        const key = _nextKey++
        const row = _row(key, n, live)
        if (row.appName === "" && row.summary === "" && row.body === "") {
            if (live) n.dismiss()
            return
        }

        if (live) {
            _live[key] = n
            n.closed.connect(reason => root._onClosed(key, reason))
            // Apps update a notification in place (replaces_id): refresh its row.
            const refresh = () => root._refresh(key)
            n.summaryChanged.connect(refresh)
            n.bodyChanged.connect(refresh)
            n.appIconChanged.connect(refresh)
            n.imageChanged.connect(refresh)
            n.actionsChanged.connect(refresh)
            n.urgencyChanged.connect(refresh)
        }

        history.insert(0, row)
        while (history.count > _maxHistory) dismiss(history.get(history.count - 1).key)

        if (!toast || doNotDisturb) return

        // Already in view when the full center is showing: no toast, not unread.
        const popoutOpen     = PopoutService.currentName === "notif"
        const fullCenterOpen = centerOpen && !toastMode
        if (popoutOpen || fullCenterOpen) return
        unreadCount++

        const ttl = (live && n.expireTimeout > 0) ? Math.max(n.expireTimeout, 2000) : _toastTTL
        const t = Object.assign({}, row, { exp: row.critical ? 0 : Date.now() + ttl })
        toasts.insert(0, t)
        while (toasts.count > _toastMax) toasts.remove(toasts.count - 1)
        toastMode    = true
        centerScreen = null   // show on all screens
        centerOpen   = true
        _toastTimer.restart()
    }

    function _refresh(key) {
        const n = _live[key]
        if (!n) return
        const row = _row(key, n, true)
        const h = _indexIn(history, key)
        if (h >= 0) history.set(h, row)
        const t = _indexIn(toasts, key)
        if (t >= 0) toasts.set(t, Object.assign({}, row, { exp: toasts.get(t).exp }))
    }

    // The app (or the user, via dismiss) closed the notification. User dismissals
    // already removed the row; an app close keeps it, minus its actions.
    function _onClosed(key, reason) {
        delete _live[key]
        if (_clearing) return
        const h = _indexIn(history, key)
        if (h < 0) return
        if (history.get(h).transient) { _removeRow(key); return }
        history.setProperty(h, "live", false)
        if (reason === NotificationCloseReason.CloseRequested) {
            const t = _indexIn(toasts, key)
            if (t >= 0) toasts.remove(t)
        }
    }

    function _removeRow(key) {
        const h = _indexIn(history, key)
        if (h >= 0) history.remove(h)
        const t = _indexIn(toasts, key)
        if (t >= 0) toasts.remove(t)
        if (unreadCount > history.count) unreadCount = history.count
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    function dismiss(key) {
        _removeRow(key)
        const n = _live[key]
        delete _live[key]
        if (n) n.dismiss()
    }

    function dismissAll() {
        // One model reset instead of a row removal per notification; the closed
        // handlers fired by dismiss() below are no-ops while _clearing is set.
        _clearing = true
        const live = Object.values(_live)
        _live = {}
        history.clear()
        toasts.clear()
        unreadCount = 0
        for (const n of live) n.dismiss()
        _clearing = false
    }

    function invokeAction(key, identifier) {
        const n = _live[key]
        if (!n) return
        const acts = n.actions ?? []
        for (let i = 0; i < acts.length; i++)
            if (("" + acts[i].identifier) === identifier) { acts[i].invoke(); break }
        if (!n.resident) dismiss(key)
    }

    function markRead() {
        unreadCount = 0
    }

    // Click a notification → run its default action and bring its app forward:
    //  - window on a special (tray-parked) workspace → reveal that workspace
    //  - window elsewhere → focus it (switches to its workspace)
    //  - no window found → launch the app from its desktop entry
    function activate(key) {
        const h = _indexIn(history, key)
        if (h < 0) return
        const row = history.get(h)
        const n = _live[key]

        // Messaging apps register "default" to jump to the conversation; the
        // window reveal below still runs for tray-parked apps it can't surface.
        if (n) {
            const acts = n.actions ?? []
            for (let a = 0; a < acts.length; a++)
                if (("" + (acts[a].identifier ?? "")) === "default") { acts[a].invoke(); break }
        }

        const cands = []
        if (row.desktopEntry) cands.push(row.desktopEntry.toLowerCase())
        if (row.appName)      cands.push(row.appName.toLowerCase())

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
                // Reveal the special workspace only if it isn't already shown on
                // some monitor: toggle would otherwise hide it.
                let shown = false
                const mons = Hyprland.monitors?.values ?? []
                for (let m = 0; m < mons.length; m++) {
                    const mo = mons[m].lastIpcObject
                    if (mo && mo.specialWorkspace && ("" + (mo.specialWorkspace.name ?? "")) === wsName) { shown = true; break }
                }
                if (!shown)
                    Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + wsName.substring("special:".length) + '")')
            }
            if (addr) Hyprland.dispatch('hl.dsp.focus({window = "address:' + addr + '"})')
        } else {
            let app = null
            if (row.desktopEntry) app = AppService.byKey(row.desktopEntry) || AppService.byClass(row.desktopEntry)
            if (!app && row.appName) app = AppService.byClass(row.appName)
            if (app) AppService.launch(app)
        }

        if (!n || !n.resident) dismiss(key)
        closeCenter()
    }

    // "now", "5m", "3h", then a date.
    function ago(t) {
        const s = Math.max(0, (now - t) / 1000)
        if (s < 60)    return "now"
        if (s < 3600)  return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Qt.formatDate(new Date(t), "d MMM")
    }

    // ── Center visibility ────────────────────────────────────────────────────
    function openCenter(screen) {
        centerScreen = screen
        toastMode    = false
        centerOpen   = true
        unreadCount  = 0
        now          = Date.now()
        _toastTimer.stop()
        _closeTimer.stop()
    }

    function closeCenter() {
        centerOpen   = false
        toastMode    = false
        bellHovered  = false
        panelHovered = false
        toasts.clear()
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
