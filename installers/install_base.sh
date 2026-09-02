#!/usr/bin/env bash
# =============================================================================
#  install_base.sh — Bootstrap interactivo para VPS Ubuntu nuevas
#  Probado en: Ubuntu 22.04 / 24.04
# =============================================================================
#  USO:
#    curl -fsSL https://raw.githubusercontent.com/Pistatxos/vps-base/main/installers/install_base.sh -o install_base.sh
#    chmod +x install_base.sh
#    sudo ./install_base.sh
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo -e "\n\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ ERR]\033[0m $*"; exit 1; }

require_root() { [[ "${EUID}" -ne 0 ]] && err "Ejecuta como root: sudo ./install_base.sh"; }

ask_with_default() {
  local prompt="$1" default="$2" reply=""
  read -r -p "${prompt} [${default}]: " reply
  echo "${reply:-$default}"
}

ask_yes_no() {
  local prompt="$1" reply=""
  read -r -p "${prompt} [Y/n]: " reply
  case "${reply}" in ""|Y|y|YES|yes) return 0 ;; *) return 1 ;; esac
}

ask_hidden_confirmed() {
  local v1="" v2=""
  while true; do
    read -r -s -p "  Contraseña: " v1; echo
    read -r -s -p "  Repite contraseña: " v2; echo
    [[ -z "$v1" ]]       && warn "No puede estar vacía." && continue
    [[ "$v1" != "$v2" ]] && warn "No coinciden, inténtalo de nuevo." && continue
    PASSWORD_RESULT="$v1"; return
  done
}

append_if_missing() {
  local line="$1" file="$2"
  touch "$file"; grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

run_as_user() { sudo -u "${TARGET_USER}" -H bash -lc "$*"; }

set_sshd_option() {
  local KEY="$1" VALUE="$2"
  if grep -qE "^[#[:space:]]*${KEY}\b" /etc/ssh/sshd_config; then
    sed -i "s|^[#[:space:]]*${KEY}.*|${KEY} ${VALUE}|g" /etc/ssh/sshd_config
  else
    echo "${KEY} ${VALUE}" >> /etc/ssh/sshd_config
  fi
}

install_awscli() {
  local ARCH TMP AWS_URL
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "x86_64" ]];   then AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  elif [[ "$ARCH" == "aarch64" ]]; then AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  else warn "Arquitectura ${ARCH} no soportada para AWS CLI, se omite."; return 1; fi
  TMP="$(mktemp -d)"
  curl -fsSL "$AWS_URL" -o "${TMP}/awscliv2.zip"
  unzip -q "${TMP}/awscliv2.zip" -d "$TMP"
  "${TMP}/aws/install"
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Comprobaciones previas
# ---------------------------------------------------------------------------
require_root

# Si venimos de un "curl | bash", stdin lo ocupa curl — reabrimos desde la
# terminal real para que las preguntas de abajo funcionen igual.
if [[ ! -t 0 ]]; then
  [[ -r /dev/tty ]] || err "No hay terminal interactiva (/dev/tty) para preguntar. Descárgalo y ejecútalo directamente: sudo ./install_base.sh"
  exec < /dev/tty
fi

# ---------------------------------------------------------------------------
# Log en disco
# ---------------------------------------------------------------------------
LOG_DIR="/var/log/instalacion"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/instalacion_${TIMESTAMP}.log"
mkdir -p "$LOG_DIR"; touch "$LOG_FILE"; chmod 600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------------------------------------------------
# Preguntas iniciales
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  VPS Bootstrap — Configuración inicial"
echo "=============================================="
echo ""

TARGET_USER="$(ask_with_default '  Nombre de usuario' 'xuser')"

echo ""
log "¿Qué hacemos con ${TARGET_USER}?"
echo "  1) Crear usuario nuevo"
echo "  2) Ya existe en este servidor — no tocar su contraseña"
read -r -p "  Opción [1/2]: " USER_OPT
if [[ "$USER_OPT" == "2" ]]; then
  CREATE_USER=false
  id "$TARGET_USER" &>/dev/null || err "El usuario ${TARGET_USER} no existe en este servidor."
else
  CREATE_USER=true
fi

