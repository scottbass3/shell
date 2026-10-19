pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import "."

// Notification daemon + history. Notifications from the same app with the same
// title are grouped into a stack; `history` holds one row per stack, newest
// stack first, and a stack that receives a notification moves back to the top.
// Rows are inserted, updated, moved and removed one at a time, so views never
// rebuild their delegates on a change. Every notification keeps a stable `key`;
// its live Notification object (needed for actions) stays in `_live` until the
// app or the user closes it, and an app closing it leaves it in the history.
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

    // Stack rows: stackId, size, items (JSON of the stack's notifications, newest
    // first) and the latest notification's fields: key, appName, summary, body,
    // icon, image, desktopEntry, time, critical, transient, live, actions (JSON
    // [{id, text}]). Toast rows are the same plus `exp` (0 = stays until dismissed).
    property ListModel history: ListModel {}
    property ListModel toasts:  ListModel {}
    property int total: 0                // notifications across all stacks

    property var  _items: ({})           // stackId -> [notification], newest first
    property var  _keyStack: ({})        // key -> stackId
    property var  _live: ({})            // key -> Notification
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

    // ── Notifications and stacks ─────────────────────────────────────────────
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

    function _item(key, n, live) {
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

    // Same app + same title. A messaging app usually puts the sender in the
    // title, so each conversation gets its own stack.
    function _stackId(item) { return item.appName + "\u001f" + item.summary }

    function _indexOf(model, stackId) {
        for (let i = 0; i < model.count; i++)
            if (model.get(i).stackId === stackId) return i
        return -1
    }

    function _findItem(key) {
        const sid = _keyStack[key]
        const arr = sid !== undefined ? _items[sid] : null
        if (!arr) return null
        const i = arr.findIndex(x => x.key === key)
        return i < 0 ? null : { sid: sid, arr: arr, i: i, item: arr[i] }
    }

    function _rowFor(sid) {
        const arr = _items[sid]
        return Object.assign({}, arr[0], { stackId: sid, size: arr.length, items: JSON.stringify(arr) })
    }

    // Rewrite a stack's row (and its toast) from `_items`; remove it once empty.
    // `bump` moves it to the top, as for a newly received notification.
    function _syncStack(sid, bump) {
        const arr = _items[sid]
        const h = _indexOf(history, sid)
        const t = _indexOf(toasts, sid)
        if (!arr || arr.length === 0) {
            delete _items[sid]
            if (h >= 0) history.remove(h)
            if (t >= 0) toasts.remove(t)
            return
        }
        const row = _rowFor(sid)
        if (h < 0) history.insert(0, row)
        else {
            history.set(h, row)
            if (bump && h > 0) history.move(h, 0, 1)
        }
        if (t >= 0) toasts.set(t, Object.assign({}, row, { exp: toasts.get(t).exp }))
    }

    function _add(n, live, toast) {
        if (live && Object.values(_live).indexOf(n) >= 0) return
        const key = _nextKey++
        const item = _item(key, n, live)
        if (item.appName === "" && item.summary === "" && item.body === "") {
            if (live) n.dismiss()
            return
        }

        if (live) {
            _live[key] = n
            n.closed.connect(reason => root._onClosed(key, reason))
            // Apps update a notification in place (replaces_id): refresh it.
            const refresh = () => root._refresh(key)
            n.summaryChanged.connect(refresh)
            n.bodyChanged.connect(refresh)
            n.appIconChanged.connect(refresh)
            n.imageChanged.connect(refresh)
            n.actionsChanged.connect(refresh)
            n.urgencyChanged.connect(refresh)
        }

        const sid = _stackId(item)
        if (!_items[sid]) _items[sid] = []
        _items[sid].unshift(item)
        _keyStack[key] = sid
        total++
        _syncStack(sid, true)
        _trim()

        if (!toast || doNotDisturb) return

        // Already in view when the full center is showing: no toast, not unread.
        const popoutOpen     = PopoutService.currentName === "notif"
        const fullCenterOpen = centerOpen && !toastMode
        if (popoutOpen || fullCenterOpen) return
        unreadCount++

        // One toast per stack: a new notification refreshes it and moves it up.
        const ttl = (live && n.expireTimeout > 0) ? Math.max(n.expireTimeout, 2000) : _toastTTL
        const trow = Object.assign(_rowFor(sid), { exp: item.critical ? 0 : Date.now() + ttl })
        const t = _indexOf(toasts, sid)
        if (t >= 0) {
            toasts.set(t, trow)
            if (t > 0) toasts.move(t, 0, 1)
        } else {
            toasts.insert(0, trow)
        }
        while (toasts.count > _toastMax) toasts.remove(toasts.count - 1)
        toastMode    = true
        centerScreen = null   // show on all screens
        centerOpen   = true
        _toastTimer.restart()
    }

    // Drop the oldest notifications beyond the history size.
    function _trim() {
        while (total > _maxHistory) {
            let oldest = null
            for (const sid in _items) {
                const arr = _items[sid]
                const last = arr[arr.length - 1]
                if (!oldest || last.time < oldest.time) oldest = last
            }
            if (!oldest) break
            dismiss(oldest.key)
        }
    }

    // An app updated a notification: it counts as new, so it moves to the top of
    // its stack, or to another stack if its title changed.
    function _refresh(key) {
        const n = _live[key]
        const f = _findItem(key)
        if (!n || !f) return
        const item = _item(key, n, true)
        f.arr.splice(f.i, 1)
        const sid = _stackId(item)
        if (sid !== f.sid) {
            _syncStack(f.sid, false)
            if (!_items[sid]) _items[sid] = []
            _keyStack[key] = sid
        }
        _items[sid].unshift(item)
        _syncStack(sid, true)
    }

    // The app (or the user, via dismiss) closed the notification. User dismissals
    // already removed it; an app close keeps it, minus its actions.
    function _onClosed(key, reason) {
        delete _live[key]
        if (_clearing) return
        const f = _findItem(key)
        if (!f) return
        if (f.item.transient) { _removeItem(key); return }
        f.item.live = false
        _syncStack(f.sid, false)
        if (reason === NotificationCloseReason.CloseRequested && f.i === 0) {
            const t = _indexOf(toasts, f.sid)
            if (t >= 0) toasts.remove(t)
        }
    }

    function _removeItem(key) {
        const f = _findItem(key)
        if (!f) return
        f.arr.splice(f.i, 1)
        delete _keyStack[key]
        total--
        _syncStack(f.sid, false)
        if (unreadCount > total) unreadCount = total
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    function dismiss(key) {
        _removeItem(key)
        const n = _live[key]
        delete _live[key]
        if (n) n.dismiss()
    }

    function dismissStack(stackId) {
        for (const it of (_items[stackId] ?? []).slice()) dismiss(it.key)
    }

    function dismissAll() {
        // One model reset instead of a row removal per notification; the closed
        // handlers fired by dismiss() below are no-ops while _clearing is set.
        _clearing = true
        const live = Object.values(_live)
        _live = {}
        _items = {}
        _keyStack = {}
        total = 0
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

    // Run a notification's default action and bring its app forward:
    //  - window on a special (tray-parked) workspace → reveal that workspace
    //  - window elsewhere → focus it (switches to its workspace)
    //  - no window found → launch the app from its desktop entry
    // Windows and monitors are read fresh from hyprctl: Quickshell's
    // lastIpcObject is only filled by an explicit refresh, so it is empty or
    // stale here.
    function _bringForward(item) {
        const n = _live[item.key]

        // Messaging apps register "default" to jump to the conversation; the
        // window reveal below still runs for tray-parked apps it can't surface.
        if (n) {
            const acts = n.actions ?? []
            for (let a = 0; a < acts.length; a++)
                if (("" + (acts[a].identifier ?? "")) === "default") { acts[a].invoke(); break }
        }

        _forwardItem = { desktopEntry: item.desktopEntry, appName: item.appName }
        _forwardProbe.running = false
        _forwardProbe.running = true
    }

    property var _forwardItem: null
    property Process _forwardProbe: Process {
        command: ["sh", "-c", 'printf \'{"clients":%s,"monitors":%s}\' "$(hyprctl -j clients)" "$(hyprctl -j monitors)"']
        stdout: StdioCollector { onStreamFinished: root._forwardWith(text) }
    }

    function _forwardWith(text) {
        const item = _forwardItem
        _forwardItem = null
        if (!item) return
        let clients = [], monitors = []
        try {
            const d = JSON.parse(text)
            clients = d.clients ?? []
            monitors = d.monitors ?? []
        } catch (e) {}

        const cands = []
        if (item.desktopEntry) cands.push(item.desktopEntry.toLowerCase())
        if (item.appName)      cands.push(item.appName.toLowerCase())

        let match = null
        for (let i = 0; i < clients.length && !match; i++) {
            const c = ("" + (clients[i]["class"] ?? "")).toLowerCase()
            if (!c) continue
            for (let j = 0; j < cands.length; j++) {
                const k = cands[j]
                if (c === k || c.indexOf(k) >= 0 || k.indexOf(c) >= 0) { match = clients[i]; break }
            }
        }

        if (match) {
            const addr = match.address
            const wsName = match.workspace ? ("" + (match.workspace.name ?? "")) : ""
            if (wsName.indexOf("special:") === 0) {
                // Reveal the special workspace only if it isn't already shown on
                // some monitor: toggle would otherwise hide it.
                const shown = monitors.some(m => m.specialWorkspace && ("" + (m.specialWorkspace.name ?? "")) === wsName)
                if (!shown)
                    Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + wsName.substring("special:".length) + '")')
            }
            if (addr) Hyprland.dispatch('hl.dsp.focus({window = "address:' + addr + '"})')
        } else {
            let app = null
            if (item.desktopEntry) app = AppService.byKey(item.desktopEntry) || AppService.byClass(item.desktopEntry)
            if (!app && item.appName) app = AppService.byClass(item.appName)
            if (app) AppService.launch(app)
        }
    }

    function _dismissUnlessResident(key) {
        const n = _live[key]
        if (!n || !n.resident) dismiss(key)
    }

    // Click one notification (inside an expanded stack).
    function activate(key) {
        const f = _findItem(key)
        if (!f) return
        _bringForward(f.item)
        _dismissUnlessResident(key)
        closeCenter()
    }

    // Click a stack: open its latest notification; the whole stack is handled.
    function activateStack(stackId) {
        const arr = _items[stackId]
        if (!arr || arr.length === 0) return
        _bringForward(arr[0])
        for (const it of arr.slice()) _dismissUnlessResident(it.key)
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
