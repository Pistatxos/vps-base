# vps-base

> Scripts de bootstrap para preparar servidores Ubuntu nuevos de forma rápida, consistente y segura.

---

## Scripts disponibles

| Script | Modo | Caso de uso |
|---|---|---|
| `install_base.sh` | Interactivo | VPS genérica, uso personal, laboratorio |
| `install_base_dev.sh` | Desatendido | VPS de desarrollo de proyecto |
| `install_base_prod.sh` | Desatendido | VPS de producción |

---

## Cuándo usar cada uno

**`install_base.sh`**
Cuando necesitas montar una máquina rápido y quieres decidir las opciones en el momento.
Instala la base completa y pregunta qué opcionales quieres.

**`install_base_dev.sh`** y **`install_base_prod.sh`**
Cuando montas un entorno de proyecto. Editas las variables de la sección `00` y lanzas.
DEV instala el toolchain Python completo. PROD solo Docker — Python va en el contenedor.

---

## Base común — los tres scripts

Todos instalan y configuran lo mismo como punto de partida:

- Sistema actualizado (`apt update` + `apt upgrade`)
- `unattended-upgrades` — parches de seguridad automáticos, sin reboot
- Herramientas base: git, curl, wget, unzip, rsync, htop, jq
- Docker CE + Compose plugin
- Cockpit (`9090`) — administración visual
- fail2ban — protección SSH (3 intentos / 5 min → ban 1 hora)
- Endurecimiento SSH completo
- Bloqueo del usuario `ubuntu`
- Deploy Key única por servidor (configurable: GitLab / GitHub / Gitea)
- Historial bash sin persistencia
- `README_started.md` — generado automáticamente en el home de `xuser` con comandos de referencia para el día a día: Git, Docker, pyenv, procesos, ufw y fail2ban.

> ⚠️ `ufw` se instala en los tres scripts pero **no se activa automáticamente**.
> Configura las reglas que necesites y actívalo manualmente cuando estés listo.
> Asegúrate de tener el puerto 22 abierto o acceso por VPN antes de ejecutar `ufw enable`.


---

## install_base.sh — interactivo

```bash
curl -fsSL https://raw.githubusercontent.com/Pistatxos/vps-base/main/install_base.sh -o install_base.sh
chmod +x install_base.sh
sudo ./install_base.sh
```

Pregunta al arrancar: usuario, contraseña, plataforma Git, si añadir clave SSH (con opción de omitir si ya estás conectado), y opcionales:

- Python completo (pyenv + pyenv-virtualenv + pipx + Poetry)
- AWS CLI v2
- Tailscale

---

## install_base_dev.sh — desatendido

```bash
curl -fsSL https://raw.githubusercontent.com/Pistatxos/vps-base/main/install_base_dev.sh -o install_base_dev.sh
chmod +x install_base_dev.sh
# Editar sección 00 antes de ejecutar
sudo ./install_base_dev.sh
```

Variables de la sección `00`:

| Variable | Descripción |
|---|---|
| `XUSER_PASS` | Contraseña para `xuser` |
| `XUSER_AUTHORIZED_KEYS` | `false` si ya estás conectado por SSH (lo más habitual). `true` si lanzas desde terminal web sin clave previa |
| `XUSER_PUBKEY` | Clave pública SSH — solo si `XUSER_AUTHORIZED_KEYS=true` |
| `GIT_HOST` | `gitlab.com` / `github.com` / tu dominio Gitea |
| `INSTALL_AWSCLI` | `true` / `false` |
| `INSTALL_TAILSCALE` | `true` / `false` |

Añade sobre la base:

- Python completo: pyenv + pyenv-virtualenv + pipx + Poetry
- AWS CLI v2 (`INSTALL_AWSCLI=true/false`)
- Tailscale (`INSTALL_TAILSCALE=true/false`)

---

## install_base_prod.sh — desatendido

```bash
curl -fsSL https://raw.githubusercontent.com/Pistatxos/vps-base/main/install_base_prod.sh -o install_base_prod.sh
chmod +x install_base_prod.sh
# Editar sección 00 antes de ejecutar
sudo ./install_base_prod.sh
```

Mismas variables que DEV en la sección `00` (`XUSER_AUTHORIZED_KEYS`, `GIT_HOST`, `INSTALL_AWSCLI`, `INSTALL_TAILSCALE`).

Diferencias respecto a DEV:

- Sin Python — va dentro del contenedor
- Sin dependencias de compilación — menor superficie de ataque
- SSH más estricto: `MaxAuthTries 2`, `LoginGraceTime 20`, `ClientAliveCountMax 1`
- Historial bash completamente desactivado (`HISTSIZE=0`) para `xuser` y `root`
- AWS CLI v2 (`INSTALL_AWSCLI=true/false`)
- Tailscale (`INSTALL_TAILSCALE=true/false`)

---

## Diferencias entre scripts

### Paquetes

| Componente | install_base | DEV | PROD |
|---|:---:|:---:|:---:|
| Herramientas base | ✓ | ✓ | ✓ (mínimas) |
| Python + pyenv + pipx + Poetry | opcional | ✓ | — |
| Docker CE | ✓ | ✓ | ✓ |
| Cockpit | ✓ | ✓ | ✓ |
| fail2ban | ✓ | ✓ | ✓ |
| unattended-upgrades | ✓ | ✓ | ✓ |
| ufw | ✓ | ✓ | ✓ |
| AWS CLI | opcional | opcional | opcional |
| Tailscale | opcional | opcional | opcional |

### Seguridad SSH

| Parámetro | install_base | DEV | PROD |
|---|:---:|:---:|:---:|
| PermitRootLogin | no | no | no |
| PasswordAuthentication | no | no | no |
| AllowTcpForwarding | yes | yes | yes |
| MaxAuthTries | 3 | 3 | 2 |
| LoginGraceTime | 30s | 30s | 20s |
| ClientAliveCountMax | 2 | 2 | 1 |
| Historial bash | 20 líneas | 20 líneas | desactivado |

---

## Seguridad

- Ningún script guarda secretos en disco ni en el log.
- Las Deploy Keys son únicas por servidor.
- `unattended-upgrades` aplica solo parches de seguridad, sin reboot automático.
- Cockpit accesible solo desde VPN (puerto `9090`).
- `ufw` se instala pero no se activa — configúralo manualmente antes de habilitarlo.
- Los `.env` con secretos deben tener `chmod 600` y nunca entrar en Git.

---

## Filosofía

Bootstrap reproducible y consistente. El objetivo es que montar un servidor nuevo tarde minutos y no dependa de memoria.

- `install_base.sh` — rapidez e interactividad
- `install_base_dev.sh` — consistencia en desarrollo
- `install_base_prod.sh` — seguridad en producción
