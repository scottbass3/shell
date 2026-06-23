import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../theme"
import "../services"

// Pure content component — no window, no background.
// MainWindow owns the BlobRect background, position, and open/close animation.
Item {
    id: root

    property bool toastMode: false

    // notifCount drives reactivity — trackedNotifications list doesn't always notify
    readonly property int _notifCount: NotificationService.notifCount

    readonly property int _pad:     ThemeManager.spacing
    readonly property int _headerH: 36

    implicitWidth:  320
    // Natural size — MainWindow caps it; when capped, the Flickable scrolls.
    implicitHeight: root.toastMode
        ? _pad + _flick.contentHeight + _pad
        : _pad + _headerH + _pad + _flick.contentHeight + _pad

    // ── Compact header (hidden in toast mode) ────────────────────────────────
    RowLayout {
        id: _header
        visible: !root.toastMode
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            topMargin: root._pad; leftMargin: root._pad; rightMargin: root._pad
        }
        height:  root._headerH
        spacing: ThemeManager.spacing

        Item {
            visible:        root._notifCount > 0
            implicitWidth:  _clearText.implicitWidth + 12
            implicitHeight: 22
            Rectangle {
                anchors.fill: parent
                radius: ThemeManager.chipRadius
                color:  ThemeManager.surfaceContainerHigh
            }
            Text {
                id: _clearText
                text:             "Clear all"
                color:            ThemeManager.onSurfaceVariant
                font.family:      ThemeManager.fontFamily
                font.pixelSize:   ThemeManager.fontSizeSm
                anchors.centerIn: parent
            }
            MouseArea {
                anchors.fill: parent
                cursorShape:  Qt.PointingHandCursor
                onClicked:    NotificationService.dismissAll()
            }
        }

        Item { Layout.fillWidth: true }
    }

    // ── Scrollable notification area ─────────────────────────────────────────
    Flickable {
        id: _flick
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
        contentWidth:   width
        contentHeight:  _col.height
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: _flick.contentHeight > _flick.height
                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width:  4
        }

        // ── Empty state ──────────────────────────────────────────────────────
        Text {
            visible:             !root.toastMode && root._notifCount === 0
            anchors.horizontalCenter: parent.horizontalCenter
            text:                "No notifications"
            color:               ThemeManager.onSurfaceVariant
            font.family:         ThemeManager.fontFamily
            font.pixelSize:      ThemeManager.fontSizeSm
            opacity:             0.5
        }

        // Plain Column + explicit child widths — avoids the ColumnLayout
        // wrapped-Text measurement bug where bodies don't grow vertically.
        Column {
            id: _col
            width:   _flick.width
            spacing: ThemeManager.spacing

            // Toast mode: stacked toast queue (newest on top). Full mode: all items.
            Repeater {
                model: root.toastMode ? NotificationService.toastCount : root._notifCount

                delegate: Rectangle {
                    id: _notifDelegate
                    required property int index

                    // Toast: newest-first toast stack. Full: newest-first full list.
                    readonly property var notif: {
                        if (root.toastMode) {
                            const t = NotificationService.toastNotifs
                            return (t && index < t.length) ? t[index] : null
                        }
                        const _ = root._notifCount
                        const arr = NotificationService.notifList
                        if (!arr || !arr.length) return null
                        const idx = arr.length - 1 - index
                        return (idx >= 0 && idx < arr.length) ? arr[idx] : null
                    }

                    // Hide stale/blank delegates: backing notification gone (count
                    // vs list briefly out of sync) OR a destroyed ref whose props
                    // read empty (would otherwise render an empty box).
                    readonly property bool _hasContent: {
                        const n = notif
                        if (!n) return false
                        return (n.appName && n.appName !== "")
                            || (n.summary && n.summary !== "")
                            || (n.body    && n.body    !== "")
                    }
                    visible: _hasContent
                    width:  _col.width
                    height: _hasContent ? _notifContent.height + ThemeManager.spacing * 2 : 0
                    radius: ThemeManager.chipRadius
                    color:  _activateMa.containsMouse ? Qt.lighter(ThemeManager.surfaceContainerHigh, 1.25)
                                                      : ThemeManager.surfaceContainerHigh

                    // Click the notification (anywhere but the ✕) → open its app.
                    readonly property bool _clickOpens: SettingsService.get("notifications.clickOpensApp", true)
                    MouseArea {
                        id: _activateMa
                        anchors.fill: parent
                        enabled: _notifDelegate._clickOpens
                        hoverEnabled: _notifDelegate._clickOpens
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            const n = _notifDelegate.notif
                            if (n) NotificationService.activate(n)
                        }
                    }

                    Column {
                        id: _notifContent
                        x: ThemeManager.spacing
                        y: ThemeManager.spacing
                        width:   parent.width - ThemeManager.spacing * 2
                        spacing: 2

                        // App row: icon · app name · dismiss
                        Item {
                            width:  parent.width
                            height: 18

                            Item {
                                id: _appIcon
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width:  14; height: 14

                                // notify-send -i may populate appIcon OR the image hint
                                readonly property string _raw: {
                                    const n = _notifDelegate.notif
                                    if (!n) return ""
                                    return (n.appIcon && n.appIcon !== "") ? n.appIcon
                                         : (n.image   && n.image   !== "") ? n.image
                                         : ""
                                }
                                // Resolve freedesktop icon names → file path; pass
                                // through absolute/file paths unchanged.
                                readonly property string _src: {
                                    const s = _appIcon._raw
                                    if (s === "") return ""
                                    if (s.startsWith("/") || s.startsWith("file:"))
                                        return s
                                    return Quickshell.iconPath(s, true)
                                }

                                IconImage {
                                    id: _appImg
                                    anchors.fill: parent
                                    implicitSize: 14
                                    source:  _appIcon._src
                                    visible: _appIcon._src !== "" && status === Image.Ready
                                }
                                // Fallback bubble glyph when no app icon (or load failed)
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
                                anchors {
                                    left: _appIcon.right; leftMargin: 6
                                    right: _dismissBtn.left; rightMargin: 6
                                    verticalCenter: parent.verticalCenter
                                }
                                text:           _notifDelegate.notif?.appName ?? ""
                                color:          ThemeManager.onSurfaceVariant
                                font.family:    ThemeManager.fontFamily
                                font.pixelSize: ThemeManager.fontSizeSm
                                elide:          Text.ElideRight
                            }
                            Item {
                                id: _dismissBtn
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width:  18; height: 18

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 18; height: 18; radius: 9
                                    color: _dismissMa.containsMouse
                                        ? Qt.rgba(ThemeManager.onSurface.r, ThemeManager.onSurface.g,
                                                  ThemeManager.onSurface.b, 0.12)
                                        : "transparent"
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text:           "✕"
                                    color:          ThemeManager.onSurfaceVariant
                                    font.family:    ThemeManager.fontFamily
                                    font.pixelSize: 10
                                }
                                MouseArea {
                                    id: _dismissMa
                                    anchors.fill:    parent
                                    anchors.margins: -4
                                    hoverEnabled:    true
                                    cursorShape:     Qt.PointingHandCursor
                                    onClicked: {
                                        const n = _notifDelegate.notif
                                        if (n) NotificationService.dismiss(n)
                                    }
                                }
                            }
                        }

                        Text {
                            readonly property string _s: _notifDelegate.notif?.summary ?? ""
                            visible:        _s.length > 0
                            width:          parent.width
                            text:           _s
                            color:          ThemeManager.onSurface
                            font.family:    ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm
                            font.weight:    Font.Medium
                            wrapMode:       Text.WordWrap
                        }

                        Text {
                            readonly property string _b: _notifDelegate.notif?.body ?? ""
                            visible:        _b.length > 0
                            width:          parent.width
                            text:           _b
                            color:          ThemeManager.onSurfaceVariant
                            font.family:    ThemeManager.fontFamily
                            font.pixelSize: ThemeManager.fontSizeSm
                            wrapMode:       Text.WordWrap
                            // Toast: cap 3 lines + elide. Full center: show all.
                            maximumLineCount: root.toastMode ? 3 : 999
                            elide:            root.toastMode ? Text.ElideRight : Text.ElideNone
                        }
                    }
                }
            }
        }
    }
}
