#!/usr/bin/env bash
set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PLUGIN_DIR}"

ACTION="${1:-check}"

case "${ACTION}" in
    check)
        if ! git fetch origin main --quiet 2>/dev/null; then
            echo "ERROR|No se pudo conectar con GitHub"
            exit 0
        fi
        LOCAL=$(git rev-parse HEAD 2>/dev/null || echo "")
        REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "")
        if [ -n "${LOCAL}" ] && [ -n "${REMOTE}" ] && [ "${LOCAL}" != "${REMOTE}" ]; then
            COUNT=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "1")
            MSG=$(git log -1 --format="%s" origin/main 2>/dev/null || echo "")
            echo "UPDATE_AVAILABLE|${COUNT}|${MSG}"
        else
            echo "UP_TO_DATE|${LOCAL:0:7}"
        fi
        ;;
    update)
        git pull origin main || {
            echo "ERROR|Fallo al descargar actualización"
            exit 1
        }
        if command -v gcc >/dev/null 2>&1; then
            gcc -O2 "${PLUGIN_DIR}/wl_nudge.c" -o "${PLUGIN_DIR}/wl-nudge" -lwayland-client 2>/dev/null || true
            chmod +x "${PLUGIN_DIR}/wl-nudge" 2>/dev/null || true
        fi
        chmod +x "${PLUGIN_DIR}/cursor_helper.py" "${PLUGIN_DIR}/install.sh" "${PLUGIN_DIR}/update_helper.sh" 2>/dev/null || true
        nohup sh -c "sleep 0.8 && dms restart" >/dev/null 2>&1 &
        echo "SUCCESS"
        ;;
    *)
        echo "Uso: $0 [check|update]"
        exit 1
        ;;
esac