if [[ "$CREATE_USER" == "true" ]]; then
  echo ""
  log "Contraseña para ${TARGET_USER}:"
  ask_hidden_confirmed
  XUSER_PASS="$PASSWORD_RESULT"
fi

echo ""
log "Plataforma Git para la Deploy Key:"
echo "  1) GitLab  (gitlab.com)"
echo "  2) GitHub  (github.com)"
echo "  3) Otra    (introducir manualmente)"
read -r -p "  Opción [1/2/3]: " GIT_OPT
case "$GIT_OPT" in
  1) GIT_HOST="gitlab.com" ;;
  2) GIT_HOST="github.com" ;;
  *) read -r -p "  Host Git (ej: gitea.midominio.com): " GIT_HOST ;;
esac

echo ""
log "Clave pública SSH para ${TARGET_USER}:"
echo "  Si ya estás conectado por SSH, tu clave está en el usuario actual."
echo "  Puedes omitir esto y copiarla después:"
echo "    sudo cp ~/.ssh/authorized_keys /home/${TARGET_USER}/.ssh/"
echo ""
echo "  1) Pegar directamente"
echo "  2) Indicar ruta de fichero"
echo "  3) Omitir (ya conectado o configurar después)"
read -r -p "  Opción [1/2/3]: " SSH_OPT
SSH_KEY=""
case "$SSH_OPT" in
  1) read -r -p "  Pega la clave pública: " SSH_KEY ;;
  2) read -r -p "  Ruta del fichero: " SSH_FILE
     [[ -f "$SSH_FILE" ]] && SSH_KEY="$(cat "$SSH_FILE")" || warn "Fichero no encontrado, se omite." ;;
  *) warn "Clave SSH omitida. Cópiala manualmente si la necesitas." ;;
esac

echo ""
INSTALL_PYTHON=false;    ask_yes_no "  ¿Instalar toolchain Python? (uv)" && INSTALL_PYTHON=true    || true
INSTALL_AWSCLI=false;    ask_yes_no "  ¿Instalar AWS CLI v2?"                                && INSTALL_AWSCLI=true    || true
INSTALL_TAILSCALE=false; ask_yes_no "  ¿Instalar Tailscale?"                                 && INSTALL_TAILSCALE=true || true
INSTALL_ZEROTIER=false;  ask_yes_no "  ¿Instalar ZeroTier?"                                  && INSTALL_ZEROTIER=true  || true
ZEROTIER_NETWORK_ID=""
if [[ "$INSTALL_ZEROTIER" == "true" ]]; then
  read -r -p "  ID de red ZeroTier a la que unirte (déjalo en blanco para hacerlo después): " ZEROTIER_NETWORK_ID
fi

echo ""
echo "----------------------------------------------"
log "Configuración:"
echo "  Usuario:    ${TARGET_USER} ($([[ "$CREATE_USER" == "true" ]] && echo "nuevo" || echo "existente"))"
echo "  Git host:   ${GIT_HOST}"
echo "  Python:     ${INSTALL_PYTHON}"
echo "  AWS CLI:    ${INSTALL_AWSCLI}"
echo "  Tailscale:  ${INSTALL_TAILSCALE}"
echo "  ZeroTier:   ${INSTALL_ZEROTIER}"
echo "  Log:        ${LOG_FILE}"
echo "----------------------------------------------"
echo ""
ask_yes_no "  ¿Continuar con la instalación?" || { warn "Instalación cancelada."; exit 0; }

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Swap — red de seguridad en VPS con poca RAM
# ---------------------------------------------------------------------------
if ! swapon --show | grep -q .; then
  log "Sin swap activo, creando swapfile de 2G"
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  append_if_missing '/swapfile none swap sw 0 0' /etc/fstab
  ok "Swap de 2G activado."
else
  log "Swap ya activo, se omite."
fi

# ---------------------------------------------------------------------------
# 01. Usuario principal
# ---------------------------------------------------------------------------
log "01. Usuario: ${TARGET_USER}"

if [[ "$CREATE_USER" == "true" ]]; then
  if ! id "$TARGET_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$TARGET_USER"
    ok "Usuario ${TARGET_USER} creado."
  else
    warn "El usuario ${TARGET_USER} ya existe, se continúa."
  fi
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  echo "${TARGET_USER}:${XUSER_PASS}" | chpasswd
else
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  warn "Usuario existente, no se modifica su contraseña."
fi

