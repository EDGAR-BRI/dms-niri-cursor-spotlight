# DMS Niri Cursor Spotlight, Clicks & Screen Draw (`cursorSpotlight`)

Plugin nativo para **Dux Modular Shell (DMS / DankMaterialShell)** y **Niri** en Wayland que integra tres herramientas visuales de presentación y productividad:

1. **Modo Spotlight con Blur (`Mod+Alt+C`)**:
   - Aplica desenfoque real del compositor (`ext-background-effect-v1` / `BackgroundEffect.blurRegion`) y oscurecimiento en todos tus monitores, **recortando un círculo nítido (Spotlight)** con borde brillante exactamente alrededor del cursor.
   - Es *click-through*: puedes seguir haciendo click, scroll y usando tus ventanas normalmente mientras el foco sigue al ratón.
2. **Destacar Clicks del Ratón + Halo (`Mod+Shift+C`)**:
   - Muestra ondas expansivas animadas (*ripples*) en la posición del puntero cada vez que haces click:
     - **Click izquierdo**: Color primario del tema.
     - **Click derecho**: Ámbar (`#ffa502`).
     - **Click central**: Cian (`#00d2d3`).
   - Incluye un anillo/halo opcional alrededor del cursor mientras el modo está activo.
3. **Modo Pincel / Dibujar en Pantalla (`Mod+Alt+D`)**:
   - Dibuja directamente sobre la pantalla con una barra flotante superior:
     - **Colores rápidos**: Teclas `1` a `6` (Rojo, Amarillo, Verde, Azul, Rosa, Blanco).
     - **Modo Pincel Fijo vs. Pincel Láser (`L`)**: En modo láser, los trazos brillan y se desvanecen automáticamente tras ~2 segundos.
     - **Formas rápidas**:
       - Arrastrar normal: Trazo libre suavizado.
       - `Shift` + arrastrar: **Flecha / línea recta**.
       - `Ctrl` + arrastrar: **Rectángulo**.
     - **Rueda del ratón (Scroll)**: Cambia el grosor del pincel.
     - **Click derecho o `Z`**: Deshacer último trazo.
     - **Click central o `C`**: Limpiar toda la pantalla.
     - **Tecla `B`**: Activar/desactivar el Spotlight Blur mientras dibujas.
     - **Tecla `Esc`**: Salir del modo pincel.

---

## Instalación rápida (PC o Laptop)

###Requisitos
- **Niri** + **Dux Modular Shell (DMS)** (`>= 1.5.0`)
- `python3` y `python-evdev` (`sudo pacman -S python-evdev`)
- `gcc` y `wayland` (para compilar el micro-helper `wl-nudge`)

### Pasos

```bash
git clone git@github.com:EDGAR-BRI/dms-niri-cursor-spotlight.git ~/.config/DankMaterialShell/plugins/cursor-spotlight
cd ~/.config/DankMaterialShell/plugins/cursor-spotlight
chmod +x install.sh
./install.sh
```

---

## Atajos en Niri (`~/.config/niri/config.kdl`)

Agrega dentro de tu bloque `binds { ... }`:

```kdl
    Mod+Alt+C hotkey-overlay-title="Localizar ratón (Spotlight Blur)" { spawn "dms" "ipc" "call" "cursorSpotlight" "spotlightToggle"; }
    Mod+Shift+C hotkey-overlay-title="Destacar clicks del ratón (Toggle)" { spawn "dms" "ipc" "call" "cursorSpotlight" "clicksToggle"; }
    Mod+Alt+D hotkey-overlay-title="Modo Pincel (Dibujar en pantalla)" { spawn "dms" "ipc" "call" "cursorSpotlight" "drawToggle"; }
```

---

## Comandos IPC disponibles

```bash
# Alternar Spotlight con Blur en toda la pantalla
dms ipc call cursorSpotlight spotlightToggle

# Pulso rápido de Spotlight (se apaga solo tras ~1.8s)
dms ipc call cursorSpotlight spotlightPing

# Alternar destacado de clicks + halo del cursor
dms ipc call cursorSpotlight clicksToggle

# Alternar Modo Pincel para dibujar en pantalla
dms ipc call cursorSpotlight drawToggle

# Limpiar todos los dibujos de la pantalla
dms ipc call cursorSpotlight drawClear
```
