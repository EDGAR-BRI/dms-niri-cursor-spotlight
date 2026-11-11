import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "cursorSpotlight"

    readonly property var daemonInstance: pluginService && pluginService.pluginDaemonInstances ? pluginService.pluginDaemonInstances[pluginId] : null

    StyledText {
        width: parent.width
        text: "Cursor Spotlight, Clicks & Draw"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Localizador de ratón con Blur (Mod+Alt+C), ondas al hacer click (Mod+Shift+C) y modo pincel en pantalla (Mod+Alt+D) para Niri + DMS."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "clicksActive"
        label: "Destacar clicks del ratón"
        description: "Muestra ondas animadas al hacer click izquierdo, derecho o central (Mod+Shift+C)"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showHaloWithClicks"
        label: "Mostrar halo alrededor del cursor"
        description: "Dibuja un anillo sutil siguiendo al cursor mientras el destacado de clicks está activo"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "spotlightRadius"
        label: "Radio del Spotlight (Blur)"
        description: "Tamaño del círculo nítido alrededor del ratón al activar Mod+Alt+C"
        defaultValue: 140
        minimum: 60
        maximum: 320
        unit: "px"
    }

    SliderSetting {
        settingKey: "rippleSize"
        label: "Tamaño de onda de click"
        description: "Radio máximo de expansión al hacer click"
        defaultValue: 48
        minimum: 24
        maximum: 100
        unit: "px"
    }

    SliderSetting {
        settingKey: "rippleDuration"
        label: "Duración de onda de click"
        description: "Tiempo de la animación de cada click en milisegundos"
        defaultValue: 420
        minimum: 200
        maximum: 900
        unit: "ms"
    }

    ToggleSetting {
        settingKey: "drawLaserMode"
        label: "Modo Pincel Láser por defecto"
        description: "En Modo Pincel (Mod+Alt+D), los trazos se desvanecen automáticamente tras 2 segundos (también alternable con la tecla L)"
        defaultValue: false
    }

    SliderSetting {
        settingKey: "drawSize"
        label: "Grosor del Pincel"
        description: "Grosor inicial del trazo (ajustable con la rueda del ratón mientras dibujas)"
        defaultValue: 5
        minimum: 2
        maximum: 24
        unit: "px"
    }
}
