#!/usr/bin/env bash
# =============================================================================
#  install_base_dev.sh — Bootstrap desatendido para VPS de desarrollo
#  Probado en: Ubuntu 22.04 / 24.04
# =============================================================================
#  USO:
#    1. Edita las variables de la sección 00
#    2. chmod +x install_base_dev.sh
#    3. sudo ./install_base_dev.sh
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# 00. Variables de configuración — EDITAR ANTES DE EJECUTAR
# ---------------------------------------------------------------------------
XUSER_PASS="cambia_esta_password"            # Contraseña para xuser

# Si lanzas el script ya conectado por SSH, tu clave ya está en authorized_keys
# del usuario con el que entraste. Pon XUSER_AUTHORIZED_KEYS=false y copia
# la clave a xuser manualmente si la necesitas:
#   sudo cp ~/.ssh/authorized_keys /home/xuser/.ssh/
# Si lanzas desde una terminal web (sin clave previa), pon true y rellena XUSER_PUBKEY.
XUSER_AUTHORIZED_KEYS=false                  # true / false
XUSER_PUBKEY="ssh-ed25519 AAAA... tu@host"  # Solo si XUSER_AUTHORIZED_KEYS=true
ENTORNO="DEV"                                # Etiqueta de entorno

# Deploy Key — se genera automáticamente en ~/.ssh/deploy_key y la añades a tu repo.
GIT_HOST="gitlab.com"                        # gitlab.com / github.com / tu-gitea.com
# NOTA: Si usas Gitea u otra instancia privada, revisa que el servidor sea
# accesible desde esta VPS y ajusta el Host en ~/.ssh/config manualmente si
# el dominio no resuelve correctamente por DNS.

INSTALL_AWSCLI=false                         # true / false
INSTALL_TAILSCALE=false                      # true / false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo -e "\n\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ ERR]\033[0m $*"; exit 1; }

[[ "${EUID}" -ne 0 ]] && err "Ejecuta como root: sudo ./install_base_dev.sh"

