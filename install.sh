#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="cursorSpotlight"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DMS_DIR="${HOME}/.config/dms/plugins/${PLUGIN_ID}"
DMS_DIR_KEBAB="${HOME}/.config/dms/plugins/cursor-spotlight"
LEGACY_DIR="${HOME}/.config/DankMaterialShell/plugins/cursor-spotlight"

echo "==> Instalando plugin ${PLUGIN_ID} para DMS + Niri..."

# 1. Asegurar directorios destino en ~/.config/dms/plugins/ y ~/.config/DankMaterialShell/plugins/
mkdir -p "${HOME}/.config/dms/plugins"
mkdir -p "${HOME}/.config/DankMaterialShell/plugins"

# Enlazar en ~/.config/dms/plugins/ (ruta oficial del sistema DMS)
if [ "${PLUGIN_DIR}" != "$(realpath "${DMS_DIR_KEBAB}" 2>/dev/null || echo "")" ]; then
    ln -sfn "${PLUGIN_DIR}" "${DMS_DIR_KEBAB}"
fi
# Enlazar con alias camelCase y legacy
ln -sfn "${PLUGIN_DIR}" "${DMS_DIR}" 2>/dev/null || true
ln -sfn "${PLUGIN_DIR}" "${LEGACY_DIR}" 2>/dev/null || true
echo "    Instalado y enlazado en: ${DMS_DIR_KEBAB}"

# 2. Compilar wl-nudge si gcc y cabeceras están disponibles
if command -v gcc >/dev/null 2>&1; then
    echo "==> Compilando helper Wayland (wl-nudge)..."
    gcc -O2 "${PLUGIN_DIR}/wl_nudge.c" -o "${PLUGIN_DIR}/wl-nudge" -lwayland-client 2>/dev/null || {
        echo "    [Nota] No se pudo compilar wl-nudge (falta libwayland-client o similar). El plugin funcionará normalmente con cursor_helper.py."
    }
    chmod +x "${PLUGIN_DIR}/wl-nudge" 2>/dev/null || true
fi
chmod +x "${PLUGIN_DIR}/cursor_helper.py"

# Asegurar dependencias de python (evdev) en Arch / CachyOS si pacman está presente
if ! python3 -c "import evdev" >/dev/null 2>&1; then
    echo "==> Instalando python-evdev necesario para capturar clicks..."
    if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm python-evdev || echo "    [Aviso] Instala python-evdev manualmente: sudo pacman -S python-evdev"
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y python3-evdev || echo "    [Aviso] Instala python3-evdev con apt"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y python3-evdev || echo "    [Aviso] Instala python3-evdev con dnf"
    fi
fi

# 3. Configurar permisos de lectura de clicks (uaccess udev rule + setfacl inmediato)
echo "==> Configurando permisos de lectura de eventos de ratón (sin necesidad de reiniciar sesión)..."
UDEV_RULE='SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_MOUSE}=="1", TAG+="uaccess"'
UDEV_RULE_TP='SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHPAD}=="1", TAG+="uaccess"'

if command -v pkexec >/dev/null 2>&1; then
    pkexec sh -c "
        usermod -aG input ${USER} || true
        printf '%s\n%s\n' '${UDEV_RULE}' '${UDEV_RULE_TP}' > /etc/udev/rules.d/70-dms-cursor-spotlight.rules
        udevadm control --reload-rules && udevadm trigger --subsystem-match=input || true
        setfacl -m u:${USER}:r /dev/input/event* || true
    " || echo "    [Aviso] No se aplicaron permisos con pkexec; el plugin los solicitará al activar el modo de clicks."
fi

# 4. Registrar y activar en DMS
python3 -c '
import json, os
for base in [os.path.expanduser("~/.config/dms"), os.path.expanduser("~/.config/DankMaterialShell")]:
    os.makedirs(base, exist_ok=True)
    p = os.path.join(base, "plugin_settings.json")
    d = {}
    if os.path.exists(p):
        try:
            with open(p, "r") as f: d = json.load(f)
        except Exception: pass
    if "cursorSpotlight" not in d: d["cursorSpotlight"] = {}
    d["cursorSpotlight"]["enabled"] = True
    try:
        with open(p, "w") as f: json.dump(d, f, indent=2)
    except Exception: pass
' 2>/dev/null || true

if command -v dms >/dev/null 2>&1; then
    echo "==> Escaneando y habilitando el plugin en DMS..."
    dms ipc call plugin-scan scan >/dev/null 2>&1 || true
    dms ipc call plugins enable "${PLUGIN_ID}" >/dev/null 2>&1 || true
    dms ipc call plugins reload "${PLUGIN_ID}" >/dev/null 2>&1 || true
fi

echo ""
echo "✅ Plugin ${PLUGIN_ID} instalado correctamente."
echo "Atajos recomendados para ~/.config/niri/config.kdl (dentro de binds { ... }):"
echo '    Mod+Alt+C hotkey-overlay-title="Localizar ratón (Spotlight Blur)" { spawn "dms" "ipc" "call" "cursorSpotlight" "spotlightToggle"; }'
echo '    Mod+Shift+C hotkey-overlay-title="Destacar clicks del ratón (Toggle)" { spawn "dms" "ipc" "call" "cursorSpotlight" "clicksToggle"; }'
echo '    Mod+Alt+D hotkey-overlay-title="Modo Pincel (Dibujar en pantalla)" { spawn "dms" "ipc" "call" "cursorSpotlight" "drawToggle"; }'
