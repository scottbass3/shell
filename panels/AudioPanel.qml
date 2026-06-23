import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

Item {
    id: root

    property int currentPage: 0

    // Fixed page height so caelestia-style y-offset slide works cleanly
    readonly property int _pageH:   200
    readonly property int _headerH: 28

    implicitWidth:  210
    implicitHeight: ThemeManager.spacingLg
                  + _headerH
                  + ThemeManager.spacing
                  + _pageH
                  + ThemeManager.spacingLg

    // ── Tab header ────────────────────────────────────────────────────────────
    RowLayout {
        id: _header
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            topMargin: ThemeManager.spacingLg
            leftMargin: ThemeManager.spacingLg; rightMargin: ThemeManager.spacingLg
        }
        spacing: 0

        Repeater {
            model: [
                { icon: "󰓃", tip: "Volume"  },
                { icon: "󰒓", tip: "Devices" }
            ]
            delegate: Item {
                required property var  modelData
                required property int  index
                Layout.fillWidth: true
                height: _headerH

                readonly property bool active: root.currentPage === index

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 24; radius: 12
                    color: parent.active
                          ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g,
                                    ThemeManager.primary.b, 0.15)
                          : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Text {
                    anchors.centerIn: parent
                    text:           modelData.icon
                    font.family:    ThemeManager.fontFamily
                    font.pixelSize: 15
                    color:          parent.active ? ThemeManager.primary : ThemeManager.onSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    root.currentPage = index
                }
            }
        }
    }

    // ── Paged content — caelestia-style clip + y-shift ─────────────────────
    Item {
        id: _pager
        anchors {
            top: _header.bottom; topMargin: ThemeManager.spacing
            left: parent.left;   right: parent.right
        }
        height: root._pageH
        clip:   true

        ColumnLayout {
            id: _stack
            spacing: 0
            width: parent.width
            y: -root.currentPage * root._pageH

            Behavior on y {
                NumberAnimation {
                    duration:           400
                    easing.type:        Easing.Bezier
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]  // M3 emphasizedDecel
                }
            }

            // ── Page 0 : Volume sliders ───────────────────────────────────────
            Item {
                implicitWidth:  _stack.width
                implicitHeight: root._pageH

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin:  ThemeManager.spacingLg
                        rightMargin: ThemeManager.spacingLg
                    }
                    spacing: ThemeManager.spacingLg

                    VolumeSlider {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        icon: {
                            const v = AudioService.sinkVolPct
                            if (AudioService.sinkMuted || v === 0) return "󰝟"
                            if (v < 33) return "󰕿"
                            if (v < 66) return "󰖀"
                            return "󰕾"
                        }
                        muted:     AudioService.sinkMuted
                        volume:    AudioService.sinkVolume
                        maxVolume: 1.5
                        onToggleMute: AudioService.toggleSinkMute()
                        onSetVolume:  (v) => AudioService.setSinkVolume(v)
                    }

                    Rectangle {
                        width: 1; Layout.fillHeight: true
                        color: ThemeManager.outlineVariant; opacity: 0.4
                    }

                    VolumeSlider {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        icon:      AudioService.sourceMuted ? "󰍭" : "󰍬"
                        muted:     AudioService.sourceMuted
                        volume:    AudioService.sourceVolume
                        maxVolume: 1.0
                        onToggleMute: AudioService.toggleSourceMute()
                        onSetVolume:  (v) => AudioService.setSourceVolume(v)
                    }
                }
            }

            // ── Page 1 : Devices ──────────────────────────────────────────────
            Item {
                implicitWidth:  _stack.width
                implicitHeight: root._pageH

                ColumnLayout {
                    anchors {
                        top: parent.top; left: parent.left; right: parent.right
                        margins: ThemeManager.spacingLg
                    }
                    spacing: ThemeManager.spacing

                    // Output section
                    DeviceSection {
                        Layout.fillWidth: true
                        label:   "Output"
                        nodes:   AudioService.sinks
                        current: AudioService.sink
                        isSink:  true
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 1
                        color: ThemeManager.outlineVariant; opacity: 0.4
                    }

                    // Input section
                    DeviceSection {
                        Layout.fillWidth: true
                        label:   "Input"
                        nodes:   AudioService.sources
                        current: AudioService.source
                        isSink:  false
                    }
                }
            }
        }
    }

    // ── Device section component ──────────────────────────────────────────────
    component DeviceSection: ColumnLayout {
        id: ds
        property string label:   ""
        property var    nodes:   []
        property var    current: null
        property bool   isSink:  true

        spacing: 4

        Text {
            text:           ds.label
            color:          ThemeManager.onSurfaceVariant
            font.family:    ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            font.weight:    Font.Medium
        }

        Repeater {
            model: ds.nodes
            delegate: MouseArea {
                id: _devRow
                required property var modelData
                readonly property bool isDefault: ds.current?.id === modelData.id

                Layout.fillWidth: true
                implicitHeight:   28

                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked:    ds.isSink ? AudioService.setDefaultSink(modelData)
                                        : AudioService.setDefaultSource(modelData)

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: _devRow.isDefault
                          ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g,
                                    ThemeManager.primary.b, _devRow.containsMouse ? 0.20 : 0.12)
                          : (_devRow.containsMouse
                             ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g,
                                       ThemeManager.onSurface.b, 0.08)
                             : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        spacing: 6

                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: _devRow.isDefault ? ThemeManager.primary : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Text {
                            Layout.fillWidth: true
                            text:           _devRow.modelData.description || _devRow.modelData.name || "Unknown"
                            color:          _devRow.isDefault ? ThemeManager.primary : ThemeManager.onSurface
                            font.family:    ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm
                            elide:          Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                }
            }
        }
    }

    // ── M3 vertical volume slider ─────────────────────────────────────────────
    component VolumeSlider: Item {
        id: vs

        property string icon:      ""
        property bool   muted:     false
        property real   volume:    0
        property real   maxVolume: 1.0

        signal toggleMute()
        signal setVolume(real v)

        readonly property int  volPct: Math.round(volume * 100)
        readonly property real frac:   Math.min(volume / maxVolume, 1.0)

        readonly property color _active:   muted ? ThemeManager.error   : ThemeManager.primary
        readonly property color _inactive: ThemeManager.surfaceContainerHigh

        readonly property int _trackW: 6
        readonly property int _thumbR: 10
        readonly property int _trackH: 130

        implicitWidth:  _thumbR * 2
        implicitHeight: _col.implicitHeight

        ColumnLayout {
            id: _col
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: ThemeManager.spacing

            Text {
                Layout.alignment:  Qt.AlignHCenter
                text:             vs.muted ? "M" : vs.volPct + "%"
                color:            vs.muted ? ThemeManager.error : ThemeManager.onSurface
                font.family:      ThemeManager.fontFamily
                font.pixelSize:   ThemeManager.fontSizeSm
                font.weight:      Font.Medium
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Item {
                id: _body
                Layout.alignment:  Qt.AlignHCenter
                implicitWidth:  vs._thumbR * 4
                implicitHeight: vs._trackH + vs._thumbR * 2

                readonly property real thumbCY: vs._thumbR + (1.0 - vs.frac) * (vs._trackH - vs._thumbR * 2)

                Rectangle {
                    id: _track
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: vs._thumbR; width: vs._trackW; height: vs._trackH
                    radius: vs._trackW / 2
                    color:  vs._inactive
                    clip:   true
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: vs.frac * vs._trackH
                        color:  vs._active
                        Behavior on color  { ColorAnimation  { duration: 120 } }
                        Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y:      _body.thumbCY - vs._thumbR
                    width:  vs._thumbR * 2; height: vs._thumbR * 2
                    radius: vs._thumbR
                    color:  vs._active
                    Behavior on y     { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                    Behavior on color { ColorAnimation  { duration: 120 } }

                    Rectangle {
                        anchors { fill: parent; margins: -vs._thumbR * 0.8 }
                        radius: vs._thumbR * 1.8
                        color:  Qt.rgba(vs._active.r, vs._active.g, vs._active.b,
                                        _hoverMa.containsMouse ? 0.12 : 0)
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                    MouseArea {
                        id: _hoverMa
                        anchors { fill: parent; margins: -vs._thumbR * 0.8 }
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.NoButton
                    }
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    function applyY(y) {
                        const cy   = Math.max(vs._thumbR, Math.min(vs._thumbR + vs._trackH, y))
                        const frac = 1.0 - (cy - vs._thumbR) / vs._trackH
                        vs.setVolume(Math.max(0, Math.min(vs.maxVolume, frac * vs.maxVolume)))
                    }
                    onPressed:         (ev) => applyY(ev.y)
                    onPositionChanged: (ev) => { if (pressed) applyY(ev.y) }
                }
            }

            Text {
                Layout.alignment:  Qt.AlignHCenter
                text:             vs.icon; font.family: ThemeManager.fontFamily; font.pixelSize: 16
                color:            vs.muted ? ThemeManager.error : ThemeManager.primary
                Behavior on color { ColorAnimation { duration: 120 } }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    cursorShape:  Qt.PointingHandCursor; onClicked: vs.toggleMute()
                }
            }
        }
    }
}