append_if_missing() {
  local line="$1" file="$2"
  touch "$file"; grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

run_as_user() { sudo -u xuser -H bash -lc "$*"; }

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

export DEBIAN_FRONTEND=noninteractive
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# ---------------------------------------------------------------------------
# 01. Usuario principal
# ---------------------------------------------------------------------------
log "01. Usuario: xuser"

id -u xuser &>/dev/null || useradd -m -s /bin/bash xuser
TARGET_HOME="$(getent passwd xuser | cut -d: -f6)"

echo "xuser:${XUSER_PASS}" | chpasswd
usermod -aG sudo xuser
gpasswd -d xuser users 2>/dev/null || true
ok "Usuario configurado."

# ---------------------------------------------------------------------------
# 02. SSH de xuser
# ---------------------------------------------------------------------------
log "02. Configurando SSH de xuser"

mkdir -p "${TARGET_HOME}/.ssh"
touch "${TARGET_HOME}/.ssh/authorized_keys"
chmod 700 "${TARGET_HOME}/.ssh"
chmod 600 "${TARGET_HOME}/.ssh/authorized_keys"
chown -R xuser:xuser "${TARGET_HOME}/.ssh"

if [[ "$XUSER_AUTHORIZED_KEYS" == "true" ]]; then
  echo "${XUSER_PUBKEY}" >> "${TARGET_HOME}/.ssh/authorized_keys"
  ok "Clave pública añadida a authorized_keys."
else
  warn "XUSER_AUTHORIZED_KEYS=false — authorized_keys vacío. Añade tu clave manualmente después."
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
set_sshd_option AllowUsers                      xuser
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
sudo -u xuser mkdir -p "${TARGET_HOME}/proyecto"
sed -i '/^ENTORNO=/d' /etc/environment
echo "ENTORNO=${ENTORNO}" >> /etc/environment
ok "Carpeta ~/proyecto creada. ENTORNO=${ENTORNO}"

# ---------------------------------------------------------------------------
# 06. Sistema y herramientas base
# ---------------------------------------------------------------------------
log "06. Actualizando sistema e instalando herramientas base"

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

# --- fail2ban ---
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
gpasswd -d xuser docker 2>/dev/null || true
ok "Docker instalado. xuser usa 'sudo docker'."

# ---------------------------------------------------------------------------
# 08. Cockpit
# ---------------------------------------------------------------------------
log "08. Instalando Cockpit"
apt install -y cockpit cockpit-pcp
systemctl enable --now cockpit.socket
ok "Cockpit instalado. Puerto: 9090"

# ---------------------------------------------------------------------------
# 09. Toolchain Python
# ---------------------------------------------------------------------------
log "09. Instalando Python: pyenv + pipx + Poetry"

apt install -y \
  python3 python3-pip python3-venv \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev llvm libncursesw5-dev xz-utils tk-dev \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

if [[ ! -d "${TARGET_HOME}/.pyenv" ]]; then
  run_as_user "git clone https://github.com/pyenv/pyenv.git ~/.pyenv"
fi

for FILE in .bashrc .profile; do
  append_if_missing 'export PYENV_ROOT="$HOME/.pyenv"'    "${TARGET_HOME}/${FILE}"
  append_if_missing 'export PATH="$PYENV_ROOT/bin:$PATH"' "${TARGET_HOME}/${FILE}"
  append_if_missing 'eval "$(pyenv init - bash)"'         "${TARGET_HOME}/${FILE}"
done

if [[ ! -d "${TARGET_HOME}/.pyenv/plugins/pyenv-virtualenv" ]]; then
  run_as_user "git clone https://github.com/pyenv/pyenv-virtualenv.git ~/.pyenv/plugins/pyenv-virtualenv"
fi

for FILE in .bashrc .profile; do
  append_if_missing 'eval "$(pyenv virtualenv-init -)"' "${TARGET_HOME}/${FILE}"
done

chown -R xuser:xuser "${TARGET_HOME}/.pyenv"

sudo -u xuser python3 -m pip install --user pipx --break-system-packages
sudo -u xuser mkdir -p "${TARGET_HOME}/.local/bin"

for FILE in .bashrc .profile; do
  append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "${TARGET_HOME}/${FILE}"
done

run_as_user "python3 -m pipx ensurepath"
run_as_user "/home/xuser/.local/bin/pipx install poetry"
chown xuser:xuser "${TARGET_HOME}/.bashrc" "${TARGET_HOME}/.profile"
ok "Python, pyenv, pipx y Poetry instalados."

# ---------------------------------------------------------------------------
# 10. AWS CLI (opcional)
# ---------------------------------------------------------------------------
if [[ "$INSTALL_AWSCLI" == "true" ]]; then
  log "10. Instalando AWS CLI v2"
  if install_awscli; then ok "AWS CLI instalado: $(aws --version)"; fi
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
# 12. Deploy Key
# ---------------------------------------------------------------------------
log "12. Generando Deploy Key para ${GIT_HOST}"

if [[ ! -f "${TARGET_HOME}/.ssh/deploy_key" ]]; then
  sudo -u xuser ssh-keygen -t ed25519 -a 100 \
    -f "${TARGET_HOME}/.ssh/deploy_key" \
    -C "deploy-${ENTORNO}-$(hostname)" \
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
sudo -u xuser ssh-keyscan "${GIT_HOST}" >> "${TARGET_HOME}/.ssh/known_hosts" 2>/dev/null
chmod 644 "${TARGET_HOME}/.ssh/known_hosts"
chown -R xuser:xuser "${TARGET_HOME}/.ssh"
ok "Deploy Key generada para ${GIT_HOST}."

# ---------------------------------------------------------------------------
# 13. Historial bash
# ---------------------------------------------------------------------------
log "13. Configurando historial bash"

append_if_missing '# Security — historial limitado sin persistencia' "${TARGET_HOME}/.bashrc"
append_if_missing 'export HISTSIZE=20'                               "${TARGET_HOME}/.bashrc"
append_if_missing 'unset HISTFILE'                                   "${TARGET_HOME}/.bashrc"

truncate -s 0 "${TARGET_HOME}/.bash_history" 2>/dev/null || true
truncate -s 0 /home/ubuntu/.bash_history     2>/dev/null || true
truncate -s 0 /root/.bash_history            2>/dev/null || true

chown xuser:xuser "${TARGET_HOME}/.bashrc"
ok "Historial configurado."

# ---------------------------------------------------------------------------
# 14. README_started.md
# ---------------------------------------------------------------------------
log "14. Generando README_started.md"

cat > "${TARGET_HOME}/README_started.md" <<ENDREADME
# README Started — ${ENTORNO}

> Usuario: \`xuser\` · Trabajo: \`${TARGET_HOME}/proyecto\` · SSH: solo \`xuser\`

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
sudo docker logs -f <container>

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

---

## pyenv

\`\`\`bash
# Versiones disponibles
pyenv install --list | grep "3\."

# Instalar / eliminar
pyenv install 3.12.12
pyenv uninstall 3.12.12

# Versiones instaladas
pyenv versions

# Global / local
pyenv global 3.12.12
pyenv local 3.12.12               # crea .python-version en el dir actual

# Virtualenvs
pyenv virtualenv 3.12.12 mi-env
pyenv activate mi-env
pyenv deactivate
pyenv virtualenvs
pyenv virtualenv-delete mi-env
\`\`\`

---

## Procesos

\`\`\`bash
# Ver procesos python corriendo
ps aux | grep python
pgrep -a python

# Ver procesos sh / bash corriendo
ps aux | grep -E "bash|sh"

# Matar proceso
kill <PID>
kill -9 <PID>
pkill python
pkill -f "mi_script.py"

# Buscar qué usa un puerto
sudo ss -tlnp | grep :8000
sudo lsof -i :8000
\`\`\`

---

## ufw

\`\`\`bash
sudo ufw status verbose
sudo ufw status numbered

sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw deny 8080

sudo ufw delete allow 8080
sudo ufw delete <número>

sudo ufw enable
sudo ufw disable
sudo ufw reset
\`\`\`

---

## fail2ban

\`\`\`bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip <IP>
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

chown xuser:xuser "${TARGET_HOME}/README_started.md"
chmod 640 "${TARGET_HOME}/README_started.md"
ok "README_started.md generado."

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
log "RESUMEN FINAL — ${ENTORNO}"
echo "=============================================="
echo ""; echo "--- Sistema ---"; uname -a
echo ""; echo "--- IP ---";      hostname -I
echo ""; echo "--- Disco ---";   df -h /
echo ""; echo "--- RAM ---";     free -h
echo ""
echo "--- Versiones ---"
git --version; docker --version; docker compose version; python3 --version
[[ "$INSTALL_AWSCLI"    == "true" ]] && aws --version     || true
[[ "$INSTALL_TAILSCALE" == "true" ]] && tailscale version || true
echo ""
echo "--- Servicios ---"
systemctl is-active docker         && ok "docker activo"   || warn "docker inactivo"
systemctl is-active ssh            && ok "ssh activo"      || warn "ssh inactivo"
systemctl is-active cockpit.socket && ok "cockpit activo"  || warn "cockpit inactivo"
systemctl is-active fail2ban       && ok "fail2ban activo" || warn "fail2ban inactivo"
[[ "$INSTALL_TAILSCALE" == "true" ]] && { systemctl is-active tailscaled && ok "tailscale activo" || warn "tailscale inactivo"; }
echo ""
echo "--- Usuario ---"; id xuser
echo ""
echo "--- Deploy Key pública (${GIT_HOST}) ---"
cat "${TARGET_HOME}/.ssh/deploy_key.pub"
echo ""
ok "Bootstrap DEV completado."
[[ "$INSTALL_TAILSCALE" == "true" ]] && echo -e "\nSiguiente (Tailscale):\n  sudo tailscale up"
echo -e "\nSiguiente (Python):\n  sudo -iu xuser\n  pyenv install 3.12.12\n  pyenv virtualenv 3.12.12 app-env\n  pyenv global app-env"
