import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../theme"
import "../services"

// Pure content component: no window, no background.
// MainWindow owns the BlobRect background, position, and open/close animation.
Item {
    id: root

    property bool toastMode: false

    readonly property ListModel _model: toastMode ? NotificationService.toasts : NotificationService.history
    readonly property int _count: _model.count

    readonly property int _pad:     ThemeManager.spacing
    readonly property int _headerH: 28
    readonly property int _emptyH:  48

    implicitWidth:  320
    // Natural size. MainWindow caps it; when capped, the list scrolls.
    implicitHeight: root.toastMode
        ? _pad + _list.contentHeight + _pad
        : _pad + _headerH + _pad + (_count > 0 ? _list.contentHeight : _emptyH) + _pad

    // ── Header (hidden in toast mode) ────────────────────────────────────────
    RowLayout {
        id: _header
        visible: !root.toastMode
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            topMargin: root._pad; leftMargin: root._pad; rightMargin: root._pad
        }
        height:  root._headerH
        spacing: ThemeManager.spacing

        Text {
            text:           "Notifications"
            color:          ThemeManager.onSurface
            font.family:    ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
            font.weight:    Font.Medium
        }
        Text {
            visible:        NotificationService.total > 0
            text:           NotificationService.total
            color:          ThemeManager.onSurfaceVariant
            font.family:    ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
        }

        Item { Layout.fillWidth: true }

        HeaderButton {
            text:    NotificationService.doNotDisturb ? "󰂛" : "󰂚"
            active:  NotificationService.doNotDisturb
            onClicked: NotificationService.doNotDisturb = !NotificationService.doNotDisturb
        }
        HeaderButton {
            visible: root._count > 0
            text:    "Clear all"
            onClicked: NotificationService.dismissAll()
        }
    }

    Text {
        visible: !root.toastMode && root._count === 0
        anchors { top: _header.bottom; topMargin: root._pad; horizontalCenter: parent.horizontalCenter }
        height:            root._emptyH
        verticalAlignment: Text.AlignVCenter
        text:           NotificationService.doNotDisturb ? "Do not disturb is on" : "No notifications"
        color:          ThemeManager.onSurfaceVariant
        font.family:    ThemeManager.fontFamily
        font.pixelSize: ThemeManager.fontSizeSm
        opacity:        0.6
    }

    // ── List ─────────────────────────────────────────────────────────────────
    // ListView only instantiates the visible cards, so a long history stays cheap.
    ListView {
        id: _list
        anchors {
            top:    root.toastMode ? parent.top : _header.bottom
            left:   parent.left
            right:  parent.right
            bottom: parent.bottom
            topMargin:    root._pad
            leftMargin:   root._pad
            rightMargin:  root._pad
            bottomMargin: root._pad
        }
        clip:           true
        model:          root._model
        spacing:        ThemeManager.spacing
        boundsBehavior: Flickable.StopAtBounds
        interactive:    contentHeight > height

        ScrollBar.vertical: ScrollBar {
            policy: _list.contentHeight > _list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width:  4
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
        }
        // Also restores opacity: a card displaced mid-fade-in would otherwise
        // stay half transparent.
        displaced: Transition {
            NumberAnimation { property: "y"; duration: 150; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; to: 1; duration: 150 }
        }

        delegate: Card { width: ListView.view.width; toast: root.toastMode }
    }

    // ── Components ───────────────────────────────────────────────────────────
    component HeaderButton: Item {
        id: hb
        property string text: ""
        property bool active: false
        signal clicked()
        implicitWidth:  _hbText.implicitWidth + 14
        implicitHeight: 22
        Rectangle {
            anchors.fill: parent
            radius: ThemeManager.chipRadius
            color:  hb.active ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.2)
                  : _hbMa.containsMouse ? Qt.lighter(ThemeManager.surfaceContainerHigh, 1.25)
                  : ThemeManager.surfaceContainerHigh
        }
        Text {
            id: _hbText
            anchors.centerIn: parent
            text:           hb.text
            color:          hb.active ? ThemeManager.primary : ThemeManager.onSurfaceVariant
            font.family:    ThemeManager.fontFamily
            font.pixelSize: ThemeManager.fontSizeSm
        }
        MouseArea {
            id: _hbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked:    hb.clicked()
        }
    }

    component IconBtn: Item {
        id: ib
        property string glyph: ""
        property int    glyphSize: 10
        signal clicked()
        width: 18; height: 18
        Rectangle {
            anchors.fill: parent
            radius: 9
            color: _ibMa.containsMouse
                ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.12)
                : "transparent"
        }
        Text {
            anchors.centerIn: parent
            text:           ib.glyph
            color:          ThemeManager.onSurfaceVariant
            font.family:    ThemeManager.fontFamily
            font.pixelSize: ib.glyphSize
        }
        MouseArea {
            id: _ibMa
            anchors.fill:    parent
            anchors.margins: -4
            hoverEnabled:    true
            cursorShape:     Qt.PointingHandCursor
            onClicked:       ib.clicked()
        }
    }

    component ActionChips: Flow {
        id: ac
        property int key: 0
        property string actions: "[]"
        property bool live: false
        // "default" is what a click on the notification runs; the rest are buttons.
        readonly property var _list: {
            if (!live) return []
            try { return JSON.parse(actions).filter(a => a.id !== "default" && a.text !== "") }
            catch (e) { return [] }
        }
        visible: _list.length > 0
        spacing: 6
        Repeater {
            model: ac._list
            delegate: Rectangle {
                required property var modelData
                width:  _actText.implicitWidth + 16
                height: 24
                radius: ThemeManager.chipRadius
                color:  _actMa.containsMouse
                    ? Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.25)
                    : Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.12)
                Text {
                    id: _actText
                    anchors.centerIn: parent
                    text:           modelData.text
                    color:          ThemeManager.primary
                    font.family:    ThemeManager.fontFamily
                    font.pixelSize: ThemeManager.fontSizeSm
                }
                MouseArea {
                    id: _actMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    NotificationService.invokeAction(ac.key, modelData.id)
                }
            }
        }
    }

    // One stack: the latest notification, with the edges of the older ones
    // peeking out below. Expanded, it lists every notification of the stack.
    component Card: Item {
        id: card
        required property string stackId
        required property int    size
        required property string items
        required property int    key
        required property string appName
        required property string summary
        required property string body
        required property string icon
        required property string image
        required property double time
        required property bool   critical
        required property bool   live
        required property string actions
        property bool toast: false
        property bool expanded: false

        readonly property bool _stacked: size > 1
        // Only the full center expands; hovering a toast opens the center instead.
        readonly property bool _open: expanded && _stacked && !toast
        onSizeChanged: if (size <= 1) expanded = false
        readonly property var _members: {
            if (!_open) return []
            try { return JSON.parse(items) } catch (e) { return [] }
        }
        readonly property int  _depth: (_stacked && !_open) ? Math.min(size - 1, 2) : 0
        readonly property bool _clickOpens: SettingsService.get("notifications.clickOpensApp", true)
        readonly property bool _hasImage: image !== "" && image !== icon

        height: _face.height + _depth * 4

        // Older notifications of the stack, deepest drawn first.
        Repeater {
            model: card._depth
            delegate: Rectangle {
                required property int index
                readonly property int level: card._depth - index
                x: level * 6
                y: level * 4
                width:  card.width - level * 12
                height: _face.height
                radius: ThemeManager.chipRadius
                color:  ThemeManager.surfaceContainerHigh
                opacity: level === 1 ? 0.7 : 0.4
            }
        }

        Rectangle {
            id: _face
            width:  parent.width
            height: _content.height + ThemeManager.spacing * 2
            radius: ThemeManager.chipRadius
            color:  _cardMa.containsMouse ? Qt.lighter(ThemeManager.surfaceContainerHigh, 1.25)
                                          : ThemeManager.surfaceContainerHigh
            border.width: card.critical ? 1 : 0
            border.color: ThemeManager.error

            MouseArea {
                id: _cardMa
                anchors.fill: parent
                enabled:      card._clickOpens
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked:    NotificationService.activateStack(card.stackId)
            }

            Column {
                id: _content
                x: ThemeManager.spacing
                y: ThemeManager.spacing
                width:   parent.width - ThemeManager.spacing * 2
                spacing: 4

                // App row: icon · app name · count · time · expand · dismiss stack
                RowLayout {
                    width:   parent.width
                    height:  18
                    spacing: 6

                    Item {
                        implicitWidth: 14; implicitHeight: 14
                        IconImage {
                            id: _appImg
                            anchors.fill: parent
                            implicitSize: 14
                            source:  card.icon
                            visible: card.icon !== "" && status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible:        !_appImg.visible
                            text:           "󰭹"
                            color:          ThemeManager.primary
                            font.family:    ThemeManager.fontFamily
                            font.pixelSize: 12
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text:           card.appName
                        color:          ThemeManager.onSurfaceVariant
                        font.family:    ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeSm
                        elide:          Text.ElideRight
                    }
                    Rectangle {
                        visible: card._stacked
                        implicitWidth:  Math.max(18, _countText.implicitWidth + 10)
                        implicitHeight: 16
                        radius: 8
                        color:  Qt.rgba(ThemeManager.primary.r, ThemeManager.primary.g, ThemeManager.primary.b, 0.2)
                        Text {
                            id: _countText
                            anchors.centerIn: parent
                            text:           card.size
                            color:          ThemeManager.primary
                            font.family:    ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeXs
                            font.weight:    Font.Medium
                        }
                    }
                    Text {
                        text:           NotificationService.ago(card.time)
                        color:          ThemeManager.onSurfaceVariant
                        font.family:    ThemeManager.fontFamily
                        font.pixelSize: ThemeManager.fontSizeXs
                        opacity:        0.7
                    }
                    IconBtn {
                        visible:   card._stacked && !card.toast
                        glyph:     card._open ? "󰅃" : "󰅀"
                        glyphSize: 14
                        onClicked: card.expanded = !card.expanded
                    }
                    IconBtn {
                        glyph: "✕"
                        onClicked: NotificationService.dismissStack(card.stackId)
                    }
                }

                // Title (shared by the whole stack) + latest body, image on the right
                Item {
                    width:  parent.width
                    height: Math.max(_texts.height, _img.visible ? _img.height : 0)

                    Column {
                        id: _texts
                        width: parent.width - (_img.visible ? _img.width + 8 : 0)
                        spacing: 2
                        Text {
                            visible:        card.summary.length > 0
                            width:          parent.width
                            text:           card.summary
                            textFormat:     Text.PlainText
                            color:          ThemeManager.onSurface
                            font.family:    ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm
                            font.weight:    Font.Medium
                            wrapMode:       Text.Wrap
                            maximumLineCount: 2
                            elide:          Text.ElideRight
                        }
                        Text {
                            visible:        !card._open && card.body.length > 0
                            width:          parent.width
                            text:           card.body
                            textFormat:     Text.PlainText
                            color:          ThemeManager.onSurfaceVariant
                            font.family:    ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm
                            wrapMode:       Text.Wrap
                            // Toast: 3 lines. Full center: long enough for real messages.
                            maximumLineCount: card.toast ? 3 : 12
                            elide:          Text.ElideRight
                        }
                    }
                    Image {
                        id: _img
                        anchors.right: parent.right
                        width: 44; height: 44
                        source:       card._hasImage ? card.image : ""
                        visible:      card._hasImage && status === Image.Ready
                        fillMode:     Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize:   Qt.size(88, 88)
                    }
                }

                ActionChips {
                    visible: !card._open && _list.length > 0
                    width:   parent.width
                    key:     card.key
                    actions: card.actions
                    live:    card.live
                }

                // Expanded: every notification of the stack, each dismissable.
                Repeater {
                    model: card._members
                    delegate: Rectangle {
                        id: _member
                        required property var modelData
                        width:  _content.width
                        height: _memberCol.height + 12
                        radius: ThemeManager.chipRadius
                        color:  _memberMa.containsMouse
                            ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.08)
                            : Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g, ThemeManager.onSurface.b, 0.04)

                        MouseArea {
                            id: _memberMa
                            anchors.fill: parent
                            enabled:      card._clickOpens
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    NotificationService.activate(_member.modelData.key)
                        }

                        Column {
                            id: _memberCol
                            x: 8; y: 6
                            width: parent.width - 16
                            spacing: 4
                            RowLayout {
                                width: parent.width
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text:           _member.modelData.body !== "" ? _member.modelData.body : _member.modelData.summary
                                    textFormat:     Text.PlainText
                                    color:          ThemeManager.onSurfaceVariant
                                    font.family:    ThemeManager.fontFamily
                                    font.pixelSize: ThemeManager.fontSizeSm
                                    wrapMode:       Text.Wrap
                                    maximumLineCount: 6
                                    elide:          Text.ElideRight
                                }
                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    text:           NotificationService.ago(_member.modelData.time)
                                    color:          ThemeManager.onSurfaceVariant
                                    font.family:    ThemeManager.fontFamily
                                    font.pixelSize: ThemeManager.fontSizeXs
                                    opacity:        0.7
                                }
                                IconBtn {
                                    Layout.alignment: Qt.AlignTop
                                    glyph: "✕"
                                    onClicked: NotificationService.dismiss(_member.modelData.key)
                                }
                            }
                            ActionChips {
                                width:   parent.width
                                key:     _member.modelData.key
                                actions: _member.modelData.actions
                                live:    _member.modelData.live
                            }
                        }
                    }
                }
            }
        }
    }
}
