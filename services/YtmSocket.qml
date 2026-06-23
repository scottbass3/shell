import QtQuick
import QtWebSockets

// Thin socket.io/engine.io transport wrapper. Isolated in its own file so the
// `QtWebSockets` import (the qt6-websockets module) is only resolved when this
// is loaded — letting YtmCompanionService treat it as an optional dependency
// and fall back to MPRIS when the module isn't installed.
Item {
    id: root

    property string url:      ""
    property bool   wsActive: false

    signal messageReceived(string msg)
    signal disconnected()

    function send(m) { _ws.sendTextMessage(m) }

    WebSocket {
        id: _ws
        url:    root.url
        active: root.wsActive
        onTextMessageReceived: msg => root.messageReceived(msg)
        onStatusChanged: st => {
            if (st === WebSocket.Closed || st === WebSocket.Error) root.disconnected()
        }
    }
}
