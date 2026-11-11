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
    readonly property bool spotlightOn: daemonInstance ? daemonInstance.spotlightActive : false
    readonly property bool clicksOn: daemonInstance ? daemonInstance.clicksActive : Boolean(pluginData.clicksActive)
    readonly property bool drawOn: daemonInstance ? daemonInstance.drawActive : false
    readonly property string permStatus: daemonInstance ? daemonInstance.helperPermStatus : "UNKNOWN"

    function settingVal(key, fallback) {
        if (!pluginService || !pluginService.loadPluginData)
            return fallback;
        return pluginService.loadPluginData(pluginId, key, fallback);
    }

    function saveVal(key, val) {
        if (pluginService && pluginService.savePluginData)
            pluginService.savePluginData(pluginId, key, val);
    }

    // Reusable code snippet component with 1-click Copy button
    component BindCode: StyledRect {
        id: codeBox
        property string titleText: ""
        property string code: ""

        width: parent.width
        height: codeCol.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.25)

        Column {
            id: codeCol
            anchors.left: parent.left
            anchors.right: copyBtn.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingS
            spacing: 4

            StyledText {
                visible: codeBox.titleText !== ""
                text: codeBox.titleText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
                color: Theme.primary
            }

            TextEdit {
                width: parent.width
                text: codeBox.code
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceText
                selectionColor: Theme.primary
                selectedTextColor: Theme.surface
            }
        }

        DankActionButton {
            id: copyBtn
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingXS
            iconName: "content_copy"
            iconSize: Theme.iconSize - 6
            buttonSize: 28
            tooltipText: "Copiar al portapapeles"
            onClicked: {
                Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | dms cl copy", "_", codeBox.code]);
                ToastService.showInfo("Atajos copiados al portapapeles");
            }
        }
    }

    // Reusable color picker row
    component ColorRow: Item {
        id: colorRow
        property string labelText: ""
        property string subText: ""
        property string settingKey: ""
        property color defaultColor: Theme.primary
        property bool allowThemeReset: false

        readonly property string storedHex: root.pluginService ? root.settingVal(settingKey, "") : ""
        readonly property color currentColor: storedHex !== "" ? Qt.color(storedHex) : defaultColor

        width: parent.width
        height: 44

        Column {
            anchors.left: parent.left
            anchors.right: swatchRow.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            StyledText {
                text: colorRow.labelText
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }

            StyledText {
                visible: colorRow.subText !== ""
                text: colorRow.subText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        Row {
            id: swatchRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankActionButton {
                visible: colorRow.allowThemeReset && colorRow.storedHex !== ""
                anchors.verticalCenter: parent.verticalCenter
                iconName: "restart_alt"
                iconSize: Theme.iconSize - 4
                buttonSize: 28
                tooltipText: "Restaurar al color del tema"
                onClicked: {
                    if (root.pluginService && root.pluginService.deletePluginKey)
                        root.pluginService.deletePluginKey(root.pluginId, colorRow.settingKey);
                    else
                        root.saveVal(colorRow.settingKey, "");
                }
            }

            Rectangle {
                width: 68
                height: 28
                radius: Theme.cornerRadius
                color: colorRow.currentColor
                border.color: Theme.outlineStrong
                border.width: 2
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!PopoutService || !PopoutService.colorPickerModal)
                            return;
                        PopoutService.colorPickerModal.selectedColor = colorRow.currentColor;
                        PopoutService.colorPickerModal.pickerTitle = colorRow.labelText;
                        PopoutService.colorPickerModal.onColorSelectedCallback = selected => {
                            root.saveVal(colorRow.settingKey, selected.toString());
                        };
                        PopoutService.colorPickerModal.show();
                    }
                }
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Cursor Spotlight, Clicks & Draw"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Localizador de ratón con Blur, ondas y rebote al hacer click, y modo pincel en pantalla para Niri, Hyprland, Sway y compositores Wayland."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // 1. ESTADO Y CONTROLES EN VIVO
    StyledRect {
        width: parent.width
        height: liveCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: liveCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Control Rápido y Permisos"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            // Spotlight live toggle
            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width - spotToggle.width - Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        text: "Modo Spotlight (Blur en pantalla)"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: "Atajo: Mod+Alt+C  |  IPC: dms ipc call cursorSpotlight spotlightToggle"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                DankToggle {
                    id: spotToggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.spotlightOn
                    onToggled: isChecked => {
                        if (root.daemonInstance && root.daemonInstance.spotlightActive !== isChecked)
                            root.daemonInstance.toggleSpotlight();
                    }
                }
            }

            // Clicks live toggle
            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width - clickToggle.width - Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        text: "Destacar Clicks del Ratón + Halo"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: "Atajo: Mod+Shift+C  |  IPC: dms ipc call cursorSpotlight clicksToggle"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                DankToggle {
                    id: clickToggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.clicksOn
                    onToggled: isChecked => {
                        if (root.daemonInstance && root.daemonInstance.clicksActive !== isChecked)
                            root.daemonInstance.toggleClicks();
                    }
                }
            }

            // Draw mode live toggle
            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width - drawToggleBtn.width - Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        text: "Modo Pincel (Dibujar en pantalla)"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }
                    StyledText {
                        text: "Atajo: Mod+Alt+D  |  IPC: dms ipc call cursorSpotlight drawToggle"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                DankToggle {
                    id: drawToggleBtn
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.drawOn
                    onToggled: isChecked => {
                        if (root.daemonInstance && root.daemonInstance.drawActive !== isChecked)
                            root.daemonInstance.toggleDraw();
                    }
                }
            }

            // Permission button
            StyledRect {
                width: parent.width
                height: 44
                radius: Theme.cornerRadius
                color: root.permStatus === "OK" ? Qt.rgba(0.18, 0.84, 0.45, 0.14) : Qt.rgba(1.0, 0.65, 0.0, 0.16)
                border.width: 1
                border.color: root.permStatus === "OK" ? "#2ed573" : "#ffa502"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingS

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - authBtn.width - Theme.spacingS
                        text: root.permStatus === "OK"
                            ? "✓ Permisos de lectura de clicks del ratón activos"
                            : "Se requiere autorizar acceso al ratón (una sola vez) para animar los clicks"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    DankActionButton {
                        id: authBtn
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: root.permStatus === "OK" ? "verified_user" : "lock_open"
                        iconSize: Theme.iconSize - 4
                        buttonSize: 32
                        tooltipText: "Autorizar permisos de lectura de ratón (Polkit)"
                        onClicked: {
                            if (root.daemonInstance)
                                root.daemonInstance.requestInputPermissions();
                        }
                    }
                }
            }
        }
    }

    // 2. PERSONALIZACIÓN DE CLICKS Y HALO
    StyledRect {
        width: parent.width
        height: clicksCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: clicksCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Personalización de Clicks y Halo"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "showHaloWithClicks"
                label: "Mostrar círculo (Halo) alrededor del cursor"
                description: "Mantiene un anillo siguiendo al ratón que crece y rebota cuando haces click"
                defaultValue: true
            }

            SliderSetting {
                settingKey: "haloRadius"
                label: "Tamaño base del Halo"
                description: "Radio normal del círculo alrededor del cursor"
                defaultValue: 20
                minimum: 10
                maximum: 55
                unit: "px"
            }

            SliderSetting {
                settingKey: "haloGrowPercent"
                label: "Efecto de crecimiento al hacer click"
                description: "Qué tanto se agranda y rebota el círculo cuando presionas un botón (175% = 1.75x)"
                defaultValue: 175
                minimum: 100
                maximum: 260
                unit: "%"
            }

            ToggleSetting {
                settingKey: "showShockwave"
                label: "Mostrar doble onda expansiva (Shockwave)"
                description: "Anillos concéntricos que se expanden hacia afuera al hacer click"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showRadialBurst"
                label: "Mostrar destello radial (Click Burst)"
                description: "Líneas radiales alrededor del cursor al estilo de tutoriales"
                defaultValue: true
            }

            SliderSetting {
                settingKey: "rippleSize"
                label: "Radio máximo de la onda expansiva"
                description: "Hasta dónde se expande la onda de cada click"
                defaultValue: 58
                minimum: 25
                maximum: 120
                unit: "px"
            }

            SliderSetting {
                settingKey: "rippleDuration"
                label: "Duración de la animación del click"
                description: "Velocidad de la onda y el rebote en milisegundos"
                defaultValue: 460
                minimum: 180
                maximum: 1000
                unit: "ms"
            }

            ColorRow {
                labelText: "Color de Click Izquierdo y Halo"
                subText: "Por defecto sigue automáticamente el color primario de tu tema"
                settingKey: "leftClickColor"
                defaultColor: Theme.primary
                allowThemeReset: true
            }

            ColorRow {
                labelText: "Color de Click Derecho"
                subText: "Color de la onda y rebote al hacer click secundario"
                settingKey: "rightClickColor"
                defaultColor: "#ffa502"
                allowThemeReset: true
            }

            ColorRow {
                labelText: "Color de Click Central (Rueda)"
                subText: "Color de la onda al presionar la rueda del ratón"
                settingKey: "middleClickColor"
                defaultColor: "#00d2d3"
                allowThemeReset: true
            }
        }
    }

    // 3. PERSONALIZACIÓN DEL SPOTLIGHT (BLUR)
    StyledRect {
        width: parent.width
        height: spotCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: spotCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Personalización del Spotlight (Pantalla en Blur)"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            SliderSetting {
                settingKey: "spotlightRadius"
                label: "Radio del foco nítido (Spotlight)"
                description: "Tamaño del área circular sin desenfoque alrededor del ratón"
                defaultValue: 140
                minimum: 60
                maximum: 350
                unit: "px"
            }

            SliderSetting {
                settingKey: "spotlightDimPercent"
                label: "Oscurecimiento del fondo"
                description: "Opacidad de la capa oscura sobre el área desenfocada"
                defaultValue: 58
                minimum: 0
                maximum: 90
                unit: "%"
            }

            SliderSetting {
                settingKey: "spotlightRingWidth"
                label: "Grosor del anillo iluminado"
                description: "Borde alrededor del círculo Spotlight (0 para ocultar)"
                defaultValue: 3
                minimum: 0
                maximum: 12
                unit: "px"
            }

            SliderSetting {
                settingKey: "spotlightAutoHideSec"
                label: "Auto-apagar Spotlight"
                description: "0 = mantener activo hasta volver a pulsar el atajo; >0 = apagar solo tras X segundos"
                defaultValue: 0
                minimum: 0
                maximum: 10
                unit: "s"
            }

            ColorRow {
                labelText: "Color del borde del Spotlight"
                subText: "Por defecto usa el color primario de tu tema"
                settingKey: "spotlightCustomColor"
                defaultColor: Theme.primary
                allowThemeReset: true
            }
        }
    }

    // 4. PERSONALIZACIÓN DEL MODO PINCEL (DRAW)
    StyledRect {
        width: parent.width
        height: drawCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: drawCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Personalización del Modo Pincel"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "drawLaserMode"
                label: "Modo Pincel Láser por defecto"
                description: "Los trazos brillan y se desvanecen solos tras 2 segundos (también cambiable con la tecla L)"
                defaultValue: false
            }

            SliderSetting {
                settingKey: "drawSize"
                label: "Grosor inicial del pincel"
                description: "También puedes ajustarlo en vivo con la rueda del ratón mientras dibujas"
                defaultValue: 5
                minimum: 2
                maximum: 28
                unit: "px"
            }

            ColorRow {
                labelText: "Color inicial del pincel"
                subText: "En vivo puedes cambiarlo con las teclas 1 a 6 o en la barra superior"
                settingKey: "drawColor"
                defaultColor: "#ff4757"
                allowThemeReset: true
            }
        }
    }

    // 5. ATAJOS PARA CUALQUIER GESTOR DE VENTANAS (WAYLAND)
    StyledRect {
        width: parent.width
        height: bindsCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: bindsCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Atajos por Gestor de Ventanas (Wayland)"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: "Copia y pega el bloque correspondiente a tu compositor:"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            BindCode {
                titleText: "Niri (~/.config/niri/config.kdl)"
                code: "Mod+Alt+C { spawn \"dms\" \"ipc\" \"call\" \"cursorSpotlight\" \"spotlightToggle\"; }\n" +
                      "Mod+Shift+C { spawn \"dms\" \"ipc\" \"call\" \"cursorSpotlight\" \"clicksToggle\"; }\n" +
                      "Mod+Alt+D { spawn \"dms\" \"ipc\" \"call\" \"cursorSpotlight\" \"drawToggle\"; }"
            }

            BindCode {
                titleText: "Hyprland (~/.config/hypr/hyprland.conf)"
                code: "bind = SUPER ALT, C, exec, dms ipc call cursorSpotlight spotlightToggle\n" +
                      "bind = SUPER SHIFT, C, exec, dms ipc call cursorSpotlight clicksToggle\n" +
                      "bind = SUPER ALT, D, exec, dms ipc call cursorSpotlight drawToggle"
            }

            BindCode {
                titleText: "Sway / MangoWM (~/.config/sway/config)"
                code: "bindsym $mod+Mod1+c exec dms ipc call cursorSpotlight spotlightToggle\n" +
                      "bindsym $mod+Shift+c exec dms ipc call cursorSpotlight clicksToggle\n" +
                      "bindsym $mod+Mod1+d exec dms ipc call cursorSpotlight drawToggle"
            }
        }
    }
}
