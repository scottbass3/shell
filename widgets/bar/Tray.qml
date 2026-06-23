import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Hyprland
import "../../theme"
import "../../services"

RowLayout {
    id: root

    property var barScreen: null

    // Configurable in Settings → Tray. Defaults preserve the prior hardcoded set.
    // hidden: substrings of a tray item's id/title to hide (case-insensitive).
    readonly property var hidden: SettingsService.get("tray.hidden",
        ["nm-applet", "blueman", "slimbookintelcontrollerindicator.py",
         "Wayland to X11 Video bridge", "Gestionnaire de paramètres de Manjaro"])

    // specialWs: [{match, ws}] — left-click toggles that Hyprland special
    // workspace instead of activating the item (ws names match hyprland.lua rules).
    readonly property var specialWs: SettingsService.get("tray.specialWs", [
        { match: "spotify",   ws: "spotify"    },
        { match: "youtube",   ws: "ytmusic"    },
        { match: "rocket",    ws: "rocketchat" },
        { match: "vesktop",   ws: "vesktop"    },
        { match: "discord",   ws: "vesktop"    },
        { match: "vencord",   ws: "vesktop"    }
    ])

    function _wsFor(item) {
        // Electron apps share id "chrome_status_icon_1" with empty title — the
        // only distinguishing field is the tooltip title (e.g. "Vesktop").
        const hay = ((item.id ?? "") + " " + (item.title ?? "") + " "
                   + (item.tooltipTitle ?? "")).toLowerCase()
        for (const e of root.specialWs)
            if (hay.includes(e.match)) return e.ws
        return ""
    }

    spacing: 2

    readonly property var _items: {
        const all = SystemTray.items?.values ?? []
        if (!root.hidden || root.hidden.length === 0) return all
        return all.filter(it => {
            const hay = ((it.id ?? "") + " " + (it.title ?? "")).toLowerCase()
            return !root.hidden.some(h => hay.includes(String(h).toLowerCase()))
        })
    }

    // Custom user entries for apps without SNI tray support. Each:
    // { name, icon (freedesktop name or path), action: "run"|"ws", value }.
    readonly property var _custom: SettingsService.get("tray.custom", [])

    function _runEntry(e) {
        if (e.action === "ws")
            Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + String(e.value) + '")')
        else
            Quickshell.execDetached(["sh", "-c", String(e.value)])
    }

    Repeater {
        model: root._items

        delegate: Item {
            id: trayItem
            required property SystemTrayItem modelData

            implicitWidth:  22
            implicitHeight: 22
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius:       4
                color:        _trayHov.hovered
                    ? ThemeManager.surfaceVariant
                    : Qt.rgba(ThemeManager.surfaceVariant.r, ThemeManager.surfaceVariant.g, ThemeManager.surfaceVariant.b, 0)
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize:     16
                source:           trayItem.modelData.icon
            }

            HoverHandler {
                id: _trayHov
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: {
                    if (!hovered && PopoutService.currentName === "traymenu")
                        PopoutService.widgetHovered = false
                }
            }

            // Left click → toggle special workspace (if parked there), else activate
            readonly property string _ws: root._wsFor(trayItem.modelData)
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: {
                    if (trayItem._ws !== "")
                        // Hyprland 0.55 lua IPC: dispatch evaluates as hl.dispatch(<arg>),
                        // so pass a dispatcher expression, not the legacy string.
                        Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + trayItem._ws + '")')
                    else
                        trayItem.modelData.activate()
                }
            }
            // Right click → context menu
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    const pos = trayItem.mapToItem(null, trayItem.width / 2, 0)
                    PopoutService.menuHandle = trayItem.modelData.menu
                    PopoutService.open("traymenu", pos.x, root.barScreen)
                    PopoutService.pinned = true
                }
            }

            ToolTip.visible: _trayHov.hovered && trayItem.modelData.title !== ""
            ToolTip.text:    trayItem.modelData.title
            ToolTip.delay:   600
        }
    }

    // ── Custom (non-SNI) entries ──────────────────────────────────────────────
    Repeater {
        model: root._custom

        delegate: Item {
            id: customItem
            required property var modelData

            implicitWidth:  22
            implicitHeight: 22
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius:       4
                color:        _custHov.hovered
                    ? ThemeManager.surfaceVariant
                    : Qt.rgba(ThemeManager.surfaceVariant.r, ThemeManager.surfaceVariant.g, ThemeManager.surfaceVariant.b, 0)
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize:     16
                source: {
                    const ic = String(customItem.modelData.icon ?? "")
                    if (ic === "") return ""
                    return (ic.startsWith("/") || ic.indexOf("://") >= 0)
                        ? ic : Quickshell.iconPath(ic, true)
                }
            }

            HoverHandler { id: _custHov; cursorShape: Qt.PointingHandCursor }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root._runEntry(customItem.modelData)
            }

            ToolTip.visible: _custHov.hovered && (customItem.modelData.name ?? "") !== ""
            ToolTip.text:    customItem.modelData.name ?? ""
            ToolTip.delay:   600
        }
    }
}
