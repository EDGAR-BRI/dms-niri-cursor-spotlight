import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "cursor-spotlight"

    readonly property var daemonInstance: pluginService && pluginService.pluginDaemonInstances ? pluginService.pluginDaemonInstances[pluginId] : null
    readonly property bool spotlightOn: daemonInstance ? daemonInstance.spotlightActive : false
    readonly property bool clicksOn: daemonInstance ? daemonInstance.clicksActive : Boolean(pluginData.clicksActive)
    readonly property bool drawOn: daemonInstance ? daemonInstance.drawActive : false
    readonly property bool isAnyOn: spotlightOn || clicksOn || drawOn

    pillClickAction: () => {
        if (root.daemonInstance) {
            root.daemonInstance.toggleClicks();
        }
    }

    pillRightClickAction: () => {
        if (root.daemonInstance) {
            root.daemonInstance.toggleSpotlight();
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: root.drawOn ? "brush" : (root.spotlightOn ? "flare" : (root.clicksOn ? "ads_click" : "my_location"))
                size: root.iconSize
                color: root.isAnyOn ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DIcon {
            name: root.drawOn ? "brush" : (root.spotlightOn ? "flare" : (root.clicksOn ? "ads_click" : "my_location"))
            size: root.iconSize
            color: root.isAnyOn ? Theme.primary : Theme.surfaceVariantText
        }
    }
}