usermod -aG sudo "$TARGET_USER"
gpasswd -d "$TARGET_USER" users 2>/dev/null || true
ok "Usuario configurado."

# ---------------------------------------------------------------------------
# 02. SSH del usuario
# ---------------------------------------------------------------------------
log "02. Configurando SSH de ${TARGET_USER}"

SSH_DIR="${TARGET_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
mkdir -p "$SSH_DIR"; touch "$AUTH_KEYS"
chmod 700 "$SSH_DIR"; chmod 600 "$AUTH_KEYS"
chown -R "${TARGET_USER}:${TARGET_USER}" "$SSH_DIR"

if [[ -n "$SSH_KEY" ]]; then
  echo "$SSH_KEY" >> "$AUTH_KEYS"
  ok "Clave SSH añadida."
fi

# ---------------------------------------------------------------------------
# 03. Endurecer SSH
# ---------------------------------------------------------------------------
log "03. Endureciendo SSH"

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak."${TIMESTAMP}"

set_sshd_option PermitRootLogin                 no
set_sshd_option PasswordAuthentication          no
set_sshd_option KbdInteractiveAuthentication    no
set_sshd_option ChallengeResponseAuthentication no
set_sshd_option PermitEmptyPasswords            no
set_sshd_option PubkeyAuthentication            yes
set_sshd_option UsePAM                          yes
set_sshd_option AllowUsers                      "${TARGET_USER}"
set_sshd_option X11Forwarding                   no
set_sshd_option AllowTcpForwarding              yes
set_sshd_option AllowAgentForwarding            no
set_sshd_option PermitTunnel                    no
set_sshd_option MaxAuthTries                    3
set_sshd_option LoginGraceTime                  30
set_sshd_option ClientAliveInterval             300
set_sshd_option ClientAliveCountMax             2

mkdir -p /run/sshd; chmod 755 /run/sshd
sshd -t; systemctl restart ssh
ok "SSH endurecido y reiniciado."

# ---------------------------------------------------------------------------
# 04. Bloquear usuario ubuntu
# ---------------------------------------------------------------------------
log "04. Bloqueando usuario ubuntu"

if id ubuntu &>/dev/null; then
  passwd -l ubuntu || true
  usermod -s /usr/sbin/nologin ubuntu || true
  truncate -s 0 /home/ubuntu/.ssh/authorized_keys 2>/dev/null || true
  rm -f /etc/sudoers.d/90-cloud-init-users || true
  for G in adm sudo docker lxd; do gpasswd -d ubuntu "$G" 2>/dev/null || true; done
  ok "Usuario ubuntu bloqueado."
else
  warn "Usuario ubuntu no encontrado, se omite."
fi

# ---------------------------------------------------------------------------
# 05. Estructura base
# ---------------------------------------------------------------------------
log "05. Estructura base"
sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/proyecto"
ok "Carpeta ~/proyecto creada."

# ---------------------------------------------------------------------------
# 06. Sistema y herramientas base
# ---------------------------------------------------------------------------
log "06. Actualizando sistema e instalando herramientas base"

# Evita que apt-daily/unattended-upgrades compitan por memoria y por el lock
# de dpkg con la actualización que lanza este script.
systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl kill --kill-who=all apt-daily.service         2>/dev/null || true
systemctl kill --kill-who=all apt-daily-upgrade.service 2>/dev/null || true
WAIT=0
while pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -x dpkg >/dev/null || pgrep -x unattended-upgr >/dev/null; do
  WAIT=$((WAIT + 1))
  [[ $WAIT -gt 60 ]] && { warn "Timeout esperando apt/dpkg, se continúa de todas formas."; break; }
  warn "Esperando a que termine un proceso apt/dpkg en curso..."
  sleep 3
done

apt update && apt upgrade -y
apt install -y \
  git curl wget unzip zip \
  ca-certificates gnupg lsb-release \
  make build-essential \
  rsync htop jq \
  openssh-server \
  ufw \
  fail2ban \
  unattended-upgrades apt-listchanges

systemctl enable --now ssh
ok "Herramientas base instaladas."

