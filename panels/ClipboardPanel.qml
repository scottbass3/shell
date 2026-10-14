import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../theme"
import "../services"

// Clipboard history picker — CONTENT ONLY. MainWindow draws the blob surface,
// animates it and owns keyboard focus, as for the launcher. Data comes from
// ClipboardService (the clipd daemon).
Item {
    id: root

    property bool active: false

    onActiveChanged: {
        if (active) {
            _idx = -1
            _clearArmed = false
            Qt.callLater(() => _search.forceActiveFocus())
        }
    }
    Component.onCompleted: if (active) _search.forceActiveFocus()

    readonly property var _entries: ClipboardService.entries
    readonly property bool _searching: ClipboardService.query.trim() !== ""

    // ── Selection: -1 = search field, else an index in _entries ──────────────
    property int _idx: -1
    on_EntriesChanged: if (_idx >= _entries.length) _idx = _entries.length - 1

    function _move(d) {
        if (_entries.length === 0) return
        _idx = Math.max(-1, Math.min(_entries.length - 1, _idx + d))
        if (_idx >= 0) _list.positionViewAtIndex(_idx, ListView.Contain)
    }
    function _selected() { return _idx >= 0 ? (_entries[_idx] ?? null) : (_entries[0] ?? null) }

    function _copy(e) {
        if (!e) return
        ClipboardService.copy(e.id)
        ClipboardService.hide()
    }
    function _togglePin(e) {
        if (!e) return
        if (e.pin) ClipboardService.unpin(e.id); else ClipboardService.pin(e.id)
    }

    // Clearing the history asks for a second click.
    property bool _clearArmed: false
    Timer { id: _disarm; interval: 3000; onTriggered: root._clearArmed = false }

    function _ago(ms) {
        const s = Math.max(0, (Date.now() - ms) / 1000)
        if (s < 60)    return "now"
        if (s < 3600)  return Math.floor(s / 60) + " min"
        if (s < 86400) return Math.floor(s / 3600) + " h"
        if (s < 86400 * 30) return Math.floor(s / 86400) + " d"
        return new Date(ms).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }
    // Relative times are refreshed while the panel is open.
    property real _now: Date.now()
    Timer { interval: 30000; repeat: true; running: root.active; onTriggered: root._now = Date.now() }

    function _size(n) {
        if (n < 1024) return n + " B"
        if (n < 1024 * 1024) return Math.ceil(n / 1024) + " KiB"
        return (n / 1024 / 1024).toFixed(1) + " MiB"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        anchors.bottomMargin: 22 + ThemeManager.borderWidth
        spacing: 14

        // ── Search + actions ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 22
                color: ThemeManager.surfaceContainerHigh
                border.width: _search.activeFocus && root._idx < 0 ? 2 : 1
                border.color: _search.activeFocus && root._idx < 0 ? ThemeManager.primary : ThemeManager.outlineVariant

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 10
                    Text {
                        text: ""
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 16
                        color: ThemeManager.onSurfaceVariant
                    }
                    TextField {
                        id: _search
                        Layout.fillWidth: true
                        background: null
                        color: ThemeManager.onSurface
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 15
                        placeholderText: "Search the clipboard history…"
                        placeholderTextColor: ThemeManager.onSurfaceVariant
                        verticalAlignment: TextInput.AlignVCenter
                        text: ClipboardService.query
                        onTextChanged: {
                            if (text !== ClipboardService.query) ClipboardService.query = text
                            root._idx = -1
                        }
                        onAccepted: root._copy(root._selected())
                        Keys.onDownPressed: (e) => { root._move(1); e.accepted = true }
                        Keys.onUpPressed:   (e) => { root._move(-1); e.accepted = true }
                        Keys.onPressed: (e) => {
                            if (root._idx < 0) return
                            if (e.key === Qt.Key_Delete) {
                                ClipboardService.remove(root._entries[root._idx].id)
                                e.accepted = true
                            } else if (e.key === Qt.Key_P && (e.modifiers & Qt.ControlModifier)) {
                                root._togglePin(root._entries[root._idx])
                                e.accepted = true
                            }
                        }
                        Keys.onEscapePressed: {
                            if (root._searching) ClipboardService.query = ""
                            else ClipboardService.hide()
                        }
                    }
                }
            }

            IconButton {
                visible: ClipboardService.connected
                icon: ClipboardService.paused ? "󰐊" : "󰏤"
                tip: ClipboardService.paused ? "Resume recording" : "Pause recording"
                highlighted: ClipboardService.paused
                onClicked: ClipboardService.setPaused(!ClipboardService.paused)
            }
            IconButton {
                visible: ClipboardService.connected && root._entries.length > 0
                icon: "󰎟"
                tip: root._clearArmed ? "Click again to clear the history (pins are kept)" : "Clear the history"
                danger: root._clearArmed
                onClicked: {
                    if (root._clearArmed) { ClipboardService.clear(); root._clearArmed = false; _disarm.stop() }
                    else { root._clearArmed = true; _disarm.restart() }
                }
            }
        }

        // ── Paused banner ─────────────────────────────────────────────────────
        Rectangle {
            visible: ClipboardService.connected && ClipboardService.paused
            Layout.fillWidth: true
            implicitHeight: 36
            radius: ThemeManager.chipRadius
            color: Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.12)
            Text {
                anchors.centerIn: parent
                text: ClipboardService.pausedUntil
                    ? "Recording paused until " + new Date(ClipboardService.pausedUntil).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                    : "Recording paused: new copies are not kept"
                color: ThemeManager.primary
                font.family: ThemeManager.fontFamily
                font.pixelSize: ThemeManager.fontSizeSm
            }
        }

        // ── History ───────────────────────────────────────────────────────────
        ListView {
            id: _list
            visible: ClipboardService.connected && root._entries.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root._entries
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool _sel: root._idx === index
                readonly property bool _image: modelData.kind === "image"
                width: ListView.view.width - 8
                height: _image && modelData.thumbnail ? 76 : 52
                radius: ThemeManager.chipRadius + 2
                color: _sel ? ThemeManager.secondaryContainer
                     : (_rowHov.hovered ? ThemeManager.surfaceContainerHigh : "transparent")
                border.width: _sel ? 1 : 0
                border.color: ThemeManager.primary

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 12

                    Image {
                        visible: row._image && !!row.modelData.thumbnail
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 60
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        // Ids can be reused after deletions, and the file with them.
                        cache: false
                        sourceSize.width: 192
                        source: visible ? "file://" + row.modelData.thumbnail : ""
                    }
                    Text {
                        visible: !(row._image && row.modelData.thumbnail)
                        text: row._image ? "󰋩" : "󰅍"
                        color: ThemeManager.onSurfaceVariant
                        font.family: ThemeManager.fontFamily
                        font.pixelSize: 18
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: row._image
                                ? (row.modelData.width ? row.modelData.width + " × " + row.modelData.height : "Image")
                                : row.modelData.preview
                            color: ThemeManager.onSurface
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeMd
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        Text {
                            Layout.fillWidth: true
                            text: {
                                void root._now
                                const parts = [root._ago(row.modelData.last_used_ms)]
                                if (row._image) parts.push(row.modelData.mime.replace("image/", "").toUpperCase())
                                parts.push(root._size(row.modelData.size))
                                if (row.modelData.use_count > 1) parts.push(row.modelData.use_count + "×")
                                return parts.join("  ·  ")
                            }
                            color: ThemeManager.onSurfaceVariant
                            font.family: ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeXs
                            elide: Text.ElideRight
                        }
                    }
                    IconButton {
                        visible: row.modelData.pin || _rowHov.hovered || row._sel
                        small: true
                        icon: "󰐃"
                        tip: row.modelData.pin ? "Unpin (Ctrl+P)" : "Pin (Ctrl+P)"
                        highlighted: !!row.modelData.pin
                        onClicked: root._togglePin(row.modelData)
                    }
                    IconButton {
                        visible: _rowHov.hovered || row._sel
                        small: true
                        icon: "󰆴"
                        tip: "Delete (Del)"
                        onClicked: ClipboardService.remove(row.modelData.id)
                    }
                }
                HoverHandler { id: _rowHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root._copy(row.modelData) }
            }
        }

        // ── Empty states ──────────────────────────────────────────────────────
        Item {
            visible: !_list.visible
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰅍"
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: 40
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: ThemeManager.onSurface
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeMd
                    text: !ClipboardService.connected
                            ? (ClipboardService.installed ? "clipd is not running" : "Install clipd to keep a clipboard history")
                        : !ClipboardService.loaded ? "…"
                        : root._searching ? "Nothing matches this search"
                        : "Copied text and images appear here"
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: ThemeManager.onSurfaceVariant
                    font.family: ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeSm
                    textFormat: Text.PlainText
                    text: ClipboardService.connected ? ""
                        : ClipboardService.installed ? "Start it with: systemctl --user enable --now clipd.service"
                        : "Package: " + DependencyService.pkg("clipd")
                }
            }
        }

        // ── Hints ─────────────────────────────────────────────────────────────
        Text {
            visible: _list.visible
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "Enter copies  ·  Ctrl+P pins  ·  Del deletes  ·  then paste with Ctrl+V"
            color: ThemeManager.onSurfaceVariant
            font.family: ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeXs
        }
    }

    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""
        property bool highlighted: false
        property bool danger: false
        property bool small: false
        signal clicked()
        implicitWidth: small ? 32 : 44
        implicitHeight: small ? 32 : 44
        radius: height / 2
        readonly property color _fg: danger ? ThemeManager.error
                                   : highlighted ? ThemeManager.primary : ThemeManager.onSurfaceVariant
        color: danger ? Qt.rgba(ThemeManager.error.r, ThemeManager.error.g, ThemeManager.error.b, _ibMouse.containsMouse ? 0.22 : 0.14)
             : _ibMouse.containsMouse ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)
             : (small ? "transparent" : ThemeManager.surfaceContainerHigh)
        Text {
            anchors.centerIn: parent
            text: ib.icon
            color: ib._fg
            font.family: ThemeManager.fontFamily
            font.pixelSize: ib.small ? 16 : 18
        }
        // A MouseArea, not a TapHandler: the click must not reach the row below.
        MouseArea {
            id: _ibMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
        ToolTip.visible: _ibMouse.containsMouse && ib.tip !== ""
        ToolTip.text: ib.tip
        ToolTip.delay: 500
    }
}
