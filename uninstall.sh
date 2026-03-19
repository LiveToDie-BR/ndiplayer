#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/ndiplayer"
CONFIG_FILE="/etc/ndiplayer.conf"
SERVICE_PLAYER="/etc/systemd/system/ndiplayer.service"
SERVICE_WEB="/etc/systemd/system/ndiplayer-web.service"
LD_CONF="/etc/ld.so.conf.d/ndiplayer-ndi.conf"

log()  { echo "[INFO] $*"; }
ok()   { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }

if [[ "$EUID" -ne 0 ]]; then
  echo "Execute com sudo: sudo ./uninstall.sh"
  exit 1
fi

log "Parando serviços..."
systemctl stop ndiplayer.service 2>/dev/null || true
systemctl stop ndiplayer-web.service 2>/dev/null || true
systemctl disable ndiplayer.service 2>/dev/null || true
systemctl disable ndiplayer-web.service 2>/dev/null || true

log "Removendo serviços..."
rm -f "${SERVICE_PLAYER}"
rm -f "${SERVICE_WEB}"
systemctl daemon-reload
systemctl reset-failed || true

log "Removendo arquivos do projeto..."
rm -rf "${APP_DIR}"
rm -f "${CONFIG_FILE}"

log "Removendo SDK NDI instalado manualmente..."
rm -f /usr/local/lib/libndi.so*
rm -f /usr/local/include/Processing.NDI.*
rm -f /usr/local/bin/ndi-*
rm -f /usr/local/bin/libndi.so*
rm -f "${LD_CONF}"
ldconfig

log "Removendo caches e logs..."
rm -rf /var/log/ndiplayer
rm -rf /tmp/ndiplayer*

ok "Desinstalação concluída."