# --- fail2ban SSH ---
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled  = true
port     = ssh
filter   = sshd
maxretry = 3
findtime = 300
bantime  = 3600
EOF
systemctl enable --now fail2ban
ok "fail2ban configurado."

# --- unattended-upgrades ---
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades
ok "Actualizaciones de seguridad automáticas configuradas."

# ---------------------------------------------------------------------------
# 07. Docker CE
# ---------------------------------------------------------------------------
log "07. Instalando Docker CE"

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
gpasswd -d "$TARGET_USER" docker 2>/dev/null || true
ok "Docker instalado. ${TARGET_USER} usa 'sudo docker'."

# ---------------------------------------------------------------------------
# 08. Cockpit
# ---------------------------------------------------------------------------
log "08. Instalando Cockpit"
apt install -y cockpit cockpit-pcp
systemctl enable --now cockpit.socket
ok "Cockpit instalado. Puerto: 9090"

# ---------------------------------------------------------------------------
# 09. Toolchain Python (opcional)
# ---------------------------------------------------------------------------
if [[ "$INSTALL_PYTHON" == "true" ]]; then
  log "09. Instalando Python: uv"

  sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.local/bin"

  if [[ ! -x "${TARGET_HOME}/.local/bin/uv" ]]; then
    run_as_user "curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi

  for FILE in .bashrc .profile; do
    append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "${TARGET_HOME}/${FILE}"
  done
  chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.bashrc" "${TARGET_HOME}/.profile"

  run_as_user "uv python install 3.12"

  ok "uv instalado (gestiona versiones de Python, entornos virtuales y dependencias)."
else
  log "09. Toolchain Python omitido."
fi

# ---------------------------------------------------------------------------
# 10. AWS CLI (opcional)
# ---------------------------------------------------------------------------
if [[ "$INSTALL_AWSCLI" == "true" ]]; then
  log "10. Instalando AWS CLI v2"
  if install_awscli; then
    ok "AWS CLI instalado: $(aws --version)"
  fi
else
  log "10. AWS CLI omitido."
fi

# ---------------------------------------------------------------------------
# 11. Tailscale (opcional)
# ---------------------------------------------------------------------------
if [[ "$INSTALL_TAILSCALE" == "true" ]]; then
  log "11. Instalando Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
  ok "Tailscale instalado."
  warn "Ejecuta 'sudo tailscale up' para conectar al network."
else
  log "11. Tailscale omitido."
fi

# ---------------------------------------------------------------------------
# 12. ZeroTier (opcional)
# ---------------------------------------------------------------------------
if [[ "$INSTALL_ZEROTIER" == "true" ]]; then
  log "12. Instalando ZeroTier"
  curl -fsSL https://install.zerotier.com | bash
  if [[ -n "$ZEROTIER_NETWORK_ID" ]]; then
    zerotier-cli join "$ZEROTIER_NETWORK_ID"
    ok "ZeroTier instalado y unido a la red ${ZEROTIER_NETWORK_ID}."
  else
    ok "ZeroTier instalado."
    warn "Ejecuta 'sudo zerotier-cli join <NETWORK_ID>' para unirte a una red."
  fi
else
  log "12. ZeroTier omitido."
fi

# ---------------------------------------------------------------------------
# 13. Deploy Key
# ---------------------------------------------------------------------------
log "13. Generando Deploy Key para ${GIT_HOST}"

sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.ssh"
chmod 700 "${TARGET_HOME}/.ssh"

if [[ ! -f "${TARGET_HOME}/.ssh/deploy_key" ]]; then
  sudo -u "$TARGET_USER" ssh-keygen -t ed25519 -a 100 \
    -f "${TARGET_HOME}/.ssh/deploy_key" \
    -C "deploy-$(hostname)" \
    -N ""
fi

chmod 600 "${TARGET_HOME}/.ssh/deploy_key"
chmod 644 "${TARGET_HOME}/.ssh/deploy_key.pub"

cat > "${TARGET_HOME}/.ssh/config" <<EOF
Host ${GIT_HOST}
  HostName ${GIT_HOST}
  User git
  IdentityFile ${TARGET_HOME}/.ssh/deploy_key
  IdentitiesOnly yes
EOF

