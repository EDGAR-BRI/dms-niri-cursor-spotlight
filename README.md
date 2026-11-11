# DMS Cursor Spotlight, Clicks & Screen Draw (`cursorSpotlight`)

Plugin nativo para **Dux Modular Shell (DMS / DankMaterialShell)** en Wayland (**Niri**, **Hyprland**, **Sway**, **MangoWM**, **Wayfire**) que integra tres herramientas visuales de presentación y productividad:

1. **Modo Spotlight con Blur (`Mod+Alt+C`)**:
   - Aplica desenfoque real del compositor (`ext-background-effect-v1` / `BackgroundEffect.blurRegion`) y oscurecimiento en todos tus monitores, **recortando un círculo nítido (Spotlight)** con borde brillante alrededor del cursor.
   - Es *click-through*: puedes seguir haciendo click, scroll y usando tus ventanas normalmente mientras el foco sigue al ratón.
2. **Destacar Clicks del Ratón + Halo con Rebote (`Mod+Shift+C`)**:
   - **Crecimiento elástico del Halo (`Easing.OutBack`)**: El anillo alrededor del cursor crece y rebota en cada click.
   - **Doble onda expansiva (*Shockwave*) + Rayos radiales (*Click Burst*)** a 60 FPS con colores personalizables por botón (Izquierdo, Derecho y Central).
3. **Modo Pincel / Dibujar en Pantalla (`Mod+Alt+D`)**:
   - Dibuja directamente sobre la pantalla con una barra de herramientas flotante estilo Paint (Material 3):
     - **Herramientas de dibujo**:
       - 🖌️ **Pincel libre (`P`)**: Trazo suave a mano alzada.
       - ↗️ **Flecha (`A`)**: Flecha apuntadora con punta rellena y eje dinámico.
       - ⭕ **Círculo / Óvalo (`O`)**: Círculo u óvalo (mantén `Shift` para proporción perfecta 1:1).
       - 🔲 **Cuadrado / Rectángulo (`R`)**: Rectángulo (mantén `Shift` para cuadrado perfecto 1:1).
     - **Control de Grosor interactivo**:
       - Botones `[-]` y `[+]`, control deslizante con previsualización en vivo del punto y tamaño en píxeles.
       - También ajustable con la **rueda del ratón (Scroll)** o teclas `[` y `]`.
     - **Colores rápidos**: Paleta visual interactiva o teclas numéricas `1` a `6` (Rojo, Amarillo, Verde, Azul, Rosa, Blanco).
     - **Modo Pincel Fijo vs. Pincel Láser (`L`)**: En modo láser, los trazos brillan con resplandor neón y se desvanecen automáticamente tras ~2 segundos.
     - **Spotlight Blur de fondo (`B`)**: Activa o desactiva el desenfoque de fondo mientras dibujas.
     - **Deshacer (`Z` o Click Derecho)**: Deshace el último trazo o figura dibujada.
     - **Limpiar pantalla (`C` o Click Central)**: Borra todos los dibujos de la pantalla.
     - **Salir (`Esc`)**: Cierra el modo de dibujo.

---

## Personalización y Actualizaciones Gráficas (Sin tocar la terminal)

Abre **Ajustes de DMS → Plugins → Cursor Spotlight, Clicks & Draw**:
- 🔄 **Actualizaciones con 1 click**: Comprobación automática y botón de actualización directa desde GitHub, recompilando y reiniciando DMS sin necesidad de usar la terminal.
- ⚡ **Control en vivo y permisos**: Activa cualquiera de los 3 modos o concede permisos de lectura del ratón con un click mediante Polkit.
- 🎯 **Clicks y Halo**: Tamaño del halo, porcentaje de crecimiento/rebote al hacer click (`100%`–`260%`), activar/desactivar ondas (*Shockwave*) o rayos (*Click Burst*), velocidad y **selectores de color gráficos** para Click Izquierdo, Derecho y Central.
- 🔍 **Spotlight (Blur)**: Radio del círculo nítido, porcentaje de oscurecimiento del fondo, grosor/color del anillo y temporizador de auto-apagado.
- 🎨 **Modo Pincel**: Modo Láser por defecto, grosor inicial y color inicial.

---

## Instalación rápida (PC o Laptop)

```bash
git clone git@github.com:EDGAR-BRI/dms-niri-cursor-spotlight.git ~/.config/DankMaterialShell/plugins/cursor-spotlight
cd ~/.config/DankMaterialShell/plugins/cursor-spotlight
chmod +x install.sh
./install.sh
```

---

## Configuración de Atajos por Compositor

### Niri (`~/.config/niri/config.kdl`)
```kdl
    Mod+Alt+C hotkey-overlay-title="Localizar ratón (Spotlight Blur)" { spawn "dms" "ipc" "call" "cursorSpotlight" "spotlightToggle"; }
    Mod+Shift+C hotkey-overlay-title="Destacar clicks del ratón (Toggle)" { spawn "dms" "ipc" "call" "cursorSpotlight" "clicksToggle"; }
    Mod+Alt+D hotkey-overlay-title="Modo Pincel (Dibujar en pantalla)" { spawn "dms" "ipc" "call" "cursorSpotlight" "drawToggle"; }
```

### Hyprland (`~/.config/hypr/hyprland.conf`)
```ini
bind = SUPER ALT, C, exec, dms ipc call cursorSpotlight spotlightToggle
bind = SUPER SHIFT, C, exec, dms ipc call cursorSpotlight clicksToggle
bind = SUPER ALT, D, exec, dms ipc call cursorSpotlight drawToggle
```

### Sway / MangoWM (`~/.config/sway/config`)
```ini
bindsym $mod+Mod1+c exec dms ipc call cursorSpotlight spotlightToggle
bindsym $mod+Shift+c exec dms ipc call cursorSpotlight clicksToggle
bindsym $mod+Mod1+d exec dms ipc call cursorSpotlight drawToggle
```
