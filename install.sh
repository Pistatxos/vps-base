#!/usr/bin/env bash
# =============================================================================
#  install.sh — Selector de los scripts de vps-base
# =============================================================================
#  USO (en la VPS) — opción A, descargar y luego ejecutar (más seguro,
#  puedes leer el script antes de lanzarlo):
#    curl -fsSL https://vps.mariox.es -o install.sh
#    chmod +x install.sh
#    sudo ./install.sh
#
#  USO — opción B, todo en un comando (más rápido, típico curl | bash):
#    curl -fsSL https://vps.mariox.es | sudo bash
#
#  Descarga el catálogo (scripts.conf), muestra el menú, y al elegir una
#  opción descarga y lanza ese script. No hace falta descargar nada más a mano.
#  Los prompts se leen de /dev/tty para que la opción B también funcione.
# =============================================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/Pistatxos/vps-base/main"

log()  { echo -e "\n\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ ERR]\033[0m $*"; exit 1; }

[[ "${EUID}" -ne 0 ]] && err "Ejecuta como root: sudo ./install.sh (o: curl ... | sudo bash)"
command -v curl >/dev/null || err "Necesitas curl instalado."
[[ -r /dev/tty ]] || err "No hay terminal interactiva (/dev/tty). Este script necesita poder preguntar."

clear
printf '\033[1;36m'
cat <<'BANNER'
█   █ ████   ████   ████   ███   ████ █████
█   █ █   █ █       █   █ █   █ █     █
█   █ █   █ █       █   █ █   █ █     █
█   █ ████   ███    ████  █████  ███  ████
 █ █  █         █   █   █ █   █     █ █
  █   █     ████    ████  █   █ ████  █████
BANNER
printf '\033[0m'
echo "        Bootstrap para servidores Ubuntu — github.com/Pistatxos/vps-base"

TMP="$(mktemp -d)"

log "Descargando catálogo de scripts..."
curl -fsSL "${REPO_RAW}/scripts.conf" -o "${TMP}/scripts.conf" || { rm -rf "$TMP"; err "No se pudo descargar scripts.conf"; }
# shellcheck source=/dev/null
source "${TMP}/scripts.conf"

[[ "${#SCRIPTS[@]}" -eq 0 ]] && { rm -rf "$TMP"; err "scripts.conf no define ningún script."; }

echo ""
echo "----------------------------------------------"
echo "  Elige qué instalar:"
echo "----------------------------------------------"
for i in "${!SCRIPTS[@]}"; do
  printf "  \033[1;33m%d)\033[0m %s\n" "$((i + 1))" "$(basename "${SCRIPTS[$i]}")"
  printf "     %s\n\n" "${DESCRIPTIONS[$i]:-(sin descripción)}"
done
echo "  0) Salir"
echo ""

read -r -p "Opción: " OPT < /dev/tty

if [[ "$OPT" == "0" ]]; then
  warn "Cancelado."
  rm -rf "$TMP"
  exit 0
fi

if ! [[ "$OPT" =~ ^[0-9]+$ ]]; then
  rm -rf "$TMP"
  err "Opción inválida."
fi

IDX=$((OPT - 1))
CHOSEN_PATH="${SCRIPTS[$IDX]:-}"
[[ -z "$CHOSEN_PATH" ]] && { rm -rf "$TMP"; err "Opción inválida."; }
CHOSEN_NAME="$(basename "$CHOSEN_PATH")"

log "Descargando ${CHOSEN_NAME}..."
curl -fsSL "${REPO_RAW}/${CHOSEN_PATH}" -o "${TMP}/${CHOSEN_NAME}" || { rm -rf "$TMP"; err "No se pudo descargar ${CHOSEN_NAME}"; }
chmod +x "${TMP}/${CHOSEN_NAME}"

ok "Lanzando ${CHOSEN_NAME}"
echo ""

set +e
"${TMP}/${CHOSEN_NAME}" < /dev/tty
EXIT_CODE=$?
set -e

rm -rf "$TMP"
exit "$EXIT_CODE"
