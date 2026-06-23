import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../../theme"
import "../../services"

Item {
    id: root

    property var barScreen: null

    implicitWidth:  _icon.implicitWidth
    implicitHeight: _icon.implicitHeight

    // Reactive scan: bindings re-evaluate whenever the device list, a network's
    // `connected`, or its `signalStrength` changes (QML subscribes to every
    // notifiable property touched while evaluating). The connected wifi network
    // is a WifiNetwork, which carries `signalStrength` (the device does not).
    readonly property var _devices: Networking.devices?.values ?? []

    readonly property var connectedWifi: {
        for (const d of _devices) {
            if (!d || d.type !== DeviceType.Wifi) continue
            const nets = d.networks?.values ?? []
            for (const n of nets) if (n && n.connected) return n
        }
        return null
    }
    readonly property bool _hasEthernet: {
        for (const d of _devices) if (d && d.type === DeviceType.Ethernet && d.connected) return true
        return false
    }
    readonly property bool isWifi:     connectedWifi !== null
    readonly property bool isEthernet: !isWifi && _hasEthernet

    Text {
        id: _icon
        anchors.centerIn: parent
        text: {
            if (isEthernet) return "󰈀"
            if (!isWifi) return "󰤭"
            // signalStrength is a 0..1 fraction.
            const s = root.connectedWifi ? root.connectedWifi.signalStrength : 0
            if (s >= 0.8) return "󰤨"
            if (s >= 0.6) return "󰤥"
            if (s >= 0.4) return "󰤢"
            if (s >= 0.2) return "󰤟"
            return "󰤯"
        }
        color: (isWifi || isEthernet) ? ThemeManager.onSurface : ThemeManager.onSurfaceVariant
        opacity: (isWifi || isEthernet) ? 1.0 : 0.5
        font.family: ThemeManager.fontFamily
        font.pixelSize: 15
    }

    HoverHandler {
        onHoveredChanged: {
            const pos = root.mapToItem(null, root.width / 2, 0)
            if (hovered) {
                PopoutService.open("network", pos.x, root.barScreen)
                PopoutService.widgetHovered = true
            } else {
                PopoutService.widgetHovered = false
            }
        }
    }
}
