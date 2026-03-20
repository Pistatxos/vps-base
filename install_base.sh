#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# install_base.sh
# Script base para preparar servidores Ubuntu nuevos
# =========================================================

DEFAULT_USER="xuser"
RUN_FULL_UPGRADE="true"

# -----------------------------
# Logs
# -----------------------------
log()  { echo -e "\n\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m   $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m  $*"; }

require_root() {
  [[ "${EUID}" -ne 0 ]] && err "Ejecuta como root (sudo)" && exit 1
}

ask_with_default() {
  local prompt="$1"
  local default="$2"
  local reply=""
  read -r -p "${prompt} [${default}]: " reply
  echo "${reply:-$default}"
}

ask_yes_no_default_yes() {
  local prompt="$1"
  local reply=""
  read -r -p "${prompt} [Y/n]: " reply
  case "${reply}" in
    ""|Y|y|YES|yes) return 0 ;;
    *) return 1 ;;
  esac
}

append_if_missing() {
  local line="$1"
  local file="$2"
  touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

run_as_target_user() {
  sudo -u "${TARGET_USER}" -H bash -lc "$*"
}

ask_hidden_confirmed() {
  local value1=""
  local value2=""

  while true; do
    read -r -s -p "Contraseña: " value1
    echo
    read -r -s -p "Repite contraseña: " value2
    echo

    [[ -z "$value1" ]] && warn "Vacío" && continue
    [[ "$value1" != "$value2" ]] && warn "No coinciden" && continue

    PASSWORD_RESULT="$value1"
    return
  done
}

require_root

# -----------------------------
# Preguntas iniciales
# -----------------------------
TARGET_USER="$(ask_with_default 'Nombre del usuario' "${DEFAULT_USER}")"

if ask_yes_no_default_yes "¿Instalar Cockpit?"; then
  INSTALL_COCKPIT="true"
else
  INSTALL_COCKPIT="false"
fi

# -----------------------------
# Log
# -----------------------------
LOG_DIR="/var/log/instalacion"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/instalacion_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

log "Inicio instalación base"
log "Usuario: $TARGET_USER"
log "Cockpit: $INSTALL_COCKPIT"
log "Log: $LOG_FILE"

# -----------------------------
# Sistema
# -----------------------------
apt update
[[ "$RUN_FULL_UPGRADE" == "true" ]] && apt upgrade -y

# -----------------------------
# Paquetes base
# -----------------------------
apt install -y \
  ca-certificates curl git gnupg lsb-release unzip zip wget \
  make build-essential ufw sudo rsync htop jq \
  openssh-server passwd \
  python3 python3-pip python3-venv

systemctl enable --now ssh

# -----------------------------
# Usuario
# -----------------------------
if ! id "$TARGET_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$TARGET_USER"

  ask_hidden_confirmed
  echo "$TARGET_USER:$PASSWORD_RESULT" | chpasswd
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

usermod -aG sudo "$TARGET_USER"

# -----------------------------
# SSH
# -----------------------------
SSH_DIR="$TARGET_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
touch "$AUTH_KEYS"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"
chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"

echo "Añadir clave SSH:"
echo "1) Pegar"
echo "2) Archivo"
echo "3) Omitir"
read -r opt

if [[ "$opt" == "1" ]]; then
  read -r -p "Clave: " key
  echo "$key" >> "$AUTH_KEYS"
elif [[ "$opt" == "2" ]]; then
  read -r -p "Ruta: " file
  [[ -f "$file" ]] && cat "$file" >> "$AUTH_KEYS"
fi

# -----------------------------
# pyenv
# -----------------------------
apt install -y \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev llvm libncursesw5-dev xz-utils tk-dev \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

BASHRC="$TARGET_HOME/.bashrc"
PROFILE="$TARGET_HOME/.profile"

if [[ ! -d "$TARGET_HOME/.pyenv" ]]; then
  run_as_target_user "git clone https://github.com/pyenv/pyenv.git ~/.pyenv"
fi

append_if_missing 'export PYENV_ROOT="$HOME/.pyenv"' "$BASHRC"
append_if_missing 'export PATH="$PYENV_ROOT/bin:$PATH"' "$BASHRC"
append_if_missing 'eval "$(pyenv init - bash)"' "$BASHRC"

append_if_missing 'export PYENV_ROOT="$HOME/.pyenv"' "$PROFILE"
append_if_missing 'export PATH="$PYENV_ROOT/bin:$PATH"' "$PROFILE"

# -----------------------------
# pyenv-virtualenv (AQUÍ LO IMPORTANTE)
# -----------------------------
PYENV_VENV_DIR="$TARGET_HOME/.pyenv/plugins/pyenv-virtualenv"

if [[ ! -d "$PYENV_VENV_DIR" ]]; then
  run_as_target_user "git clone https://github.com/pyenv/pyenv-virtualenv.git $PYENV_VENV_DIR"
fi

# IMPORTANTE → añadir a bashrc/profile
append_if_missing 'eval "$(pyenv virtualenv-init -)"' "$BASHRC"
append_if_missing 'eval "$(pyenv virtualenv-init -)"' "$PROFILE"

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.pyenv"

# -----------------------------
# Docker
# -----------------------------
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt update

apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

usermod -aG docker "$TARGET_USER"

# -----------------------------
# /projects
# -----------------------------
mkdir -p /projects
chown "$TARGET_USER:docker" /projects
chmod 2775 /projects

# -----------------------------
# AWS CLI
# -----------------------------
TMP=$(mktemp -d)
cd "$TMP"

curl -s https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o aws.zip
unzip aws.zip
./aws/install

cd /
rm -rf "$TMP"

# -----------------------------
# Cockpit
# -----------------------------
if [[ "$INSTALL_COCKPIT" == "true" ]]; then
  apt install -y cockpit cockpit-pcp
  systemctl enable --now cockpit.socket
  ufw allow 9090 || true
fi

# -----------------------------
# Resumen final
# -----------------------------
log "===== RESUMEN ====="

echo "Usuario: $TARGET_USER"
echo "Home: $TARGET_HOME"
echo "Log: $LOG_FILE"

echo "--- Sistema ---"
uname -a

echo "--- IP ---"
hostname -I

echo "--- Disco ---"
df -h

echo "--- RAM ---"
free -h

echo "--- Versiones ---"
python3 --version
docker --version
docker compose version
git --version
jq --version
htop --version

echo "--- Servicios ---"
systemctl is-active docker
systemctl is-active ssh
[[ "$INSTALL_COCKPIT" == "true" ]] && systemctl is-active cockpit.socket

echo "--- Usuario ---"
id "$TARGET_USER"

echo "--- /projects ---"
ls -ld /projects

ok "Instalación completa"
ok "Log: $LOG_FILE"

echo
echo "Siguiente:"
echo "sudo -iu $TARGET_USER"
echo "pyenv install 3.12.12"
echo "pyenv virtualenv 3.12.12 app-env"
echo "pyenv global app-env"