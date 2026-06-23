pragma Singleton
import QtQuick
import Quickshell.Io
import "."

// CalDAV-backed calendar via khal (synced by vdirsyncer) — both optional.
// Loads the visible month's events, exposes per-date lookup + dots, and
// creates events (khal new → vdirsyncer sync → reload). When khal is absent the
// whole events feature is disabled (the month grid still works as a date view);
// without vdirsyncer, events still load but aren't synced/created.
QtObject {
    id: root

    // Feature gate — events need khal; creating/syncing also needs vdirsyncer.
    readonly property bool available:    DependencyService.available("khal")
    readonly property bool _canSync:     DependencyService.available("vdirsyncer")
    readonly property bool canCreate:    available && _canSync

    // { "YYYY-MM-DD": [ {title,sdate,stime,edate,etime,location,calendar,uid,description} ] }
    property var  eventsByDate: ({})
    property bool busy:    false
    property var  _lastView: new Date()

    readonly property string _fmt: "{title}\x1f{start-date}\x1f{start-time}\x1f{end-date}\x1f{end-time}\x1f{location}\x1f{calendar}\x1f{uid}\x1f{description}\x1e"

    function _ymd(d) { return Qt.formatDate(d, "yyyy-MM-dd") }

    function loadMonth(viewDate) {
        _lastView = viewDate
        if (!available) { root.eventsByDate = ({}); return }
        // Grid range: Monday on/before the 1st, 42 days (6 weeks)
        const first  = new Date(viewDate.getFullYear(), viewDate.getMonth(), 1)
        const offset = (first.getDay() + 6) % 7
        const start  = new Date(first.getFullYear(), first.getMonth(), 1 - offset)
        const end    = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 41)
        _list.command = ["khal", "list", "--day-format", "", "--format", _fmt,
                         _ymd(start), _ymd(end)]
        _list.running = true
    }

    function eventsOn(dateStr) { return eventsByDate[dateStr] || [] }
    function hasEvents(dateStr) { const e = eventsByDate[dateStr]; return !!e && e.length > 0 }

    function createEvent(dateStr, startTime, endTime, summary, location) {
        if (busy || !summary || !canCreate) return
        busy = true
        const args = ["khal", "new", "-a", "personal"]
        if (location && location !== "") { args.push("-l"); args.push(location) }
        args.push(dateStr)
        if (startTime && startTime !== "") args.push(startTime)
        if (endTime && endTime !== "")     args.push(endTime)
        args.push(summary)
        _new.command = args
        _new.running = true
    }

    property Process _list: Process {
        stdout: StdioCollector { onStreamFinished: root._parse(text) }
    }

    function _parse(out) {
        const map = {}
        for (const rec of out.split("\x1e")) {
            const t = rec.replace(/^\n+/, "")
            if (!t.trim()) continue
            const f = t.split("\x1f")
            if (f.length < 8) continue
            const ev = {
                title:    f[0],          sdate: f[1], stime: f[2],
                edate:    f[3],          etime: f[4], location: f[5],
                calendar: f[6],          uid:   f[7], description: (f[8] || "").trim()
            }
            if (!map[ev.sdate]) map[ev.sdate] = []
            map[ev.sdate].push(ev)
        }
        for (const k in map)
            map[k].sort((a, b) => a.stime.localeCompare(b.stime))
        root.eventsByDate = map
    }

    // khal new → push via vdirsyncer → reload
    property Process _new: Process {
        onExited: (code, status) => root._sync.running = true
    }
    property Process _sync: Process {
        command: ["vdirsyncer", "sync"]
        onExited: (code, status) => { root.busy = false; root.loadMonth(root._lastView) }
    }
}