chmod 600 "${TARGET_HOME}/.ssh/config"
sudo -u "$TARGET_USER" ssh-keyscan "${GIT_HOST}" >> "${TARGET_HOME}/.ssh/known_hosts" 2>/dev/null
chmod 644 "${TARGET_HOME}/.ssh/known_hosts"
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.ssh"
ok "Deploy Key generada para ${GIT_HOST}."

# ---------------------------------------------------------------------------
# 14. Historial bash
# ---------------------------------------------------------------------------
log "14. Configurando historial bash"

append_if_missing '# Security — historial limitado sin persistencia' "${TARGET_HOME}/.bashrc"
append_if_missing 'export HISTSIZE=20'                               "${TARGET_HOME}/.bashrc"
append_if_missing 'unset HISTFILE'                                   "${TARGET_HOME}/.bashrc"

truncate -s 0 "${TARGET_HOME}/.bash_history" 2>/dev/null || true
truncate -s 0 /home/ubuntu/.bash_history     2>/dev/null || true
truncate -s 0 /root/.bash_history            2>/dev/null || true

chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.bashrc"
ok "Historial configurado."

# ---------------------------------------------------------------------------
# 15. README_started.md
# ---------------------------------------------------------------------------
log "15. Generando README_started.md"

PYTHON_SECTION=""
if [[ "$INSTALL_PYTHON" == "true" ]]; then
  PYTHON_SECTION="
## uv

