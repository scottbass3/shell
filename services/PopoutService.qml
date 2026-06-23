pragma Singleton
import QtQuick

// Tracks which bar popout is open and where to anchor it.
// anchorX is the widget's horizontal center in window coordinates.
// Hover on widget OR panel keeps it open; leaving both starts close timer.
QtObject {
    id: root

    property bool   hasCurrent:   false
    property string currentName:  ""
    property real   anchorX:      0
    property var    anchorScreen: null

    property bool widgetHovered: false
    property bool panelHovered:  false

    // Pinned = stay open regardless of hover (click-to-keep, e.g. notifications)
    property bool pinned: false

    // Arbitrary per-popup payload (e.g. QsMenuHandle for tray menus)
    property var menuHandle: null

    // Last known position per panel name — so reopening the same panel after a
    // brief close (cursor gap between widgets) lands at the original position.
    property var _savedX:      ({})
    property var _savedScreen: ({})

    onWidgetHoveredChanged: _evalHover()
    onPanelHoveredChanged:  _evalHover()

    property Timer _closeTimer: Timer {
        interval: 600   // generous — covers slow cursor movement between adjacent widgets
        repeat:   false
        onTriggered: { if (!root.widgetHovered && !root.panelHovered) root.close() }
    }

    function _evalHover() {
        if (!hasCurrent) return
        if (pinned || widgetHovered || panelHovered)
            _closeTimer.stop()
        else
            _closeTimer.restart()
    }

    function open(name, x, screen) {
        // Same panel already open — don't reposition, just cancel close.
        // Exception: traymenu always repositions (different icon = different position).
        if (hasCurrent && currentName === name &&
                anchorScreen?.name === screen?.name) {
            if (name === "traymenu") anchorX = x
            _closeTimer.stop()
            return
        }
        pinned       = false
        hasCurrent   = true
        currentName  = name
        // Reuse saved position if the same panel is reopening (closed during gap traversal)
        const savedKey = name + (screen?.name ?? "")
        anchorX      = (savedKey in _savedX) ? _savedX[savedKey] : x
        anchorScreen = screen
        _closeTimer.stop()
    }

    function close() {
        // Save position before clearing so a quick reopen lands in the same spot
        if (hasCurrent) {
            const key = currentName + (anchorScreen?.name ?? "")
            const sx = Object.assign({}, _savedX);  sx[key] = anchorX;  _savedX = sx
        }
        hasCurrent    = false
        currentName   = ""
        widgetHovered = false
        panelHovered  = false
        pinned        = false
        menuHandle    = null
        _closeTimer.stop()
    }

    // Toggle on click (kept for keyboard / alternative trigger)
    function toggle(name, x, screen) {
        if (hasCurrent && currentName === name &&
                anchorScreen?.name === screen?.name)
            close()
        else
            open(name, x, screen)
    }

    // Click-to-pin: open + keep open ignoring hover. Click again on same → close.
    function togglePin(name, x, screen) {
        if (hasCurrent && currentName === name && pinned &&
                anchorScreen?.name === screen?.name) {
            close()
        } else {
            open(name, x, screen)
            pinned = true
            _closeTimer.stop()
        }
    }
}
