# install_base.sh

> Script base para preparar servidores Ubuntu nuevos de forma rápida, consistente y reutilizable.

---

## 📚 Tabla de contenidos
- [🚀 Qué hace](#-qué-hace)
- [🧠 Qué deja preparado](#-qué-deja-preparado)
- [🧾 Log de instalación](#-log-de-instalación)
- [❓ Preguntas al inicio](#-preguntas-al-inicio)
- [⚙️ Cómo usar](#️-cómo-usar)
- [🧩 Después de ejecutar](#-después-de-ejecutar)
- [🌐 Cockpit](#-cockpit)
- [📦 Estructura final](#-estructura-final-del-servidor)
- [🔐 Seguridad](#-notas-de-seguridad)
- [🧱 Filosofía](#-filosofía)
- [🚧 Futuro](#-futuras-mejoras)

---

## 🚀 Qué hace

Prepara un servidor desde cero con:

### Sistema
- `apt update` + `apt upgrade -y`
- Herramientas base

### Usuario
- Crea usuario (default `xuser`)
- Solicita contraseña
- Añade clave SSH opcional
- Permisos sudo

### Herramientas
- git
- curl
- wget
- unzip / zip
- rsync
- htop
- jq
- openssh-server
- python3 + pip + venv

### Python
- pyenv
- pyenv-virtualenv

### Contenedores
- Docker CE
- Docker Compose plugin

### Cloud
- AWS CLI v2

### Administración
- Cockpit (opcional)
- cockpit-pcp (histórico)

---

## 🧠 Qué deja preparado

### Usuario listo
- SSH
- sudo
- docker

### Python listo

```bash
pyenv install 3.12.12
pyenv virtualenv 3.12.12 myenv
pyenv activate myenv
```

### Carpeta de proyectos

```bash
/projects
```

Permisos:
- owner: usuario
- grupo: docker
- modo: `2775`

---

## 🧾 Log de instalación

Ruta:

```bash
/var/log/instalacion/
```

Ejemplo:

```bash
instalacion_20260320_101500.log
```

Incluye:
- acciones
- errores
- versiones
- servicios
- resumen sistema

---

## ❓ Preguntas al inicio

- Usuario (`xuser` por defecto)
- Instalar Cockpit (sí por defecto)
- Contraseña
- Clave SSH opcional

---

## ⚙️ Cómo usar

### Opción recomendada

```bash
curl -fsSL https://raw.githubusercontent.com/USUARIO/REPO/main/install_base.sh -o install_base.sh
chmod +x install_base.sh
sudo ./install_base.sh
```

---

## 🧩 Después de ejecutar

```bash
sudo -iu xuser

pyenv install 3.12.12
pyenv virtualenv 3.12.12 app-env
pyenv global app-env
```

---

## 🌐 Cockpit

```bash
https://IP_DEL_SERVER:9090
```

---

## 📦 Estructura final del servidor

- Usuario configurado
- `/projects`
- Docker listo
- Python versionado
- Logs en `/var/log/instalacion`

---

## 🔐 Notas de seguridad

- Pensado para servidores nuevos
- Ejecuta upgrade completo
- Cockpit abre puerto 9090

👉 Recomendado restringir acceso por firewall o VPN

---

## 🧱 Filosofía

Bootstrap automático de servidores.

Objetivo:
- consistencia
- rapidez
- trazabilidad

---

## 🚧 Futuras mejoras

- modo no interactivo
- flags (`--user`, `--no-cockpit`)
- install_project.sh
- hardening

---

## ⭐ Recomendación

Usa este script como base para todos tus servidores.