\`\`\`bash
# Versiones de Python disponibles / instaladas
uv python list
uv python install 3.12
uv python uninstall 3.12

# Entornos virtuales
uv venv                           # crea .venv en el dir actual
uv venv --python 3.12
source .venv/bin/activate
deactivate

# Dependencias de proyecto (sustituye a Poetry)
uv init mi-proyecto
uv add requests
uv remove requests
uv sync                           # instala desde pyproject.toml / uv.lock
uv run python app.py

# Herramientas globales (sustituye a pipx)
uv tool install ruff
uv tool run ruff check .          # o: uvx ruff check .
\`\`\`

---
"
fi

ZEROTIER_SECTION=""
if [[ "$INSTALL_ZEROTIER" == "true" ]]; then
  ZEROTIER_SECTION="
## ZeroTier

\`\`\`bash
sudo zerotier-cli info
sudo zerotier-cli listnetworks
sudo zerotier-cli join <NETWORK_ID>
sudo zerotier-cli leave <NETWORK_ID>
\`\`\`

---
"
fi

cat > "${TARGET_HOME}/README_started.md" <<ENDREADME
# README Started

> Usuario: \`${TARGET_USER}\` · Trabajo: \`${TARGET_HOME}/proyecto\` · SSH: solo \`${TARGET_USER}\`

---

## Deploy Key

\`\`\`bash
cat ${TARGET_HOME}/.ssh/deploy_key.pub
\`\`\`

Añádela en tu plataforma Git (\`${GIT_HOST}\`):
\`Settings → Deploy Keys → Add\`
Título: \`Deploy Key $(hostname)\` — sin Write access salvo necesidad.

---

## Git

\`\`\`bash
# Clonar
git clone git@${GIT_HOST}:grupo/repo.git .
git clone -b dev git@${GIT_HOST}:grupo/repo.git .

# Básico
git status
git log --oneline -10
git diff

# Ramas
git branch -a
git checkout -b nueva-rama
git switch main

# Cambios
git add .
git add -p                        # añadir interactivo
git commit -m "mensaje"
git push origin rama
git pull

# Stash
git stash
git stash pop
git stash list

# Ver cambios entre ramas
git diff main..dev
\`\`\`

---

## Docker

\`\`\`bash
# Levantar / parar
sudo docker compose up -d
sudo docker compose down
sudo docker compose restart <servicio>

# Logs y estado
sudo docker ps
sudo docker ps -a
sudo docker logs <container>
sudo docker logs -f <container>    # follow

# Exec
sudo docker exec -it <container> bash

# Limpieza
sudo docker system prune -f
sudo docker volume prune -f
\`\`\`

---

## Cockpit

Accede desde VPN — puerto \`9090\`:
\`\`\`
https://IP_SERVIDOR:9090
\`\`\`

\`\`\`bash
sudo systemctl status cockpit.socket
\`\`\`

---
${PYTHON_SECTION}${ZEROTIER_SECTION}
## Procesos

\`\`\`bash
# Ver procesos python corriendo
ps aux | grep python
pgrep -a python

# Ver procesos sh / bash corriendo
ps aux | grep -E "bash|sh"

# Matar proceso
kill <PID>
kill -9 <PID>                     # forzar
pkill python                      # por nombre
pkill -f "mi_script.py"           # por nombre de fichero

# Buscar qué usa un puerto
sudo ss -tlnp | grep :8000
sudo lsof -i :8000
\`\`\`

---

## ufw

\`\`\`bash
# Estado
sudo ufw status verbose
sudo ufw status numbered

# Reglas básicas
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw deny 8080

# Eliminar regla
sudo ufw delete allow 8080
sudo ufw delete <número>          # con status numbered

# Activar / desactivar
sudo ufw enable
sudo ufw disable
sudo ufw reset                    # borra todas las reglas
\`\`\`

---

## fail2ban

\`\`\`bash
# Estado
sudo fail2ban-client status
sudo fail2ban-client status sshd

# IPs baneadas
sudo fail2ban-client status sshd | grep "Banned IP"

# Desbanear IP
sudo fail2ban-client set sshd unbanip <IP>

# Log
sudo tail -f /var/log/fail2ban.log
\`\`\`

---

## Buenas prácticas

- No compartir claves privadas.
- No reutilizar Deploy Keys entre servidores.
- No guardar secretos en repositorios Git.
- Usar \`chmod 600 .env\` si se usan ficheros de entorno.
- Mantener imágenes Docker actualizadas.
ENDREADME

chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/README_started.md"
chmod 640 "${TARGET_HOME}/README_started.md"
ok "README_started.md generado."

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
log "RESUMEN FINAL"
echo "=============================================="
echo ""
echo "--- Sistema ---";  uname -a
echo "--- IP ---";       hostname -I
echo "--- Disco ---";    df -h /
echo "--- RAM ---";      free -h
echo ""
echo "--- Versiones ---"
git --version; docker --version; docker compose version
[[ "$INSTALL_PYTHON"    == "true" ]] && run_as_user "uv --version" || true
[[ "$INSTALL_AWSCLI"    == "true" ]] && aws --version        || true
[[ "$INSTALL_TAILSCALE" == "true" ]] && tailscale version    || true
[[ "$INSTALL_ZEROTIER"  == "true" ]] && zerotier-cli -v      || true
echo ""
echo "--- Servicios ---"
systemctl is-active docker         && ok "docker activo"     || warn "docker inactivo"
systemctl is-active ssh            && ok "ssh activo"        || warn "ssh inactivo"
systemctl is-active cockpit.socket && ok "cockpit activo"    || warn "cockpit inactivo"
systemctl is-active fail2ban       && ok "fail2ban activo"   || warn "fail2ban inactivo"
[[ "$INSTALL_TAILSCALE" == "true" ]] && { systemctl is-active tailscaled && ok "tailscale activo" || warn "tailscale inactivo"; }
[[ "$INSTALL_ZEROTIER"  == "true" ]] && { systemctl is-active zerotier-one && ok "zerotier activo" || warn "zerotier inactivo"; }
echo ""
echo "--- Usuario ---";  id "$TARGET_USER"
echo ""
echo "--- Deploy Key pública (${GIT_HOST}) ---"
cat "${TARGET_HOME}/.ssh/deploy_key.pub"
echo ""
echo "--- Log ---"; echo "$LOG_FILE"
echo ""
ok "Bootstrap completado."

[[ "$INSTALL_PYTHON"    == "true" ]] && echo -e "\nSiguiente (Python):\n  sudo -iu ${TARGET_USER}\n  uv venv --python 3.12\n  source .venv/bin/activate"
[[ "$INSTALL_TAILSCALE" == "true" ]] && echo -e "\nSiguiente (Tailscale):\n  sudo tailscale up"
[[ "$INSTALL_ZEROTIER"  == "true" && -z "$ZEROTIER_NETWORK_ID" ]] && echo -e "\nSiguiente (ZeroTier):\n  sudo zerotier-cli join <NETWORK_ID>"
