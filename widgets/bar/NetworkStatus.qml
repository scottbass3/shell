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

    // Find first wifi device and first connected network
    property var wifiDevice: null
    property var connectedNetwork: null
    property bool isWifi: wifiDevice !== null && connectedNetwork !== null
    property bool isEthernet: !isWifi && _hasEthernet

    property bool _hasEthernet: false

    // Scan devices to find wifi + ethernet state (logic-only, not in layout)
    Repeater {
        model: Networking.devices
        delegate: Item {
            required property var modelData

            Component.onCompleted: {
                if (modelData.type === DeviceType.Wifi && root.wifiDevice === null) {
                    root.wifiDevice = modelData
                }
                if (modelData.type === DeviceType.Ethernet && modelData.connected) {
                    root._hasEthernet = true
                }
            }
        }
    }

    // Find connected wifi network
    Repeater {
        model: wifiDevice ? wifiDevice.networks : null
        delegate: Item {
            required property var modelData
            Component.onCompleted: {
                if (modelData.connected && root.connectedNetwork === null)
                    root.connectedNetwork = modelData
            }
        }
    }

    Text {
        id: _icon
        anchors.centerIn: parent
        text: {
            if (isEthernet) return "󰈀"
            if (!isWifi) return "󰤭"
            const s = wifiDevice?.signalStrength ?? 0
            if (s >= 80) return "󰤨"
            if (s >= 60) return "󰤥"
            if (s >= 40) return "󰤢"
            if (s >= 20) return "󰤟"
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
